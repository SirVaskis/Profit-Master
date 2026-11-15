"""Offline archive-import regressions; fixtures never touch live SavedVariables."""

from __future__ import annotations

import copy
import importlib
from pathlib import Path
import sqlite3
import tempfile
import unittest


def lua_literal(value):
    """Write only literal values that the real SavedVariables serializer emits."""
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + '"'
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, dict):
        return "{\n" + ",\n".join(f"[{lua_literal(key)}] = {lua_literal(item)}" for key, item in value.items()) + "\n}"
    raise TypeError(type(value).__name__)


def bucket(day, mean_sum=30, count=2, *, latest=20, units=100, retained=80, variant="replicate:123", quotes=None):
    at = day * 86400 + 100
    if quotes is None:
        quotes = {variant: {"low": 10, "high": 20, "last": 20, "samples": count, "at": at}}
    return {
        "records": quotes,
        "count": len(quotes),
        "trimmedMeans": {variant: {"sum": mean_sum, "count": count, "mean": latest,
                                   "samples": units, "retained": retained, "at": at}},
        "trimmedScans": count,
        "trimmedMethod": "unit-weighted-trimmed",
        "trimmedTail": 0.1,
    }


def snapshot(days=None, *, markets=None, items=None):
    return {"version": 1, "minimumProfit": 3,
            "items": items if items is not None else {123: {"name": "Test armor", "vendorPrice": 100,
                "vendorLink": "item:123", "vendorSeenAt": 20000 * 86400 + 100}},
            "markets": markets if markets is not None else {"RealmPvE": {"days": days or {20000: bucket(20000)}}}}


class ProfitMasterHistoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.history = importlib.import_module("ProfitMasterHistory")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="profit-master-history-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.saved = self.root / "ProfitMaster.lua"
        self.database = self.root / "archive #100%.sqlite"

    def write(self, value, path=None):
        target = path or self.saved
        target.write_text("-- Temporary native-shaped test data only.\nProfitMasterDB = " + lua_literal(value) + "\n", encoding="utf-8")
        return target

    def ingest(self, value, path=None):
        summary = self.history.import_snapshot(self.write(value, path), self.database)
        self.assertIsInstance(summary, dict)
        return summary

    def rows(self, query, parameters=()):
        connection = self.history.connect_readonly(self.database)
        try:
            return [tuple(row) for row in connection.execute(query, parameters)]
        finally:
            connection.close()

    def logical_database(self):
        # Inspect integrity through a native read-only connection; the public
        # query connection deliberately rejects PRAGMAs used by iterdump.
        connection = sqlite3.connect(self.database.as_uri() + "?mode=ro", uri=True)
        try:
            return connection.execute("PRAGMA user_version").fetchone()[0], tuple(connection.iterdump())
        finally:
            connection.close()

    def test_repeated_a_b_a_import_is_idempotent(self):
        first = snapshot()
        second = copy.deepcopy(first)
        row = second["markets"]["RealmPvE"]["days"][20000]
        row["records"]["replicate:123"].update(low=5, high=30, last=30, samples=3, at=20000 * 86400 + 200)
        row["trimmedMeans"]["replicate:123"].update(sum=60, count=3, mean=30, at=20000 * 86400 + 200)
        row["trimmedScans"] = 3
        self.ingest(first)
        self.ingest(second)
        after_second = self.logical_database()
        self.ingest(first)
        self.assertEqual(after_second, self.logical_database())
        self.assertEqual([(2,)], self.rows("SELECT COUNT(*) FROM imports"))
        self.assertEqual([(60, 3, 30)], self.rows("SELECT mean_sum, scan_count, latest_mean FROM daily_trimmed"))
        self.assertEqual([(5, 30, 30, 3)], self.rows("SELECT low, high, last, samples FROM daily_quotes"))

    def test_cumulative_replacement_never_adds_the_same_day_twice(self):
        self.ingest(snapshot())
        later = snapshot({20000: bucket(20000, 90, 4, latest=40)})
        later["markets"]["RealmPvE"]["days"][20000]["records"]["replicate:123"].update(high=40, last=40)
        self.ingest(later)
        self.assertEqual([(90, 4)], self.rows("SELECT mean_sum, scan_count FROM daily_trimmed"))
        self.assertEqual([(4,)], self.rows("SELECT samples FROM daily_quotes"))
        self.assertEqual([(22.5, 4)], self.rows("SELECT average_copper, scan_count FROM market_averages"))

    def test_absent_old_days_remain_in_the_archive(self):
        self.ingest(snapshot({19900: bucket(19900, 10, 1, latest=10), 20000: bucket(20000)}))
        self.ingest(snapshot({20001: bucket(20001, 40, 1, latest=40)}))
        self.assertEqual([(19900,), (20000,), (20001,)], self.rows("SELECT utc_day FROM daily_trimmed ORDER BY utc_day"))
        self.assertEqual([(3, 19900, 20001)], self.rows("SELECT days, first_day, last_day FROM market_averages"))

    def test_average_weights_each_scan_not_each_day_or_latest_unit_count(self):
        self.ingest(snapshot({20000: bucket(20000, 100, 1, latest=100, units=1000000, retained=800000),
                              20001: bucket(20001, 30, 3, latest=10, units=1, retained=0.8)}))
        self.assertEqual([(32.5, 4, 2, 20000, 20001)], self.rows(
            "SELECT average_copper, scan_count, days, first_day, last_day FROM market_averages"))

    def test_fractional_copper_is_preserved(self):
        data = snapshot({20000: bucket(20000, 1.5, 2, latest=0.75, units=3, retained=2.4),
                         20001: bucket(20001, 0.75, 1, latest=0.75, units=1, retained=0.8)})
        for day in data["markets"]["RealmPvE"]["days"].values():
            day["records"]["replicate:123"].update(low=0.5, high=1.25, last=0.75)
        self.ingest(data)
        self.assertEqual([(0.75, 3)], self.rows("SELECT average_copper, scan_count FROM market_averages"))
        self.assertEqual([(0.5, 1.25, 0.75)], self.rows("SELECT low, high, last FROM daily_quotes LIMIT 1"))
        self.assertEqual([(2.4,)], self.rows("SELECT latest_retained_units FROM daily_trimmed WHERE utc_day = ?", (20000,)))

    def test_source_market_and_quote_variants_stay_separate(self):
        at = 20000 * 86400 + 100
        variants = {"replicate:123": {"low": 10, "high": 20, "last": 20, "samples": 2, "at": at},
                    "browse:123:20:-7:0": {"low": 100, "high": 100, "last": 100, "samples": 1, "at": at},
                    "browse:123:30:7:0": {"low": 200, "high": 200, "last": 200, "samples": 1, "at": at}}
        data = snapshot(markets={"RealmA": {"days": {20000: bucket(20000, 20, 2, latest=10, quotes=variants)}},
                                 "RealmB": {"days": {20000: bucket(20000, 60, 2, latest=30)}}})
        self.ingest(data)
        self.ingest(data, self.root / "Second account.lua")
        self.assertEqual([(2,)], self.rows("SELECT COUNT(*) FROM sources"))
        self.assertEqual([(2,)], self.rows("SELECT COUNT(*) FROM imports"))
        self.assertEqual([(8,)], self.rows("SELECT COUNT(*) FROM daily_quotes"))
        self.assertEqual([("RealmA", 10.0), ("RealmA", 10.0), ("RealmB", 30.0), ("RealmB", 30.0)], self.rows(
            "SELECT market, average_copper FROM market_averages ORDER BY market, source"))
        self.assertEqual([("replicate:123",)], self.rows("SELECT DISTINCT variant FROM market_averages"))
        self.assertEqual([(2,)], self.rows("SELECT COUNT(*) FROM items WHERE item_id = ?", (123,)))

    def test_known_zero_vendor_price_is_distinct_from_missing(self):
        self.ingest(snapshot(items={123: {"name": "Unsellable", "vendorPrice": 0, "vendorLink": "item:123", "vendorSeenAt": 100},
                                   456: {"name": "Vendor unknown"}}))
        self.assertEqual([(123, 0), (456, None)], self.rows("SELECT item_id, vendor_price FROM items ORDER BY item_id"))
        self.ingest(snapshot(items={123: {"name": "Currently uncached"}, 456: {"name": "Vendor unknown"}}))
        self.assertEqual([(123, 0), (456, None)], self.rows("SELECT item_id, vendor_price FROM items ORDER BY item_id"))

    def test_import_never_rewrites_saved_variables(self):
        self.write(snapshot())
        content, modified = self.saved.read_bytes(), self.saved.stat().st_mtime_ns
        self.history.import_snapshot(self.saved, self.database)
        self.assertEqual(content, self.saved.read_bytes())
        self.assertEqual(modified, self.saved.stat().st_mtime_ns)

    def test_name_only_metadata_can_fill_an_initially_empty_item(self):
        self.ingest(snapshot(items={123: {}}))
        self.assertEqual([(None, None)], self.rows("SELECT name, vendor_price FROM items WHERE item_id = 123"))
        self.ingest(snapshot(items={123: {"name": "Learned later"}}))
        self.assertEqual([("Learned later", None, None, None)], self.rows(
            "SELECT name, vendor_price, vendor_link, vendor_seen_at FROM items WHERE item_id = 123"))
        self.ingest(snapshot(items={123: {}}))
        self.assertEqual([("Learned later", None)], self.rows("SELECT name, vendor_price FROM items WHERE item_id = 123"))

    def test_regressed_or_conflicting_cumulative_rows_are_preserved_and_reported(self):
        baseline = snapshot({20000: bucket(20000, 60, 3, latest=30)})
        self.ingest(baseline)
        expected_trimmed = self.rows("SELECT mean_sum, scan_count, latest_mean, last_seen_at FROM daily_trimmed")
        expected_quotes = self.rows("SELECT low, high, last, samples, last_seen_at FROM daily_quotes")
        for label in ("older", "lower_count", "equal_count_changed_sum"):
            with self.subTest(conflict=label):
                data = copy.deepcopy(baseline)
                day = data["markets"]["RealmPvE"]["days"][20000]
                quote, trimmed = day["records"]["replicate:123"], day["trimmedMeans"]["replicate:123"]
                if label == "older":
                    quote["at"] -= 50
                    trimmed["at"] -= 50
                elif label == "lower_count":
                    quote.update(samples=2, at=quote["at"] + 50)
                    trimmed.update(count=2, sum=40, at=trimmed["at"] + 50)
                else:
                    quote.update(low=9, at=quote["at"] + 50)
                    trimmed.update(sum=61, at=trimmed["at"] + 50)
                summary = self.ingest(data)
                self.assertGreater(summary.get("skipped_rows", 0), 0, summary)
                self.assertEqual(expected_trimmed, self.rows("SELECT mean_sum, scan_count, latest_mean, last_seen_at FROM daily_trimmed"))
                self.assertEqual(expected_quotes, self.rows("SELECT low, high, last, samples, last_seen_at FROM daily_quotes"))

    def test_invalid_input_leaves_existing_database_unchanged(self):
        self.ingest(snapshot())
        original = self.logical_database()
        malformed = ["ProfitMasterDB = {", "ProfitMasterDB = { version = 1 }; os.execute(\"never run\")"]
        for text in malformed:
            with self.subTest(parse=text):
                self.saved.write_text(text, encoding="utf-8")
                with self.assertRaises((ValueError, RuntimeError)):
                    self.history.import_snapshot(self.saved, self.database)
                self.assertEqual(original, self.logical_database())
        for label in ("version", "late_row", "method", "tail"):
            with self.subTest(schema=label):
                data = snapshot({20000: bucket(20000), 20001: bucket(20001)})
                later = data["markets"]["RealmPvE"]["days"][20001]
                if label == "version":
                    data["version"] = 2
                elif label == "late_row":
                    later["trimmedMeans"]["replicate:123"]["count"] = -1
                elif label == "method":
                    later["trimmedMethod"] = "unknown"
                else:
                    later["trimmedTail"] = 0.2
                self.write(data)
                with self.assertRaises((ValueError, RuntimeError)):
                    self.history.import_snapshot(self.saved, self.database)
                self.assertEqual(original, self.logical_database())

    def test_readonly_connection_denies_writes(self):
        self.ingest(snapshot())
        original = self.logical_database()
        connection = self.history.connect_readonly(self.database)
        try:
            self.assertEqual(1, connection.execute("SELECT COUNT(*) FROM daily_trimmed").fetchone()[0])
            for sql in ("DELETE FROM imports", "UPDATE items SET vendor_price = 999", "DROP TABLE daily_quotes"):
                with self.subTest(statement=sql), self.assertRaises(sqlite3.DatabaseError):
                    connection.execute(sql)
        finally:
            connection.close()
        self.assertEqual(original, self.logical_database())

    def test_sqlite_failure_rolls_back_prior_writes_and_import_ledger(self):
        self.ingest(snapshot())
        # A test-only trigger rejects the second day's quote after the importer
        # has already updated item metadata and the first cumulative day.
        connection = sqlite3.connect(self.database)
        try:
            connection.execute("""CREATE TRIGGER force_import_rollback
                BEFORE INSERT ON daily_quotes WHEN NEW.utc_day = 20001
                BEGIN SELECT RAISE(ABORT, 'forced transactional rollback'); END""")
            connection.commit()
        finally:
            connection.close()
        original = self.logical_database()
        updated = snapshot({20000: bucket(20000, 60, 3, latest=30), 20001: bucket(20001)},
                           items={123: {"name": "Changed in failed transaction", "vendorPrice": 999,
                                        "vendorLink": "item:123", "vendorSeenAt": 20001 * 86400 + 100}})
        updated["markets"]["RealmPvE"]["days"][20000]["records"]["replicate:123"].update(low=5, high=30, last=30)
        self.write(updated)
        with self.assertRaises(sqlite3.Error) as failure:
            self.history.import_snapshot(self.saved, self.database)
        self.assertIn("forced transactional rollback", str(failure.exception))
        self.assertEqual(original, self.logical_database())
        self.assertEqual([(100,)], self.rows("SELECT vendor_price FROM items WHERE item_id = 123"))
        self.assertEqual([(1,)], self.rows("SELECT COUNT(*) FROM imports"))

    def test_lua_strings_and_sql_parameters_preserve_data_without_execution(self):
        market = "Realm'); DROP TABLE items; --"
        name = 'Hero\'s "Focus"; DROP TABLE imports; -- Æ'
        hostile_path = self.root / "source's [1]; DROP TABLE sources; --.lua"
        data = snapshot(markets={market: {"days": {20000: bucket(20000)}}},
                        items={123: {"name": name, "vendorPrice": 100, "vendorLink": "item:123", "vendorSeenAt": 100}})
        self.ingest(data, hostile_path)
        self.assertEqual([(name,)], self.rows("SELECT name FROM items WHERE item_id = ?", (123,)))
        self.assertEqual([(15.0,)], self.rows("SELECT average_copper FROM market_averages WHERE market = ? AND variant = ?", (market, "replicate:123")))
        self.assertEqual([(1,)], self.rows("SELECT COUNT(*) FROM sources"))
        self.assertEqual([(1,)], self.rows("SELECT COUNT(*) FROM imports"))


if __name__ == "__main__":
    unittest.main()
