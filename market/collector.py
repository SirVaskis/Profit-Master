"""Windows/Linux collector: stable read, durable SQLite outbox, acknowledged uploads."""

import argparse
from contextlib import closing
import gzip
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from .adapters import rows_from_saved
from .contract import PART_SIZE, canonical, validate_batch

MAX_FILE = 64 * 1024 * 1024


def read_stable(path):
    path = Path(path).resolve()
    before = path.stat()
    with path.open("rb") as source:
        data = source.read(MAX_FILE + 1)
    after = path.stat()
    if len(data) > MAX_FILE:
        raise ValueError("SavedVariables exceeds 64 MiB")
    if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size) or len(data) != after.st_size:
        raise ValueError("SavedVariables changed during reading; waiting for a completed save")
    return data, after.st_mtime_ns


def discover(game_root):
    root = Path(game_root) / "WTF" / "Account"
    return sorted(path for name in ("ProfitMaster.lua", "ProfitTop.lua") for path in root.glob(f"*/SavedVariables/{name}"))


def connect_state(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=10)
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version == 0:
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='table'").fetchone():
            db.close()
            raise ValueError("Collector state contains an unrelated database")
        db.executescript("""
            CREATE TABLE settings (name TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE files (source_id TEXT NOT NULL, sha TEXT NOT NULL, PRIMARY KEY(source_id,sha));
            CREATE TABLE outbox (id TEXT PRIMARY KEY, body BLOB NOT NULL, created REAL NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0, next_try REAL NOT NULL DEFAULT 0);
            PRAGMA user_version=1;
        """)
        db.execute("INSERT INTO settings VALUES ('producer_id',?)", (str(uuid.uuid4()),))
        db.commit()
    elif version not in (1, 2):
        db.close()
        raise ValueError("Unsupported collector-state schema")
    if version in (0, 1):
        with db:
            db.execute("CREATE TABLE IF NOT EXISTS record_digests (source_id TEXT NOT NULL,record_key TEXT NOT NULL,sha TEXT NOT NULL,PRIMARY KEY(source_id,record_key))")
            db.execute("PRAGMA user_version=2")
    return db


def enqueue(db, path):
    path = Path(path).resolve()
    data, written = read_stable(path)
    producer = db.execute("SELECT value FROM settings WHERE name='producer_id'").fetchone()[0]
    source = str(uuid.uuid5(uuid.UUID(producer), os.path.normcase(str(path))))
    sha = hashlib.sha256(data).hexdigest()
    if db.execute("SELECT 1 FROM files WHERE source_id=? AND sha=?", (source, sha)).fetchone():
        return {"file": path.name, "unchanged": True, "queued": 0}
    addon, version, records, scan_times = rows_from_saved(data, include_scan_times=True)
    if not records:
        return {"file": path.name, "addon": addon, "records": 0, "queued": 0}
    available = len(records)
    first_record = records[0]
    time_key = 'scan_times:' + source
    time_hash = hashlib.sha256(canonical(scan_times)).hexdigest()
    previous_time_hash = db.execute('SELECT value FROM settings WHERE name=?', (time_key,)).fetchone()
    previous = dict(db.execute("SELECT record_key,sha FROM record_digests WHERE source_id=?", (source,)))
    changes = [(row, hashlib.sha256(canonical(row)).hexdigest()) for row in records]
    changes = [(row, sha) for row, sha in changes if previous.get(row["key"]) != sha]
    if not changes and scan_times and previous_time_hash != (time_hash,):
        # A timestamp-only update uses an existing row as its carrier. The
        # server replaces the same slot; it does not invent a price observation.
        changes = [(first_record, hashlib.sha256(canonical(first_record)).hexdigest())]
    records = [row for row, _ in changes]
    parts = (len(records) + PART_SIZE - 1) // PART_SIZE
    # Record all parts and the source hash atomically. A crash can leave either
    # the old queue or this complete queue, never an acknowledged missing part.
    with db:
        for index in range(parts):
            batch = dict(schema_version=1, producer_id=producer, source_id=source, addon=addon, saved_schema=version,
                snapshot_sha256=sha, snapshot_written_ns=written, part_index=index, part_count=parts,
                snapshot_record_count=len(records), capture_kind="saved_history",
                batch_id=str(uuid.uuid5(uuid.UUID(source), f"{addon}/{sha}/{index}")),
                records=records[index * PART_SIZE:(index + 1) * PART_SIZE])
            batch['scan_times'] = scan_times
            validate_batch(batch)
            db.execute("INSERT OR IGNORE INTO outbox(id,body,created) VALUES (?,?,?)",
                       (batch["batch_id"], gzip.compress(canonical(batch), mtime=0), time.time() + index / 1000))
        db.execute("INSERT OR IGNORE INTO files VALUES (?,?)", (source, sha))
        db.execute('INSERT INTO settings VALUES (?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value', (time_key,time_hash))
        db.executemany("INSERT INTO record_digests VALUES (?,?,?) ON CONFLICT(source_id,record_key) DO UPDATE SET sha=excluded.sha",
                       [(source, row["key"], row_sha) for row, row_sha in changes])
    return {"file": path.name, "addon": addon, "available_records": available, "changed_records": len(records), "queued": parts, "unchanged": False}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Upload keys must never follow a cross-host redirect.


