-- Pure SavedVariables/history checks. Does not open or control WoW.
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local DAY = 86400
local now = 20000 * DAY + 100
time = function() return now end
issecretvalue = function(value) return value == "SECRET" end
local addon = {}
assert(loadfile("addons/ProfitMaster/History.lua"))("ProfitMaster", addon)
local history = addon.History
local db = assert(history.Initialize(nil))
check(db.version == 1 and next(db.items) == nil and next(db.markets) == nil, "new database is empty and versioned")
check(not history.BeginScan("browse", now), "unknown market cannot pollute a shared default bucket")
history.SetMarket("PvE")
history.BeginScan("browse", now)
check(history.Summary():find("0/30 days", 1, true), "empty scan is not a collected day")
local function browse(id, price, quantity, level, suffix)
    return { itemKey = { itemID = id, itemLevel = level or 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0 },
        minPrice = price, totalQuantity = quantity or 1 }
end
local scan = assert(history.BeginScan("browse", now))
history.RecordBrowse(scan, browse(1, 100))
history.RecordBrowse(scan, browse(1, 50, 1000))
history.RecordBrowse(scan, browse(1, 150))
local day = math.floor(now / DAY)
local bucket = db.markets.PvE.days[day]
local row = bucket.records["browse:1:0:0:0"]
check(row.low == 50 and row.high == 150 and row.last == 150 and row.samples == 3, "daily low/high/latest aggregate actual observed unit prices")
check(bucket.count == 1, "repeated scans/listings do not create extra daily records")
check(row.low ~= 50 * 1000, "browse availability never multiplies the minimum unit price")
history.RecordBrowse(scan, browse(1, 25, 1, 20, 7))
history.RecordBrowse(scan, browse(1, 30, 1, 20, -7))
check(bucket.count == 3 and bucket.records["browse:1:20:7:0"].last == 25
    and bucket.records["browse:1:20:-7:0"].last == 30, "level and signed suffix variants stay separate")
local old = assert(history.BeginScan("browse", now - 50))
history.RecordBrowse(old, browse(1, 40))
check(row.low == 40 and row.last == 150 and row.at == now, "older observations can lower the low but cannot replace the latest quote")
local replicated = assert(history.BeginScan("replicate", now))
history.RecordReplicate(replicated, { replicateInfo = { [17] = 1, [3] = 20, [10] = 90 } })
local broad = bucket.records["replicate:1"]
check(broad.last == 4.5 and broad.samples == 1, "stack prices normalize without rounding away fractional copper")
check(broad ~= row and row.last == 150, "broader replicate history is not merged into exact browse variants")
local count = bucket.count
history.RecordBrowse(scan, browse(2, 0))
history.RecordBrowse(scan, browse(2, -1))
history.RecordBrowse(scan, browse(2, "SECRET"))
history.RecordBrowse(scan, browse(2, 1, 0))
history.RecordBrowse(scan, browse(2, 1, 1, "SECRET"))
history.RecordReplicate(replicated, { replicateInfo = { [17] = 2, [3] = 0, [10] = 10 } })
history.RecordReplicate(replicated, { replicateInfo = { [17] = 2, [3] = 10, [10] = 0 } })
history.RecordReplicate(scan, { replicateInfo = { [17] = 2, [3] = 10, [10] = 100 } })
check(bucket.count == count and not db.items[2], "invalid, unavailable and bid-only observations do not become prices or fake zeroes")
history.RecordVendor("item:1:variant", "Variant", 12, now)
check(db.items[1].vendorPrice == 12 and db.items[1].vendorLink == "item:1:variant" and db.items[1].vendorSeenAt == now,
    "vendor value retains exact-link provenance and observation time")
