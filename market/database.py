"""Atomic PostgreSQL ingestion. Credentials never enter uploader payloads."""

from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import os

import psycopg

from .contract import canonical


class Conflict(ValueError):
    pass


def ingest(batch, contributor, dsn=None):
    body_hash = hashlib.sha256(canonical(batch)).hexdigest()
    with psycopg.connect(dsn or os.environ["DATABASE_URL"], connect_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL statement_timeout='15s'")
            cursor.execute("""INSERT INTO market.uploads
                (batch_id,contributor,producer_id,source_id,addon,snapshot_sha256,revision_ns,
                 part_index,part_count,snapshot_record_count,record_count,body_sha256)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (batch_id) DO NOTHING RETURNING batch_id""",
                (batch["batch_id"], contributor, batch["producer_id"], batch["source_id"], batch["addon"],
                 batch["snapshot_sha256"], batch["snapshot_written_ns"], batch["part_index"], batch["part_count"],
                 batch["snapshot_record_count"], len(batch["records"]), body_hash))
            if cursor.fetchone() is None:
                cursor.execute("SELECT body_sha256,contributor FROM market.uploads WHERE batch_id=%s", (batch["batch_id"],))
                previous = cursor.fetchone()
                if previous != (body_hash, contributor):
                    raise Conflict("Upload identity already exists with different contents")
                return dict(status="duplicate", batch_id=batch["batch_id"], record_count=len(batch["records"]))
            values = []
            catalog = {}
            times = batch.get('scan_times', [])
            if times:
                cursor.executemany("INSERT INTO market.scan_times VALUES (%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING",
                    [(contributor,batch['producer_id'],batch['source_id'],batch['addon'],datetime.fromtimestamp(at,timezone.utc)) for at in times])
            for row in batch["records"]:
                if 'class_id' in row:
                    catalog[row['item_id']] = (row['item_id'],row.get('name'),row['class_id'],row['subclass_id'],
                                              row['class_name'],row['subclass_name'],batch['snapshot_written_ns'])
                values.append((contributor,batch["producer_id"],batch["source_id"],row["key"],batch["addon"],
                    row["market"],row["item_id"],row["variant"],row["metric"],
                    datetime.fromtimestamp(row["observed_at"],timezone.utc),Decimal(row["price"]),row.get("name"),
                    row.get("vendor_copper"), row.get("low"),row.get("high"),row.get("samples"),
                    row.get("sample_units"),row.get("units_kind"),row.get("mean_sum"),row.get("scan_count"),
                    batch["snapshot_written_ns"],batch["batch_id"]))
            if catalog:
                cursor.executemany("""INSERT INTO market.item_catalog VALUES (%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT(item_id) DO UPDATE SET item_name=COALESCE(excluded.item_name,item_catalog.item_name),
                    class_id=excluded.class_id,subclass_id=excluded.subclass_id,class_name=excluded.class_name,
                    subclass_name=excluded.subclass_name,revision_ns=excluded.revision_ns
                    WHERE excluded.revision_ns>=item_catalog.revision_ns""", list(catalog.values()))
            cursor.executemany("""INSERT INTO market.observations VALUES
                (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (contributor,producer_id,source_id,record_key) DO UPDATE SET
                  metric=excluded.metric,observed_at=excluded.observed_at,price=excluded.price,
                  item_name=excluded.item_name,vendor_copper=excluded.vendor_copper,
                  low=excluded.low,high=excluded.high,samples=excluded.samples,sample_units=excluded.sample_units,
                  units_kind=excluded.units_kind,mean_sum=excluded.mean_sum,scan_count=excluded.scan_count,
                  revision_ns=excluded.revision_ns,batch_id=excluded.batch_id
                WHERE excluded.revision_ns>market.observations.revision_ns""", values)
        # Connection context commits before a response leaves this function.
        return dict(status="accepted", batch_id=batch["batch_id"], record_count=len(values))