def validate_endpoint(url, allow_insecure=False):
    parsed = urllib.parse.urlsplit(url)
    if parsed.username or parsed.password or parsed.query or parsed.fragment or not parsed.hostname:
        raise ValueError("Use a server URL without embedded credentials, query, or fragment")
    try:
        loopback = parsed.hostname == "localhost" or ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:
        loopback = False
    if parsed.scheme != "https" and not (parsed.scheme == "http" and (loopback or allow_insecure)):
        raise ValueError("Remote uploads require HTTPS; HTTP is permitted on loopback for local testing")
    return url.rstrip("/") + "/api/v1/uploads"


def upload_pending(db, server_url, token, *, allow_insecure=False, force=False):
    endpoint = validate_endpoint(server_url, allow_insecure)
    if not isinstance(token, str) or len(token) < 32:
        raise ValueError("Configure an upload token of at least 32 characters")
    sent = 0
    opener = urllib.request.build_opener(NoRedirect)
    # FIFO is intentional: a newer snapshot cannot pass an older queued revision.
    for identity, body, attempts, next_try in db.execute("SELECT id,body,attempts,next_try FROM outbox ORDER BY created,id").fetchall():
        if not force and next_try > time.time():
            break
        request = urllib.request.Request(endpoint, data=body, method="POST", headers={
            "Authorization": "Bearer " + token, "Content-Type": "application/json", "Content-Encoding": "gzip"})
        try:
            with opener.open(request, timeout=20) as response:
                answer = json.loads(response.read(16385))
                if response.status != 200 or answer.get("batch_id") != identity or answer.get("status") not in ("accepted", "duplicate"):
                    raise ValueError("The server did not acknowledge this upload; it remains queued")
            with db:
                db.execute("DELETE FROM outbox WHERE id=?", (identity,))
                db.execute("INSERT INTO settings VALUES ('last_upload',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value", (str(int(time.time())),))
            sent += 1
        except (urllib.error.URLError, OSError, ValueError) as error:
            with db:
                db.execute("UPDATE outbox SET attempts=attempts+1,next_try=? WHERE id=?",
                           (time.time() + min(300, 2 ** min(attempts + 1, 8)), identity))
            if isinstance(error, urllib.error.HTTPError):
                error.close()
                raise ValueError(f"Upload rejected (HTTP {error.code}); data remains queued") from error
            raise ValueError("Upload was not acknowledged; data remains queued for retry") from error
    return {"acknowledged_parts": sent, "pending_parts": db.execute("SELECT COUNT(*) FROM outbox").fetchone()[0]}


def config_paths(config):
    paths = [Path(path).expanduser() for path in config.get("saved_files", [])]
    if config.get("game_root"):
        paths.extend(discover(config["game_root"]))
    return sorted(set(path.resolve() for path in paths))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--state", type=Path, default=Path(os.getenv("LOCALAPPDATA", str(Path.home() / ".local/share"))) / "ProfitMarket" / "collector.sqlite")
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Validate and count saved data without uploading")
    inspect.add_argument("files", nargs="+", type=Path)
    commands.add_parser("sync", help="Queue changed saves and upload once")
    commands.add_parser("watch", help="Watch completed writes until Ctrl+C; no game input")
    commands.add_parser("status", help="Show pending uploads")
    args = parser.parse_args(argv)
    try:
        if args.command == "inspect":
            for path in args.files:
                data, _ = read_stable(path)
                addon, version, records = rows_from_saved(data)
                print(json.dumps(dict(file=path.name, addon=addon, saved_schema=version, records=len(records),
                                     metrics=sorted({row['metric'] for row in records}))))
            return 0
        if args.command == "status":
            with closing(connect_state(args.state)) as db:
                print(json.dumps(dict(pending_parts=db.execute("SELECT COUNT(*) FROM outbox").fetchone()[0],
                                      last_upload=db.execute("SELECT value FROM settings WHERE name='last_upload'").fetchone())))
            return 0
        if not args.config:
            raise ValueError("Specify --config with server_url, token, and game_root or saved_files")
        config = json.loads(args.config.read_text(encoding="utf-8-sig"))
        signatures = {}
        db = connect_state(args.state)
        try:
            while True:
                paths = config_paths(config)
                if not paths and args.command == "sync":
                    print("No supported SavedVariables found; check game_root or saved_files.", file=sys.stderr)
                for path in paths:
                    try:
                        stat = path.stat()
                        signature = (stat.st_size, stat.st_mtime_ns)
                        if signatures.get(path) != signature:
                            print(json.dumps(enqueue(db, path)), flush=True)
                            signatures[path] = signature
                    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
                        if args.command == "sync":
                            raise
                        print(f"{path.name}: {error}; will retry after the next poll", file=sys.stderr, flush=True)
                try:
                    outcome = upload_pending(db, config["server_url"], config.get("token") or os.getenv("PROFITMARKET_UPLOAD_TOKEN", ""),
                        allow_insecure=config.get("allow_insecure_http") is True)
                    if args.command == "sync" or outcome["acknowledged_parts"]:
                        print(json.dumps(outcome), flush=True)
                except ValueError as error:
                    if args.command == "sync":
                        raise
                    print(str(error), file=sys.stderr, flush=True)
                if args.command == "sync":
                    return 0
                time.sleep(max(2, int(config.get("poll_seconds", 5))))
        finally:
            db.close()
    except KeyboardInterrupt:
        return 0
    except (ValueError, OSError, KeyError, TypeError, IndexError, sqlite3.Error) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
