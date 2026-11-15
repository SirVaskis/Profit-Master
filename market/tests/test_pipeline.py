import copy
import gzip
import json
from pathlib import Path
import sqlite3
import tempfile
import time
import unittest
import uuid

from market.adapters import rows_from_saved
from market.collector import connect_state, enqueue, read_stable, upload_pending, validate_endpoint
from market.contract import canonical, record_key, validate_batch
from tools.profit_master_saved import parse_saved_variables, SavedVariablesError

AT = 1794751200
DAY = AT // 86400


def pm_save(price=50, samples=1, debug="first"):
    return ('''ProfitMasterDB = {version=1,items={[6040]={name="Golden Scale Bracers",vendorPrice=100}},
      markets={["FixtureRealm"]={days={[%d]={records={["replicate:6040"]={low=40,high=80,last=%s,samples=%d,at=%d}}}}}}}
      ProfitMasterDebugDB = {entries={"%s"}}''' % (DAY, price, samples, AT, debug)).encode()


def one_batch():
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "ProfitMaster.lua"
        path.write_bytes(pm_save())
        db = connect_state(Path(temp) / "state.sqlite")
        enqueue(db, path)
        batch = json.loads(gzip.decompress(db.execute("SELECT body FROM outbox").fetchone()[0]))
        db.close()
        return batch


class AdapterTests(unittest.TestCase):
    def test_profit_master_preserves_daily_semantics(self):
        addon, version, rows = rows_from_saved(pm_save())
        self.assertEqual((addon, version, len(rows)), ("ProfitMaster", 1, 1))
        self.assertEqual(rows[0]["metric"], "daily_quote")
        self.assertNotIn("sample_units", rows[0])
        self.assertNotIn("mean_sum", rows[0])
        self.assertEqual(rows[0]["vendor_copper"], 100)

    def test_profit_top_distinguishes_floor_and_vwap_and_ignores_personal_data(self):
        data = Path("market/tests/fixtures/ProfitTop.lua").read_bytes()
        addon, version, rows = rows_from_saved(data)
        self.assertEqual((addon, version, len(rows)), ("ProfitTop", 3, 2))
        by_type = {row["metric"]: row for row in rows}
        self.assertNotIn("sample_units", by_type["browse_floor"])
        self.assertEqual(by_type["listing_vwap"]["sample_units"], 5)
        self.assertEqual(by_type["listing_vwap"]["units_kind"], "sampled_units")
        self.assertNotIn(b"personal-purchase", canonical(rows))
        self.assertEqual(rows_from_saved(data,include_scan_times=True)[3],[1794664800,1794751200])

    def test_future_and_mixed_schemas_rejected(self):
        for data in (pm_save().replace(b"version=1", b"version=99"), b"ProfitTopDB={version=4,markets={}}",
                     pm_save() + b"ProfitTopDB={version=3,markets={}}"):
            with self.assertRaises(ValueError):
                rows_from_saved(data)

    def test_no_lua_execution_and_existing_parser_default_remains_restricted(self):
        with self.assertRaises(SavedVariablesError):
            rows_from_saved(b'ProfitTopDB=(function() os.execute("boom") end)()')
        with self.assertRaises(SavedVariablesError):
            parse_saved_variables(b"ProfitTopDB={}")

    def test_fractional_prices_and_zero_vendor_value(self):
        data = pm_save().replace(b"last=50", b"last=50.125").replace(b"vendorPrice=100", b"vendorPrice=0")
        row = rows_from_saved(data)[2][0]
        self.assertEqual(row["price"], "50.125")
        self.assertEqual(row["vendor_copper"], 0)

    def test_category_metadata_preserves_client_classification(self):
        data = pm_save().replace(b'vendorPrice=100', b'vendorPrice=100,classID=4,subclassID=3,className="Armor",subclassName="Mail"')
        row = rows_from_saved(data)[2][0]
        self.assertEqual((row['class_id'],row['subclass_id'],row['class_name'],row['subclass_name']), (4,3,'Armor','Mail'))

    def test_profit_top_legacy_fallback_retains_metric(self):
        data = b'ProfitTopDB={version=3,markets={R={items={["6040:0:0:0"]={l={{1794751200,50,"id",1}},f={{1794664800,40}}}}}}}'
        rows = rows_from_saved(data)[2]
        self.assertEqual({r["metric"] for r in rows}, {"browse_floor", "listing_unit"})

    def test_trimmed_rollups_require_valid_method(self):
        data = pm_save().replace(b"records={", b'trimmedMethod="unit-weighted-trimmed",trimmedTail=0.1,trimmedMeans={["replicate:6040"]={sum=100,count=2,mean=50,samples=100,at=1794751200}},records={')
        rows = rows_from_saved(data)[2]
        mean = next(r for r in rows if r["metric"] == "trimmed_mean")
        self.assertEqual(mean["scan_count"], 2)
        self.assertEqual(mean["mean_sum"], "100")
        with self.assertRaises(ValueError):
            rows_from_saved(data.replace(b"trimmedTail=0.1", b"trimmedTail=0.2"))
        timed = data.replace(b'records={',b'scanTimes={[1794751200]=true},records={')
        self.assertEqual(rows_from_saved(timed,include_scan_times=True)[3],[1794751200])


class OutboxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "ProfitMaster.lua"
        self.path.write_bytes(pm_save())
        self.state = Path(self.temp.name) / "queue.sqlite"
        self.db = connect_state(self.state)

    def tearDown(self):
        self.db.close()
        self.temp.cleanup()

    def test_source_unchanged_and_no_private_path_or_log_upload(self):
        before = self.path.read_bytes()
        enqueue(self.db, self.path)
        body = gzip.decompress(self.db.execute("SELECT body FROM outbox").fetchone()[0])
        self.assertEqual(self.path.read_bytes(), before)
        self.assertNotIn(str(self.path).encode(), body)
        self.assertNotIn(b"first", body)
        self.assertEqual(self.db.execute("SELECT count(*) FROM outbox").fetchone()[0], 1)
        self.assertTrue(enqueue(self.db, self.path)["unchanged"])

    def test_pending_upload_survives_restart_and_debug_only_change_has_no_delta(self):
        enqueue(self.db, self.path)
        self.db.close()
        self.db = connect_state(self.state)
        self.assertEqual(self.db.execute("SELECT count(*) FROM outbox").fetchone()[0], 1)
        self.path.write_bytes(pm_save(debug="second"))
        result = enqueue(self.db, self.path)
        self.assertEqual(result["changed_records"], 0)
        self.assertEqual(self.db.execute("SELECT count(*) FROM outbox").fetchone()[0], 1)

    def test_changed_daily_slot_queues_new_value_with_same_identity(self):
        enqueue(self.db, self.path)
        self.path.write_bytes(pm_save(price=60, samples=2))
        enqueue(self.db, self.path)
        bodies = [json.loads(gzip.decompress(row[0])) for row in self.db.execute("SELECT body FROM outbox ORDER BY created")]
        self.assertEqual(len(bodies), 2)
        self.assertEqual(bodies[0]["records"][0]["key"], bodies[1]["records"][0]["key"])
        self.assertEqual(bodies[1]["records"][0]["price"], "60")

    def test_timestamp_only_updates_are_uploaded_without_new_price_slots(self):
        enqueue(self.db,self.path)
        self.path.write_bytes(pm_save().replace(b'records={',b'scanTimes={[1794751200]=true},records={'))
        self.assertEqual(enqueue(self.db,self.path)['queued'],1)
        batches=[json.loads(gzip.decompress(r[0])) for r in self.db.execute('SELECT body FROM outbox ORDER BY created')]
        self.assertEqual(batches[0]['records'],batches[1]['records'])
        self.assertEqual(batches[1]['scan_times'],[1794751200])

    def test_offline_failure_keeps_pending_part(self):
        enqueue(self.db, self.path)
        with self.assertRaises(ValueError):
            upload_pending(self.db, "http://127.0.0.1:1", "a" * 40)
        self.assertEqual(self.db.execute("SELECT count(*) FROM outbox").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT attempts FROM outbox").fetchone()[0], 1)

    def test_remote_cleartext_and_credentials_in_url_are_rejected(self):
        for url in ("http://example.com", "https://user:password@example.com", "https://example.com?token=x"):
            with self.assertRaises(ValueError):
                validate_endpoint(url)
        self.assertTrue(validate_endpoint("http://localhost:8787").endswith("/api/v1/uploads"))


class ContractTests(unittest.TestCase):
    def test_batch_and_record_validation(self):
        batch = one_batch()
        self.assertEqual(validate_batch(batch), batch)
        for mutate in (
            lambda b: b.update(saved_schema=True),
            lambda b: b.update(schema_version=2),
            lambda b: b.update(part_count=2),
            lambda b: b["records"][0].update(key="not-a-key"),
            lambda b: b["records"][0].update(price="NaN"),
            lambda b: b["records"][0].update(price=50.0),
            lambda b: b["records"][0].update(metric="listing_vwap"),
            lambda b: b["records"][0].update(account="private"),
            lambda b: b["records"][0].update(observed_at=int(time.time()) + 200000),
        ):
            changed = copy.deepcopy(batch)
            mutate(changed)
            with self.subTest(changed=changed), self.assertRaises((ValueError, TypeError)):
                validate_batch(changed)


if __name__ == "__main__":
    unittest.main()
