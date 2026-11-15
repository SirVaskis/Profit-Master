"""Versioned market records shared by the dependency-free client and receiver."""

import hashlib
import json
import math
import re
import time
import uuid
from decimal import Decimal, InvalidOperation

SCHEMA_VERSION = 1
PART_SIZE = 2000
MAX_PRICE = 9_007_199_254_740_991
KEY = re.compile(r"(?:replicate:[1-9][0-9]*|browse:[1-9][0-9]*:[0-9]+:-?[0-9]+:[0-9]+|[1-9][0-9]*:[0-9]+:-?[0-9]+:[0-9]+)\Z")
METRICS = {"daily_quote", "trimmed_mean", "browse_floor", "listing_vwap", "listing_unit"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def integer(value, label, minimum=0, maximum=MAX_PRICE):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"Invalid {label}")
    return value


def price(value, label="price"):
    if type(value) not in (int, float, str, Decimal) or isinstance(value, bool):
        raise ValueError(f"Invalid {label}")
    if len(str(value)) > 80:
        raise ValueError(f"Invalid {label}")
    try:
        result = Decimal(str(value))
        if not result.is_finite() or not 0 <= result <= MAX_PRICE or not -32 <= result.as_tuple().exponent <= 16:
            raise ValueError(f"Invalid {label}")
        return format(result, "f")
    except InvalidOperation as error:
        raise ValueError(f"Invalid {label}") from error


def text(value, label, maximum=160):
    if not isinstance(value, str) or not value or len(value) > maximum or any(ord(c) < 32 for c in value):
        raise ValueError(f"Invalid {label}")
    return value


def record_key(addon, market, variant, slot):
    return digest([addon, market, variant, slot])


def validate_record(row, addon):
    required = {"key", "market", "variant", "slot", "item_id", "metric", "observed_at", "price"}
    optional = {"name", "vendor_copper", "low", "high", "samples", "sample_units", "units_kind", "mean_sum", "scan_count",
                "class_id", "subclass_id", "class_name", "subclass_name"}
    if not isinstance(row, dict) or not required <= row.keys() or row.keys() - required - optional:
        raise ValueError("Invalid observation fields")
    for name in ("market", "variant", "slot"):
        text(row[name], name)
    if not KEY.fullmatch(row["variant"]):
        raise ValueError("Invalid item variant")
    identifier = integer(row["item_id"], "item ID", 1, 10_000_000)
    key_id = int(row["variant"].split(":")[1 if row["variant"].startswith(("browse:", "replicate:")) else 0])
    if key_id != identifier or row["key"] != record_key(addon, row["market"], row["variant"], row["slot"]):
        raise ValueError("Observation identity mismatch")
    metric = row["metric"]
    allowed = {"daily_quote", "trimmed_mean"} if addon == "ProfitMaster" else {"browse_floor", "listing_vwap", "listing_unit"}
    if metric not in allowed:
        raise ValueError("Metric does not match the source addon")
    integer(row["observed_at"], "observation time", 1_000_000_000, int(time.time()) + 86400)
    if not isinstance(row["price"], str):
        raise ValueError("Wire prices must be decimal strings")
    value = Decimal(price(row["price"]))
    if value <= 0:
        raise ValueError("Asking price must be positive")
    for name in ("low", "high", "mean_sum"):
        if name in row:
            if not isinstance(row[name], str):
                raise ValueError("Wire prices must be decimal strings")
            price(row[name], name)
    for name in ("samples", "scan_count", "sample_units"):
        if name in row:
            integer(row[name], name, 1)
    if "vendor_copper" in row:
        integer(row["vendor_copper"], "vendor price")
    if "name" in row:
        text(row["name"], "item name", 256)
    category = {"class_id", "subclass_id", "class_name", "subclass_name"}
    if category & row.keys():
        if not category <= row.keys():
            raise ValueError("Incomplete item category")
        integer(row['class_id'], 'item class', 0, 100)
        integer(row['subclass_id'], 'item subclass', 0, 1000)
        text(row['class_name'], 'class name')
        text(row['subclass_name'], 'subclass name')
    if "sample_units" in row:
        if row.get("units_kind") not in ("snapshot_units", "sampled_units"):
            raise ValueError("Units must describe their sampling method")
    elif "units_kind" in row:
        raise ValueError("Unit method without a quantity")
    if metric == "daily_quote":
        if not {"low", "high", "samples"} <= row.keys() or not 0 < Decimal(row["low"]) <= value <= Decimal(row["high"]):
            raise ValueError("Invalid daily quote range")
        if row["slot"] != f"day:{row['observed_at'] // 86400}":
            raise ValueError("Daily quote timestamp mismatch")
    if metric == "trimmed_mean":
        if not {"mean_sum", "scan_count", "sample_units"} <= row.keys() or not row["variant"].startswith("replicate:"):
            raise ValueError("Incomplete trimmed scan rollup")
        if row.get("units_kind") != "snapshot_units" or row["slot"] != f"trimmed:{row['observed_at'] // 86400}":
            raise ValueError("Invalid trimmed scan rollup")
    return row


def validate_batch(batch):
    fields = {"schema_version", "batch_id", "producer_id", "source_id", "addon", "saved_schema", "snapshot_sha256",
              "snapshot_written_ns", "part_index", "part_count", "snapshot_record_count", "capture_kind", "records"}
    if not isinstance(batch, dict) or set(batch) - {'scan_times'} != fields or type(batch["schema_version"]) is not int or batch["schema_version"] != 1:
        raise ValueError("Unsupported upload schema")
    addon = batch["addon"]
    if addon not in ("ProfitMaster", "ProfitTop") or type(batch["saved_schema"]) is not int or batch["saved_schema"] != (1 if addon == "ProfitMaster" else 3):
        raise ValueError("Unsupported addon schema")
    for name in ("batch_id", "producer_id", "source_id"):
        if not isinstance(batch[name], str) or str(uuid.UUID(batch[name])) != batch[name]:
            raise ValueError("Invalid upload identity")
    if not re.fullmatch(r"[a-f0-9]{64}", batch["snapshot_sha256"]):
        raise ValueError("Invalid snapshot hash")
    integer(batch["snapshot_written_ns"], "snapshot revision", 1, 2**63 - 1)
    times = batch.get('scan_times', [])
    if not isinstance(times, list) or len(times) > 10000:
        raise ValueError('Invalid scan timestamps')
    for at in times:
        integer(at, 'scan time', 1_000_000_000, int(time.time()) + 86400)
    if times != sorted(set(times)):
        raise ValueError('Scan timestamps must be unique and ordered')
    count = integer(batch["snapshot_record_count"], "snapshot size", 1, 1_000_000)
    parts = integer(batch["part_count"], "part count", 1, 1000)
    index = integer(batch["part_index"], "part index", 0, parts - 1)
    if parts != math.ceil(count / PART_SIZE) or batch["capture_kind"] != "saved_history":
        raise ValueError("Invalid upload partition")
    rows = batch["records"]
    expected = min(PART_SIZE, count - index * PART_SIZE)
    if not isinstance(rows, list) or len(rows) != expected:
        raise ValueError("Incomplete upload part")
    if batch["batch_id"] != str(uuid.uuid5(uuid.UUID(batch["source_id"]), f"{addon}/{batch['snapshot_sha256']}/{index}")):
        raise ValueError("Batch identity mismatch")
    seen = set()
    for row in rows:
        validate_record(row, addon)
        if row["key"] in seen:
            raise ValueError("Duplicate observation identity")
        seen.add(row["key"])
    return batch
