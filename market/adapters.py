"""Interpret each addon's persisted history without executing or changing Lua."""

from .contract import integer, price, record_key, text, validate_record
from tools.profit_master_saved import parse_saved_variables


def table(value, label):
    if not isinstance(value, dict):
        raise ValueError(f"Invalid {label}")
    return value


def rows_from_saved(data, *, include_scan_times=False):
    roots = parse_saved_variables(data, allowed_roots={"ProfitMasterDB", "ProfitMasterDebugDB", "ProfitMasterDisenchantDB", "ProfitTopDB"})
    # One file/adapter at a time: a mixed-root backup is ambiguous and unsupported.
    pm, pt = roots.get("ProfitMasterDB"), roots.get("ProfitTopDB")
    if pm is not None and pt is not None:
        raise ValueError("Select one addon's SavedVariables file, not a combined backup")
    if pm is not None:
        rows = profit_master(table(pm, "ProfitMasterDB"))
        times = sorted({at for market in pm['markets'].values() for day in market['days'].values()
                        for at, complete in table(day.get('scanTimes', {}), 'scan timestamps').items() if complete is True})
        return ("ProfitMaster",1,rows,times) if include_scan_times else ("ProfitMaster",1,rows)
    if pt is not None:
        rows = profit_top(table(pt, "ProfitTopDB"))
        times = sorted({row['observed_at'] for row in rows})
        return ("ProfitTop",3,rows,times) if include_scan_times else ("ProfitTop",3,rows)
    raise ValueError("No supported addon history was found")


def observation(addon, market, variant, slot, item_id, metric, at, value, **extra):
    row = dict(key=record_key(addon, market, variant, slot), market=market, variant=variant, slot=slot,
               item_id=item_id, metric=metric, observed_at=integer(at, "observation timestamp", 1), price=price(value), **extra)
    return validate_record(row, addon)


def metadata_fields(metadata):
    extra = {}
    if metadata.get('name'):
        extra['name'] = text(metadata['name'], 'name', 256)
    if metadata.get('vendorPrice') is not None:
        extra['vendor_copper'] = integer(metadata['vendorPrice'], 'vendor price')
    names = {'class_id': 'classID', 'subclass_id': 'subclassID', 'class_name': 'className', 'subclass_name': 'subclassName'}
    if all(name in metadata for name in names.values()):
        extra.update({wire: metadata[saved] for wire, saved in names.items()})
    return extra


def profit_master(db):
    if type(db.get("version")) is not int or db["version"] != 1:
        raise ValueError("Unsupported ProfitMasterDB schema; supported version is 1")
    items, result = table(db.get("items"), "item catalog"), []
    for market, data in table(db.get("markets"), "markets").items():
        text(market, "market")
        for day, bucket in table(table(data, "market").get("days"), "days").items():
            integer(day, "UTC day", 0)
            bucket = table(bucket, "day")
            for variant, raw in table(bucket.get("records"), "daily records").items():
                parts = text(variant, "variant").split(":")
                identifier = int(parts[1])
                raw = table(raw, "daily quote")
                metadata = items.get(identifier, {})
                extra = dict(low=price(raw["low"]), high=price(raw["high"]), samples=integer(raw["samples"], "sample count", 1),
                             **metadata_fields(metadata))
                result.append(observation("ProfitMaster", market, variant, f"day:{day}", identifier,
                                          "daily_quote", raw["at"], raw["last"], **extra))
            means = table(bucket.get("trimmedMeans", {}), "trimmed means")
            if means and (bucket.get("trimmedMethod") != "unit-weighted-trimmed" or bucket.get("trimmedTail") != 0.1):
                raise ValueError("Unsupported trimmed-average definition")
            for variant, raw in means.items():
                identifier = int(text(variant, "variant").split(":")[1])
                result.append(observation("ProfitMaster", market, variant, f"trimmed:{day}", identifier,
                    "trimmed_mean", raw["at"], raw["mean"], mean_sum=price(raw["sum"]),
                    scan_count=integer(raw["count"], "scan count", 1),
                    sample_units=integer(raw["samples"], "snapshot units", 1), units_kind="snapshot_units",
                    **metadata_fields(items.get(identifier, {}))))
    return sorted(result, key=lambda row: row["key"])


def profit_top(db):
    if type(db.get("version")) is not int or db["version"] != 3:
        raise ValueError("Unsupported ProfitTopDB schema; supported version is 3 (ProfitTop 0.1.13)")
    result = []
    for market, data in table(db.get("markets"), "markets").items():
        text(market, "market")
        for variant, raw in table(table(data, "market").get("items", {}), "items").items():
            identifier = int(text(variant, "variant").split(":")[0])
            raw = table(raw, "item history")
            snapshots = table(raw.get("s", {}), "snapshots")
            if snapshots:
                for point in snapshots.values():
                    point = table(point, "snapshot")
                    source = point.get(3)
                    if source == "p":
                        continue  # Personal purchases are not market asks.
                    metric = {"b": "browse_floor", "l": "listing_vwap"}.get(source)
                    if metric is None:
                        raise ValueError("Unknown ProfitTop snapshot source")
                    extra = {}
                    if source == "l" and point.get(5) is not None:
                        extra.update(sample_units=integer(point[5], "VWAP sample units", 1), units_kind="sampled_units")
                    # Same timestamp slot is mutable in ProfitTop (browse -> listing,
                    # or a lower price). Replace it; do not count it as a new scan.
                    result.append(observation("ProfitTop", market, variant, f"snapshot:{point[1]}", identifier,
                                              metric, point[1], point[2], **extra))
            else:
                # Current v3 saves can retain unmigrated l/f history. Preserve its
                # meaning; never derive a trimmed mean from floors or individual asks.
                for name, metric in (("f", "browse_floor"), ("l", "listing_unit")):
                    for point in table(raw.get(name, {}), "legacy history").values():
                        point = table(point, "legacy point")
                        slot = f"{name}:{point[1]}:{point.get(3, '')}"
                        result.append(observation("ProfitTop", market, variant, slot, identifier, metric, point[1], point[2]))
    by_key = {}
    for row in result:
        previous = by_key.get(row["key"])
        if previous is not None and previous != row:
            raise ValueError("Conflicting ProfitTop observations in the same slot")
        by_key[row["key"]] = row
    return sorted(by_key.values(), key=lambda row: row["key"])
