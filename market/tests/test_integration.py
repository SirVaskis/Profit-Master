"""Opt-in tests against the disposable native local stack, not a remote server.

Run with MARKET_INTEGRATION=1. Only this run's synthetic producer IDs are removed.
"""

import copy
from decimal import Decimal
import gzip
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid

import psycopg

from market.collector import connect_state, enqueue, upload_pending
from market.contract import canonical, record_key, validate_batch
from market.database import ingest
from market.tests.test_pipeline import one_batch, pm_save


@unittest.skipUnless(os.getenv("MARKET_INTEGRATION") == "1", "Requires the explicit local-stack test flag")
class LocalStackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.settings = dict(line.split("=", 1) for line in (root / ".env").read_text().splitlines() if "=" in line)
        state = json.loads((root / ".local/processes.json").read_text())
        cls.base = f"http://127.0.0.1:{state['apiPort']}"
        cls.grafana = f"http://127.0.0.1:{state['grafanaPort']}"
        cls.pgport = state['postgresPort']

    def setUp(self):
        self.producer = str(uuid.uuid4())

    def connection(self, role="market_admin"):
        setting = {"market_admin": "ADMIN_PASSWORD", "market_writer": "WRITER_PASSWORD", "market_reader": "READER_PASSWORD"}[role]
        return psycopg.connect(host="127.0.0.1", port=self.pgport, user=role,
            password=self.settings[setting], dbname="profit_market", autocommit=True)

    def tearDown(self):
        with self.connection() as db:
            db.execute("DELETE FROM market.scan_times WHERE producer_id=%s", (self.producer,))
            db.execute("DELETE FROM market.observations WHERE producer_id=%s", (self.producer,))
            db.execute("DELETE FROM market.uploads WHERE producer_id=%s", (self.producer,))
            db.execute("DELETE FROM market.item_catalog WHERE item_id=9900101 AND item_name='IntegrationFixture item'")

    def batch(self, price="50", revision=None):
        batch = one_batch()
        batch['producer_id'] = self.producer
        batch['source_id'] = str(uuid.uuid5(uuid.UUID(self.producer), 'fixture'))
        batch['snapshot_sha256'] = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        batch['batch_id'] = str(uuid.uuid5(uuid.UUID(batch['source_id']), f"ProfitMaster/{batch['snapshot_sha256']}/0"))
        batch['snapshot_written_ns'] = revision or time.time_ns()
        row = batch['records'][0]
        row['market'] = 'IntegrationFixture-Alliance'
        row['key'] = record_key('ProfitMaster', row['market'], row['variant'], row['slot'])
        row['price'] = price
        return validate_batch(batch)

    def post(self, data, token=None, encoding='gzip'):
        headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (token or self.settings['UPLOAD_TOKEN'])}
        if encoding:
            headers['Content-Encoding'] = encoding
        request = urllib.request.Request(self.base + '/api/v1/uploads', data=data, headers=headers, method='POST')
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.read().decode()

    def send(self, batch):
        return self.post(gzip.compress(canonical(batch)))

    def counts(self):
        with self.connection() as db:
            return tuple(db.execute(f"SELECT count(*) FROM market.{table} WHERE producer_id=%s", (self.producer,)).fetchone()[0]
                         for table in ('uploads', 'observations'))

    def test_authenticated_atomic_and_idempotent_upload(self):
        batch = self.batch(price='50.125')
        batch['scan_times'] = [batch['records'][0]['observed_at']]
        code, answer = self.send(batch)
        self.assertEqual((code, answer['status']), (200, 'accepted'))
        self.assertEqual(self.counts(), (1, 1))
        self.assertEqual(self.send(batch)[1]['status'], 'duplicate')
        self.assertEqual(self.counts(), (1, 1))
        with self.connection() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM market.scan_times WHERE producer_id=%s',(self.producer,)).fetchone(),(1,))
        altered = copy.deepcopy(batch)
        altered['records'][0]['price'] = '60'
        self.assertEqual(self.send(altered)[0], 409)
        with self.connection() as db:
            self.assertEqual(db.execute('SELECT price FROM market.observations WHERE producer_id=%s', (self.producer,)).fetchone(), (Decimal('50.125'),))

    def test_rejections_never_store_rows(self):
        body = canonical(self.batch())
        self.assertEqual(self.post(gzip.compress(body), token='wrong')[0], 401)
        self.assertEqual(self.post(b'{"duplicate":1,"duplicate":2}', encoding=None)[0], 422)
        self.assertEqual(self.post(gzip.compress(b' ' * (8 * 1024 * 1024 + 1)))[0], 413)
        self.assertEqual(self.post(gzip.compress(body) + b'trailing')[0], 422)
        changed = json.loads(body)
        changed['records'][0]['price'] = '1e-999999999999999'
        self.assertEqual(self.send(changed)[0], 422)
        self.assertEqual(self.counts(), (0, 0))

    def test_older_revisions_cannot_replace_newer_daily_slots(self):
        new = self.batch('70', 1000000000000000002)
        old = self.batch('50', 1000000000000000001)
        self.assertEqual(self.send(new)[0], 200)
        self.assertEqual(self.send(old)[0], 200)
        self.assertEqual(self.counts(), (2, 1))
        with self.connection() as db:
            self.assertEqual(db.execute('SELECT price FROM market.observations WHERE producer_id=%s', (self.producer,)).fetchone(), (Decimal('70'),))

    def test_database_failure_rolls_back_whole_batch(self):
        # Deliberately bypass wire validation to force a database CHECK failure
        # after a valid row, proving that the upload ledger rolls back too.
        batch = self.batch()
        invalid = copy.deepcopy(batch['records'][0])
        batch['scan_times'] = [batch['records'][0]['observed_at']]
        invalid.update(key='f' * 64, price='0')
        batch['records'].append(invalid)
        with self.connection('market_writer') as writer:
            dsn = psycopg.conninfo.make_conninfo(writer.info.dsn, password=self.settings['WRITER_PASSWORD'])
            with self.assertRaises(psycopg.errors.CheckViolation):
                ingest(batch, 'integration', dsn=dsn)
        self.assertEqual(self.counts(), (0, 0))
        with self.connection() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM market.scan_times WHERE producer_id=%s',(self.producer,)).fetchone(),(0,))

    def test_reader_is_restricted_to_reporting(self):
        with self.connection('market_reader') as reader:
            self.assertEqual(reader.execute("SHOW statement_timeout").fetchone(), ('5s',))
            self.assertIsInstance(reader.execute('SELECT count(*) FROM reporting.price_history').fetchone()[0], int)
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                reader.execute('SELECT * FROM market.uploads LIMIT 1')
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                reader.execute("UPDATE market.item_catalog SET item_name='no' WHERE item_id=0")
            self.assertFalse(reader.execute("SELECT has_table_privilege('reporting.price_history','INSERT')").fetchone()[0])

    def test_average_view_uses_mean_sums_and_excludes_quotes(self):
        batch = self.batch()
        row = batch['records'][0]
        row.update(metric='trimmed_mean',slot=f"trimmed:{row['observed_at']//86400}",mean_sum='120',scan_count=2,
                   sample_units=100,units_kind='snapshot_units')
        row['key'] = record_key(batch['addon'],row['market'],row['variant'],row['slot'])
        self.assertEqual(self.send(validate_batch(batch))[0],200)
        self.assertEqual(self.send(self.batch())[0],200)
        with self.connection('market_reader') as db:
            rows = db.execute("SELECT average_copper,observed_at FROM reporting.average_history WHERE source_id=%s", (batch['source_id'],)).fetchall()
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0][0],Decimal('60'))
        self.assertEqual(int(rows[0][1].timestamp()),row['observed_at'])

    def test_profit_top_uses_shared_category_catalog_without_fabricating_prices(self):
        batch = self.batch()
        row = batch['records'][0]
        row.update(item_id=9900101,variant='replicate:9900101',name='IntegrationFixture item',
                   class_id=7,subclass_id=5,class_name='Trade Goods',subclass_name='Cloth')
        row['key'] = record_key(batch['addon'],row['market'],row['variant'],row['slot'])
        self.assertEqual(self.send(validate_batch(batch))[0],200)
        pt = copy.deepcopy(batch)
        pt.update(addon='ProfitTop',saved_schema=3,source_id=str(uuid.uuid5(uuid.UUID(self.producer),'pt')))
        pt['batch_id'] = str(uuid.uuid5(uuid.UUID(pt['source_id']), f"ProfitTop/{pt['snapshot_sha256']}/0"))
        point = pt['records'][0]
        point.update(variant='9900101:0:0:0',slot=f"snapshot:{point['observed_at']}",metric='listing_vwap',price='75')
        for key in ('class_id','subclass_id','class_name','subclass_name','name','low','high','samples'):
            point.pop(key)
        point['key'] = record_key('ProfitTop',point['market'],point['variant'],point['slot'])
        self.assertEqual(self.send(validate_batch(pt))[0],200)
        with self.connection('market_reader') as db:
            value = db.execute('SELECT average_copper,class_id,subclass_id FROM reporting.average_history WHERE source_id=%s',(pt['source_id'],)).fetchone()
        self.assertEqual(value,(Decimal('75'),7,5))

    def test_collector_offline_restart_and_successful_ack(self):
        with tempfile.TemporaryDirectory() as temp:
            path, state = Path(temp) / 'ProfitMaster.lua', Path(temp) / 'outbox.sqlite'
            path.write_bytes(pm_save())
            db = connect_state(state)
            db.execute("UPDATE settings SET value=? WHERE name='producer_id'", (self.producer,))
            db.commit()
            enqueue(db, path)
            with self.assertRaises(ValueError):
                upload_pending(db, 'http://127.0.0.1:1', self.settings['UPLOAD_TOKEN'])
            db.close()
            db = connect_state(state)
            try:
                self.assertEqual(db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)
                answer = upload_pending(db, self.base, self.settings['UPLOAD_TOKEN'], force=True)
                self.assertEqual(answer, dict(acknowledged_parts=1, pending_parts=0))
                self.assertEqual(self.counts(), (1, 1))
            finally:
                db.close()

    def test_grafana_queries_real_profit_master_history(self):
        with urllib.request.urlopen(self.grafana + '/api/health') as response:
            self.assertEqual(json.load(response)['database'], 'ok')
        request = urllib.request.Request(self.grafana + '/api/ds/query', method='POST',
            headers={'Content-Type': 'application/json'}, data=canonical(dict(queries=[dict(
                refId='A', datasource=dict(type='grafana-postgresql-datasource', uid='profitmarket-postgres'),
                format='time_series', rawQuery=True, rawSql="SELECT observed_at AS time,price::double precision AS value FROM reporting.price_history WHERE addon='ProfitMaster' AND market_key NOT LIKE '%Fixture%' AND item_id=6040 ORDER BY observed_at")], to=str(int(time.time()*1000)))))
        with urllib.request.urlopen(request) as response:
            result = json.load(response)['results']['A']
        self.assertNotIn('error', result)
        values = [v for frame in result['frames'] for v in frame['data']['values'][-1] if v is not None]
        self.assertGreater(len(values), 0)


if __name__ == '__main__':
    unittest.main()
