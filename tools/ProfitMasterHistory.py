"""Archive Profit Master SavedVariables in SQLite; never execute Lua or control WoW."""

import argparse
from contextlib import closing
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import time

from profit_master_saved import parse_saved_variables


DEFAULT_DATABASE = Path(__file__).resolve().parents[1] / "data/ProfitMaster/market-history.sqlite"
MAX_BYTES = 64 * 1024 * 1024
MAX_INTEGER = 9007199254740991
VARIANT = re.compile(r"(?:replicate:([1-9][0-9]*)|browse:([1-9][0-9]*):[0-9]+:-?[0-9]+:[0-9]+)\Z")
SCHEMA = """
CREATE TABLE sources (
    id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE
);
CREATE TABLE imports (
    source_id INTEGER NOT NULL REFERENCES sources(id), sha256 TEXT NOT NULL,
    imported_at INTEGER NOT NULL, source_mtime_ns INTEGER NOT NULL,
    source_bytes INTEGER NOT NULL, quote_rows INTEGER NOT NULL,
    trimmed_rows INTEGER NOT NULL, skipped_rows INTEGER NOT NULL,
    PRIMARY KEY (source_id, sha256)
);
CREATE TABLE items (
    source_id INTEGER NOT NULL REFERENCES sources(id), item_id INTEGER NOT NULL,
    name TEXT, vendor_price INTEGER, vendor_link TEXT, vendor_seen_at INTEGER,
    PRIMARY KEY (source_id, item_id)
);
CREATE TABLE daily_quotes (
    source_id INTEGER NOT NULL REFERENCES sources(id), market TEXT NOT NULL,
    utc_day INTEGER NOT NULL, variant TEXT NOT NULL, item_id INTEGER NOT NULL,
    low REAL NOT NULL, high REAL NOT NULL, last REAL NOT NULL,
    samples INTEGER NOT NULL, last_seen_at INTEGER NOT NULL,
    PRIMARY KEY (source_id, market, utc_day, variant)
);
CREATE INDEX quotes_by_item ON daily_quotes(source_id, market, item_id, utc_day);
CREATE TABLE daily_trimmed (
    source_id INTEGER NOT NULL REFERENCES sources(id), market TEXT NOT NULL,
    utc_day INTEGER NOT NULL, variant TEXT NOT NULL, item_id INTEGER NOT NULL,
    mean_sum REAL NOT NULL, scan_count INTEGER NOT NULL, latest_mean REAL NOT NULL,
    latest_units INTEGER NOT NULL, latest_retained_units REAL NOT NULL,
    last_seen_at INTEGER NOT NULL, method TEXT NOT NULL, tail REAL NOT NULL,
    PRIMARY KEY (source_id, market, utc_day, variant)
);
CREATE INDEX trimmed_by_item ON daily_trimmed(source_id, market, item_id, utc_day);
CREATE VIEW market_averages AS
SELECT s.path AS source, t.market, t.item_id, t.variant,
       SUM(t.mean_sum) * 1.0 / SUM(t.scan_count) AS average_copper,
       SUM(t.scan_count) AS scan_count, COUNT(*) AS days,
       MIN(t.utc_day) AS first_day, MAX(t.utc_day) AS last_day
FROM daily_trimmed AS t JOIN sources AS s ON s.id = t.source_id
GROUP BY t.source_id, t.market, t.item_id, t.variant, t.method, t.tail;
PRAGMA user_version = 1;
"""


def number(value, label, minimum=0, integer=False):
    if type(value) not in (int, float) or not math.isfinite(value) or value < minimum:
        raise ValueError(f"Invalid {label}: expected a finite number >= {minimum}")
    if integer:
        if value != int(value) or value > MAX_INTEGER:
            raise ValueError(f"Invalid {label}: expected an exact nonnegative Lua integer")
        return int(value)
    return float(value)


def table(value, label):
    if not isinstance(value, dict):
        raise ValueError(f"Invalid {label}: expected a saved table")
    return value


def item_id(variant, trimmed=False):
    if not isinstance(variant, str) or not (match := VARIANT.fullmatch(variant)):
        raise ValueError("Unsupported market-history item key")
    if trimmed and match.group(1) is None:
        raise ValueError("Browse minima are not trimmed averages")
    return number(int(match.group(1) or match.group(2)), "item ID", 1, True)