history.RecordVendor("item:1:older", "Older", 99, now - 1)
check(db.items[1].vendorPrice == 12, "older vendor sample cannot replace a newer observation")
history.RecordVendor("item:3", "Unsellable", 0, now)
check(db.items[3].vendorPrice == 0, "verified zero vendor value remains distinct from missing data")
history.RecordVendor("item:4", "Missing", nil, now)
history.RecordVendor("item:4", "Restricted", "SECRET", now)
check(not db.items[4], "unknown and restricted vendor values never create fabricated item prices")
history.RecordVendor("item:1:newer", "Newer", 15, now + 1)
check(db.items[1].vendorPrice == 15 and db.items[1].vendorLink == "item:1:newer", "new vendor observation updates price and provenance together")
check(history.Summary():find("2 verified vendor prices", 1, true), "updating an existing item's vendor value does not inflate database counts")
history.SetMarket("Hardcore")
local hc = assert(history.BeginScan("browse", now))
history.RecordBrowse(hc, browse(1, 900))
check(db.markets.Hardcore.days[day].records["browse:1:0:0:0"].last == 900 and row.last == 150, "Auctionator markets remain isolated")

-- Simulate the Lua table round-trip performed by WoW SavedVariables.
local function serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local parts = { "{" }
    for key, entry in pairs(value) do parts[#parts + 1] = "[" .. serialize(key) .. "]=" .. serialize(entry) .. "," end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end
local savedText = serialize(db)
local reloaded = assert(loadstring("return " .. savedText))()
local freshAddon = {}
assert(loadfile("addons/ProfitMaster/History.lua"))("ProfitMaster", freshAddon)
history = freshAddon.History
check(history.Initialize(reloaded) == reloaded and serialize(db) == savedText, "reloading preserves data without overwriting the supplied saved table")
history.SetMarket("PvE")
check(reloaded.items[1].vendorPrice == 15 and reloaded.markets.PvE.days[day].records["browse:1:0:0:0"].samples == 4,
    "vendor cache and auction history survive a SavedVariables-style round-trip")

-- Advance through 35 observed UTC days; untouched markets also get pruned.
for offset = 1, 35 do
    now = (day + offset) * DAY + 100
    local nextScan = assert(history.BeginScan("browse", now))
    history.RecordBrowse(nextScan, browse(1, offset))
end
local days = 0
for storedDay in pairs(reloaded.markets.PvE.days) do
    check(storedDay >= day + 6, "expired date was removed")
    days = days + 1
end
check(days == 30 and reloaded.markets.PvE.days[day + 6] and not reloaded.markets.PvE.days[day + 5], "retains today plus 29 preceding UTC days")
check(next(reloaded.markets.Hardcore.days) == nil, "pruning covers markets the player has not revisited")
check(reloaded.items[1].vendorPrice == 15, "30-day auction pruning does not delete the item/vendor database")
check(not history.BeginScan("browse", now - 31 * DAY), "old snapshots cannot recreate expired history")

-- Complete replicate distributions add per-scan means without changing legacy fields.
local statsDB = { version = 1, items = {}, markets = {} }
history.Initialize(statsDB)
history.SetMarket("Stats")
local statsDay = math.floor(now / DAY)
local function native(id, quantity, buyout) return { [17] = id, [3] = quantity, [10] = buyout } end
local function close(scan, complete)
    local step, calls, done, saved = history.Finish(scan, complete), 0
    repeat
        done, saved = step()
        calls = calls + 1
        assert(calls < 10000, "trimmed mean finalization did not terminate")
    until done
    return saved, calls, step
end
local function approximately(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end
local exact = history.BeginScan("replicate", now)
for price = 1, 10 do history.RecordReplicate(exact, { replicateInfo = native(100, 1, price) }) end
local legacy = exact.bucket.records["replicate:100"]
check(legacy.low == 1 and legacy.high == 10 and legacy.last == 10 and legacy.samples == 10,
    "full-distribution capture preserves daily low/high/latest/listing counts")
local saved, _, exactStep = close(exact, true)
local mean = exact.bucket.trimmedMeans["replicate:100"]
check(exact.bucket.scanTimes[now] == true, "completed full scans retain their UTC source timestamps independently of daily means")
check(saved == 1 and mean.mean == 5.5 and mean.samples == 10 and mean.retained == 8,
    "ten equally weighted units trim exactly one at each end")
check(mean.at == now and mean.sum == 5.5 and mean.count == 1
    and exact.bucket.trimmedMethod == "unit-weighted-trimmed" and exact.bucket.trimmedTail == 0.1,
    "daily rollup preserves scan-mean sum/count and timestamp with source namespace and trim metadata")
check(legacy.low == 1 and legacy.high == 10 and legacy.last == 10 and legacy.samples == 10,
    "finalization does not rewrite legacy observation meanings")
check(history.Finish(exact, true) == exactStep and select(2, exactStep()) == 1 and exact.bucket.trimmedScans == 1,
    "duplicate finalization shares one idempotent callback and cannot save twice")
history.Abort(exact)
check(exact.bucket.trimmedScans == 1 and select(2, exactStep()) == 1, "abort after commit cannot remove or duplicate an existing mean")

local weighted = history.BeginScan("replicate", now + 1)
history.RecordReplicate(weighted, { replicateInfo = native(101, 100, 100) })
history.RecordReplicate(weighted, { replicateInfo = native(101, 1, 100) })
history.RecordReplicate(weighted, { replicateInfo = native(101, 1, 101) })
close(weighted, true)
mean = weighted.bucket.trimmedMeans["replicate:101"]
check(approximately(mean.mean, 1) and mean.samples == 102 and approximately(mean.retained, 81.6),
    "unit weighting trims ten-point-two units from each end instead of weighting three listings equally")
check(weighted.bucket.records["replicate:101"].samples == 3,
    "unit-weighted statistics do not change legacy listing-observation counts")

local small = history.BeginScan("replicate", now + 2)
for _, price in ipairs({ 1, 2, 100 }) do history.RecordReplicateDistribution(small, native(102, 1, price)) end
close(small, true)
mean = small.bucket.trimmedMeans["replicate:102"]
check(approximately(mean.mean, 727 / 24) and mean.samples == 3 and approximately(mean.retained, 2.4),
    "fewer than ten units use exact fractional boundary weights rather than rounding the trim to zero")
check(small.bucket.records["replicate:102"] == nil and statsDB.items[102] == nil,
    "raw numeric distribution capture does not invent legacy observations or item metadata")
local one = history.BeginScan("replicate", now + 3)
history.RecordReplicateDistribution(one, native(103, 1, 50))
close(one, true)
mean = one.bucket.trimmedMeans["replicate:103"]
check(mean.mean == 50 and approximately(mean.retained, 0.8), "one unit keeps its value while its middle-eighty-percent weight is fractional")
local hugeQuantity = history.BeginScan("replicate", now + 4)
history.RecordReplicateDistribution(hugeQuantity, native(104, 1000000000, 9500000000))
local hugeSaved, hugeCalls = close(hugeQuantity, true)
mean = hugeQuantity.bucket.trimmedMeans["replicate:104"]
check(hugeSaved == 1 and hugeCalls == 1 and mean.mean == 9.5 and mean.samples == 1000000000 and mean.retained == 800000000,
    "a billion units stay one histogram bin without rounding fractional per-unit copper")

local beforeCaptures = exact.bucket.trimmedScans
local bidOnly = history.BeginScan("replicate", now)
check(history.RecordReplicateDistribution(bidOnly, native(105, 1, 0)), "known bid-only rows are valid but excluded from buyout statistics")
check(close(bidOnly, true) == 0 and bidOnly.bucket.trimmedScans == beforeCaptures, "an empty buyout distribution does not create a fabricated zero mean")
local disabled = history.BeginScan("replicate", now, false)
history.RecordReplicate(disabled, { replicateInfo = native(106, 2, 30) })
check(close(disabled, true) == 0 and disabled.bucket.records["replicate:106"].last == 15,
    "legacy provider observations can explicitly disable duplicate histogram collection")
local onlyBrowse = history.BeginScan("browse", now)
history.RecordBrowse(onlyBrowse, browse(107, 1, 1000000))
check(close(onlyBrowse, true) == 0 and not onlyBrowse.bucket.records["browse:107:0:0:0"].mean,
    "browse minimum price and total stock never become an all-price distribution")

local badRows = {
    native(0, 1, 10), native(108.5, 1, 10), native(108, 0, 10), native(108, 1.5, 10),
    native(108, 1, -1), native(108, 1, 1.5), native(108, 1, math.huge), native(108, 1, "SECRET"),
    native("SECRET", 1, 10), native(108, "SECRET", 10), {}, "not native data",
}
for _, bad in ipairs(badRows) do
    local invalid = history.BeginScan("replicate", now)
    history.RecordReplicateDistribution(invalid, native(108, 1, 10))
    check(not history.RecordReplicateDistribution(invalid, bad), "malformed numeric replicate data explicitly invalidates distribution coverage")
    check(close(invalid, true) == 0 and invalid.bucket.trimmedScans == beforeCaptures,
        "a valid prefix cannot save an average after malformed/missing/restricted price rows")
end
local partial = history.BeginScan("replicate", now)
history.RecordReplicate(partial, { replicateInfo = native(109, 1, 10) })
check(close(partial, false) == 0 and partial.bucket.records["replicate:109"].last == 10,
    "partial coverage preserves observations but never saves a complete-market mean")
check(close(partial, true) == 0, "a rejected partial capture cannot later be recommitted as complete")

local many = history.BeginScan("replicate", now)
for id = 200, 1200 do history.RecordReplicateDistribution(many, native(id, 1, 100)) end
local manyStep = history.Finish(many, true)
check(manyStep() == false and many.bucket.trimmedScans == beforeCaptures,
    "finalization yields bounded group work without persisting a partial capture")
history.Abort(many)
history.Abort(many)
local done, canceledCount = manyStep()
check(done and canceledCount == 0 and many.bucket.trimmedScans == beforeCaptures,
    "repeated abort during finalization drops staged means without partially saving")
local beforeStart = history.BeginScan("replicate", now)
history.RecordReplicateDistribution(beforeStart, native(110, 1, 100))
history.Abort(beforeStart)
check(close(beforeStart, true) == 0, "abort before finalization is idempotently terminal")

-- Round-trip rollups; equal-scan averages stay distinct from unit weighting.
local statsText = serialize(statsDB)
local restoredStats = assert(loadstring("return " .. statsText))()
history.Initialize(restoredStats)
history.SetMarket("Stats")
local another = history.BeginScan("replicate", now + 10)
history.RecordReplicateDistribution(another, native(100, 1000, 20000))
close(another, true)
local combined = another.bucket.trimmedMeans["replicate:100"]
check(combined.count == 2 and combined.sum / combined.count == 12.75,
    "saved sum/count support an equal-scan average without reweighting by auction stock")
check(combined.mean == 20 and combined.samples == 1000 and combined.retained == 800 and combined.at == now + 10,
    "the latest scan's independent mean and sample fields survive a SavedVariables-style round-trip")

-- Copy-on-write finalization is atomic and safely rebases interleaved commits.
local seed = history.BeginScan("replicate", now + 20)
for id = 200, 1200 do history.RecordReplicateDistribution(seed, native(id, 1, 100)) end
close(seed, true)
local originalRollup = seed.bucket.trimmedMeans
local first = history.BeginScan("replicate", now + 40)
history.RecordReplicateDistribution(first, native(100, 1, 2))
local firstStep = history.Finish(first, true)
check(firstStep() == false and first.bucket.trimmedMeans == originalRollup,
    "copying a large daily rollup yields without changing the currently saved table")
local later = history.BeginScan("replicate", now + 50)
history.RecordReplicateDistribution(later, native(100, 3, 90))
close(later, true)
local afterLater = later.bucket.trimmedMeans["replicate:100"]
check(afterLater.count == 3 and originalRollup["replicate:100"].count == 2,
    "a commit swaps tables rather than mutating previously saved rows")
close(first, true)
combined = first.bucket.trimmedMeans["replicate:100"]
check(combined.count == 4 and approximately(combined.sum, 57.5) and approximately(combined.mean, 30) and combined.samples == 3
    and approximately(combined.retained, 2.4) and combined.at == now + 50,
    "an older interleaved commit rebases without losing means or regressing latest sample fields")
local keyCount = 0
for _ in pairs(first.bucket.trimmedMeans) do keyCount = keyCount + 1 end
for i = 1, 20 do
    local repeated = history.BeginScan("replicate", now + 50 + i)
    history.RecordReplicateDistribution(repeated, native(100, 1, 10))
    close(repeated, true)
end
local afterKeys = 0
for _ in pairs(first.bucket.trimmedMeans) do afterKeys = afterKeys + 1 end
check(afterKeys == keyCount and first.bucket.trimmedMeans["replicate:100"].count == 24,
    "repeated same-day scans grow sum/count while saved row count remains bounded by distinct source keys")
local canceledCopy = history.BeginScan("replicate", now)
history.RecordReplicateDistribution(canceledCopy, native(100, 1, 999))
local canceledStep = history.Finish(canceledCopy, true)
local beforeAbort = canceledCopy.bucket.trimmedMeans
check(canceledStep() == false, "large rollup preparation remains cancellable before its atomic swap")
history.Abort(canceledCopy)
check(select(2, canceledStep()) == 0 and canceledCopy.bucket.trimmedMeans == beforeAbort
    and beforeAbort["replicate:100"].count == 24, "canceling a staged rollup cannot partly add a scan mean")

history.SetMarket("RawOnly")
local rawOnly = history.BeginScan("replicate", now)
history.RecordReplicateDistribution(rawOnly, native(6000, 1, 12))
close(rawOnly, true)
check(rawOnly.bucket.count == 0 and statsDB.items[6000] == nil and restoredStats.items[6000] == nil
    and history.Summary():find("1/30 days", 1, true) and history.Summary():find("1 trimmed snapshots", 1, true),
    "complete raw-only financial captures count in the summary without inventing item metadata or legacy rows")
history.SetMarket("Stats")
local malformedBucket = history.BeginScan("replicate", now + DAY)
malformedBucket.bucket.trimmedMeans = "preserve unexpected optional data"
history.RecordReplicate(malformedBucket, { replicateInfo = native(111, 1, 12) })
check(close(malformedBucket, true) == 0 and malformedBucket.bucket.trimmedMeans == "preserve unexpected optional data"
    and malformedBucket.bucket.records["replicate:111"].last == 12,
    "malformed optional mean storage is preserved while legacy observations continue")
now = now + 30 * DAY
history.Prune(now)
check(restoredStats.markets.Stats.days[statsDay] == nil and restoredStats.markets.Stats.days[statsDay + 1],
    "the existing thirty-day pruning removes complete per-scan records with their owning day bucket")
local quickSaved = assert(history.Initialize(nil))
for id = 1, 350 do
    history.RememberOpportunity({ itemID = id, itemKey = browse(id, 50).itemKey, profit = 10 })
    now = now + 1
end
local keys = history.QuickKeys()
local count = 0
for _ in pairs(quickSaved.quickItems) do count = count + 1 end
check(count == 300 and #keys == 300 and keys[1].itemID == 350 and keys[300].itemID == 51,
    "watchlist storage is bounded and keeps the 300 most recent opportunities")
keys[1].itemID = 9999
check(history.QuickKeys()[1].itemID == 350, "returned watchlist keys cannot mutate saved data")
history.RememberOpportunity({ itemID = 1, itemKey = browse(1, 50, 1, "SECRET").itemKey, profit = 20 })
check(history.QuickKeys()[1].itemID == 350, "restricted key fields are skipped before key construction")
history.Initialize(quickSaved)
check(#history.QuickKeys() == 300, "learned opportunities survive SavedVariables initialization")
history.RecordVendor("item:2589", "Linen Cloth", 13, now, 7, 5, "Trade Goods", "Cloth")
check(quickSaved.items[2589].classID == 7 and quickSaved.items[2589].subclassID == 5
    and quickSaved.items[2589].subclassName == "Cloth", "category fields reuse verified vendor item metadata")
history.RecordVendor("item:2589", "Linen Cloth", 13, now, "SECRET", 5, "SECRET", "Cloth")
check(quickSaved.items[2589].classID == 7 and quickSaved.items[2589].className == "Trade Goods",
    "restricted category fields are skipped without discarding known metadata")
local future = { version = 99, items = {}, markets = {}, marker = "preserve" }
check(history.Initialize(future) == nil and future.marker == "preserve" and future.version == 99, "unknown database version is preserved and safely disabled")
history.RecordVendor("item:5", "No write", 50, now)
check(next(future.items) == nil and history.Summary():find("preserved", 1, true), "disabled schema never overwrites existing saved data")
print("Profit Master history: " .. checks .. " assertions passed (Lua 5.1).")