def snapshot_rows(data):
    db = table(parse_saved_variables(data).get("ProfitMasterDB"), "ProfitMasterDB")
    if type(db.get("version")) is not int or db["version"] != 1:
        raise ValueError("Unsupported ProfitMasterDB schema; source preserved")
    items, quotes, trimmed = [], [], []
    for key, value in table(db.get("items"), "items").items():
        identifier = number(key, "item ID", 1, True)
        row = table(value, "item")
        name = row.get("name")
        if name is not None and not isinstance(name, str):
            raise ValueError("Invalid item name")
        price, link, seen = row.get("vendorPrice"), row.get("vendorLink"), row.get("vendorSeenAt")
        if price is not None:
            price = number(price, "vendor price", 0, True)
            seen = number(seen, "vendor timestamp", 0, True)
            if not isinstance(link, str):
                raise ValueError("Invalid vendor link")
        else:
            link, seen = None, None
        items.append((identifier, name, price, link, seen))
    for market, value in table(db.get("markets"), "markets").items():
        if not isinstance(market, str) or not market:
            raise ValueError("Invalid market name")
        for day, bucket in table(table(value, "market").get("days"), "days").items():
            day = number(day, "UTC day", 0, True)
            bucket = table(bucket, "day bucket")
            for variant, value in table(bucket.get("records"), "daily records").items():
                identifier, row = item_id(variant), table(value, "daily quote")
                low = number(row.get("low"), "low price")
                high = number(row.get("high"), "high price", low)
                latest = number(row.get("last"), "last price", low)
                count = number(row.get("samples"), "observation count", 1, True)
                at = number(row.get("at"), "quote timestamp", 0, True)
                if low <= 0 or latest > high or at // 86400 != day:
                    raise ValueError("Inconsistent daily quote")
                quotes.append((market, day, variant, identifier, low, high, latest, count, at))
            means = table(bucket.get("trimmedMeans", {}), "trimmed means")
            if means and (bucket.get("trimmedMethod") != "unit-weighted-trimmed"
                          or type(bucket.get("trimmedTail")) not in (int, float)
                          or bucket["trimmedTail"] != 0.1):
                raise ValueError("Unsupported trimmed-average method or tail")
            for variant, value in means.items():
                identifier, row = item_id(variant, True), table(value, "trimmed mean")
                total = number(row.get("sum"), "sum of scan means")
                count = number(row.get("count"), "scan count", 1, True)
                mean = number(row.get("mean"), "latest scan mean")
                units = number(row.get("samples"), "latest scan units", 1, True)
                retained = number(row.get("retained"), "retained units")
                at = number(row.get("at"), "trimmed timestamp", 0, True)
                if total <= 0 or mean <= 0 or retained <= 0 or retained > units or at // 86400 != day:
                    raise ValueError("Inconsistent trimmed-average record")
                trimmed.append((market, day, variant, identifier, total, count, mean,
                                units, retained, at, "unit-weighted-trimmed", 0.1))
    return items, quotes, trimmed


def import_snapshot(saved_path, database_path=DEFAULT_DATABASE):
    saved_path, database_path = Path(saved_path).resolve(), Path(database_path).resolve()
    if saved_path == database_path:
        raise ValueError("The SQLite destination must differ from SavedVariables")
    # Read one bounded immutable buffer; never execute or rewrite SavedVariables.
    before = saved_path.stat()
    with saved_path.open("rb") as source:
        data = source.read(MAX_BYTES + 1)
    after = saved_path.stat()
    if len(data) > MAX_BYTES:
        raise ValueError("SavedVariables exceeds the 64 MiB import limit")
    if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns or len(data) != after.st_size:
        raise ValueError("SavedVariables changed during reading; import again after WoW finishes saving")
    items, quotes, trimmed = snapshot_rows(data)
    digest = hashlib.sha256(data).hexdigest()
    source_path = os.path.normcase(str(saved_path))
    result = dict(source=source_path, database=str(database_path), sha256=digest,
                  item_rows=len(items), quote_rows=len(quotes), trimmed_rows=len(trimmed),
                  skipped_rows=0, unchanged=False)
    database_path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(database_path, timeout=5)) as connection, connection:
        connection.execute("PRAGMA foreign_keys=ON")
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version == 0:
            if connection.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')").fetchone():
                raise ValueError("Destination contains an unrelated database")
            connection.executescript("BEGIN IMMEDIATE;\n" + SCHEMA)
        elif version != 1:
            raise ValueError("Unsupported archive schema; database preserved")
        else:
            connection.execute("BEGIN IMMEDIATE")
        connection.execute("INSERT INTO sources(path) VALUES (?) ON CONFLICT(path) DO NOTHING", (source_path,))
        source_id = connection.execute("SELECT id FROM sources WHERE path=?", (source_path,)).fetchone()[0]
        if connection.execute("SELECT 1 FROM imports WHERE source_id=? AND sha256=?", (source_id, digest)).fetchone():
            result["unchanged"] = True
            return result
        for identifier, name, price, link, seen in items:
            connection.execute("""
                INSERT INTO items VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_id,item_id) DO UPDATE SET
                    name=COALESCE(excluded.name,items.name),
                    vendor_price=COALESCE(excluded.vendor_price,items.vendor_price),
                    vendor_link=COALESCE(excluded.vendor_link,items.vendor_link),
                    vendor_seen_at=COALESCE(excluded.vendor_seen_at,items.vendor_seen_at)
                WHERE (excluded.vendor_seen_at IS NOT NULL
                  AND (items.vendor_seen_at IS NULL OR excluded.vendor_seen_at >= items.vendor_seen_at))
                  OR (items.name IS NULL AND excluded.name IS NOT NULL AND excluded.vendor_seen_at IS NULL)
                """, (source_id, identifier, name, price, link, seen))
        for row in quotes:
            market, day, variant, _, low, high, latest, count, at = row
            previous = connection.execute("""SELECT low,high,last,samples,last_seen_at FROM daily_quotes
                WHERE source_id=? AND market=? AND utc_day=? AND variant=?""",
                (source_id, market, day, variant)).fetchone()
            if previous:
                old_low, old_high, old_latest, old_count, old_at = previous
                if (at < old_at or count < old_count or low > old_low or high < old_high
                        or (count == old_count and (low, high, latest, at) != (old_low, old_high, old_latest, old_at))):
                    result["skipped_rows"] += 1
                    continue
            connection.execute("""INSERT INTO daily_quotes VALUES (?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(source_id,market,utc_day,variant) DO UPDATE SET
                low=excluded.low,high=excluded.high,last=excluded.last,samples=excluded.samples,
                last_seen_at=excluded.last_seen_at""", (source_id, *row))
        for row in trimmed:
            market, day, variant, _, total, count, mean, units, retained, at, method, tail = row
            previous = connection.execute("""SELECT mean_sum,scan_count,latest_mean,latest_units,
                latest_retained_units,last_seen_at,method,tail FROM daily_trimmed
                WHERE source_id=? AND market=? AND utc_day=? AND variant=?""",
                (source_id, market, day, variant)).fetchone()
            if previous:
                old_total, old_count, _, _, _, old_at, old_method, old_tail = previous
                if (at < old_at or count < old_count or total < old_total or (method, tail) != (old_method, old_tail)
                        or (count == old_count and row[4:] != previous)):
                    result["skipped_rows"] += 1
                    continue
            connection.execute("""INSERT INTO daily_trimmed VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(source_id,market,utc_day,variant) DO UPDATE SET
                mean_sum=excluded.mean_sum,scan_count=excluded.scan_count,latest_mean=excluded.latest_mean,
                latest_units=excluded.latest_units,latest_retained_units=excluded.latest_retained_units,
                last_seen_at=excluded.last_seen_at""", (source_id, *row))
        connection.execute("INSERT INTO imports VALUES (?,?,?,?,?,?,?,?)",
                           (source_id, digest, int(time.time()), after.st_mtime_ns, len(data),
                            len(quotes), len(trimmed), result["skipped_rows"]))
    return result


def connect_readonly(database_path=DEFAULT_DATABASE):
    path = Path(database_path).resolve()
    connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5)
    connection.execute("PRAGMA query_only=ON")
    allowed = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_FUNCTION, sqlite3.SQLITE_RECURSIVE}
    connection.set_authorizer(lambda action, *_: sqlite3.SQLITE_OK if action in allowed else sqlite3.SQLITE_DENY)
    deadline = time.monotonic() + 5
    connection.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
    connection.row_factory = sqlite3.Row
    return connection


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    commands = parser.add_subparsers(dest="command", required=True)
    importer = commands.add_parser("import", help="Import the last completed WoW save")
    importer.add_argument("--saved", required=True, type=Path)
    commands.add_parser("summary", help="Show archive row counts")
    query = commands.add_parser("query", help="Run read-only SQL (at most 1000 returned rows)")
    query.add_argument("--sql", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "import":
            print(json.dumps(import_snapshot(args.saved, args.database), indent=2))
        else:
            with closing(connect_readonly(args.database)) as connection:
                if args.command == "summary":
                    result = {name: connection.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
                              for name in ("sources", "imports", "items", "daily_quotes", "daily_trimmed", "market_averages")}
                else:
                    rows = connection.execute(args.sql).fetchmany(1001)
                    result = {"rows": [dict(row) for row in rows[:1000]], "truncated": len(rows) > 1000}
                print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"Profit Master history: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
