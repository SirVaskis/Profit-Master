-- Offline expected-value/eligibility checks. No game APIs or actual disenchants.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local secret = {}
issecretvalue = function(value) return value == secret end
local metadata, prices, lookups, itemReads, detailedReads = {}, {}, 0, 0, 0
C_Item = {
    GetItemInfo = function(reference)
        itemReads = itemReads + 1
        local row = metadata[reference]
        if row then return row.name, reference, row.quality, row.level, 1, "", "", row.stack or 1,
            row.slot, 1, row.vendor, row.class, 0, 0, row.expansion end
    end,
    GetDetailedItemLevelInfo = function(reference)
        detailedReads = detailedReads + 1
        local row = metadata[reference]
        if row then return row.actualLevel or row.level, false, row.level end
    end,
}
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
    check(caller == "ProfitMaster", "material lookup identifies its caller")
    lookups = lookups + 1
    return prices[id]
end } } }
local addon = {}
assert(loadfile("addons/ProfitMaster/Disenchant.lua"))("ProfitMaster", addon)
local de = addon.Disenchant
check(de.Icon() == nil, "missing spell data does not use a generic Enchant icon")
C_Spell = { GetSpellTexture = function(id)
    check(id == 13262, "icon requests the actual Disenchant spell")
    return secret
end }
check(de.Icon() == nil, "restricted spell texture is omitted")
local spellReads = 0
C_Spell.GetSpellTexture = function(id) spellReads = spellReads + 1; return 880 end
check(de.Icon() == 880 and de.Icon() == 880 and spellReads == 1, "actual Disenchant texture is reused without repeated spell lookups")
local function item(reference, quality, level, class, vendor)
    metadata[reference] = { name = "Equipment", quality = quality, level = level,
        slot = class == 2 and "INVTYPE_WEAPON" or "INVTYPE_CHEST", vendor = vendor or 1, class = class, expansion = 0 }
    return metadata[reference]
end

local saved = de.Initialize()
check(saved.version == 1 and not saved.enabled and not de.Enabled(), "disenchant mode defaults off")
check(saved.safe == true and de.Safe(), "safe valuation defaults on without enabling disenchant profits")
de.SetSafe(false) -- Existing expected-value regression cases explicitly select average mode.
item("item:10001", 2, 10, 4, 150)
prices[10940], prices[10938] = 100, 200
check(not de.Estimate("item:10001") and itemReads == 0 and lookups == 0, "disabled mode does no item or market work")
de.SetEnabled(true)
check(saved.enabled and de.Enabled(), "explicit enable persists to the separate settings table")
local net, gross, vendor = de.Estimate("item:10001")
check(net == 153 and gross == 180 and vendor == 150, "expected dust/essence quantities apply a conservative fifteen-percent fee allowance")
check(de.ShouldMark("item:10001"), "bag marker includes exactly three copper expected gain over vendor")
metadata["item:10001"].vendor = 151
check(not de.ShouldMark("item:10001"), "bag marker excludes two copper gain using fresh vendor data")
metadata["item:10001"].vendor = 153
check(not de.ShouldMark("item:10001"), "equal expected proceeds and vendor value do not mark")

local beforePrices = lookups
de.Estimate("item:10001")
check(lookups == beforePrices, "repeated values share the material-price cache")
prices[10940] = 200
check(de.Estimate("item:10001") == 153, "saved market-price cache stays stable until explicit refresh")
de.ResetCache()
check(de.Estimate("item:10001") == 255, "explicit refresh picks up changed material prices")

prices[10940], prices[10939], prices[10978], prices[10998] = 100, 100, 100, 100
de.ResetCache()
item("item:10002", 2, 20, 2)
net, gross = de.Estimate("item:10002")
check(net == 142 and gross == 167, "weapon value uses weapon expected quantities rather than armor odds")
item("item:10003", 2, 25, 4)
net, gross = de.Estimate("item:10003")
check(net == 346 and gross == 407, "armor ilvl21-25 includes all three outcomes and floors copper")
item("item:10004", 2, 25, 2)
check(not de.Estimate("item:10004"), "known changed Forever weapon ilvl21-30 yields are not guessed")
item("item:10005", 3, 20, 4)
check(not de.Estimate("item:10005"), "new Forever rare5-20 client buckets with unknown server outputs are skipped")
item("item:10006", 3, 21, 4)
prices[10978] = 500
de.ResetCache()
check(de.Estimate("item:10006") == 425, "supported rare estimate values its shard after fees")
item("item:10007", 3, 56, 2)
prices[14344], prices[20725] = 1000, 10000
de.ResetCache()
net, gross = de.Estimate("item:10007")
check(net == 888 and gross == 1045, "high rare estimate includes its rare crystal outcome")
prices[20725] = nil
de.ResetCache()
check(not de.Estimate("item:10007"), "a missing low-probability outcome is unknown, not a zero-valued material")
prices[20725] = 10000
de.ResetCache()
item("item:10008", 4, 65, 4)
check(de.Estimate("item:10008") == 12750, "epic estimate uses its expected one-and-a-half crystals")
metadata["item:10008"].actualLevel = 999
check(de.Estimate("item:10008") == 12750, "yield bracket uses sparse base item level rather than display scaling")

for _, reference in ipairs({ "item:11287", "item:11288", "item:11289", "item:11290", "item:200000", "item:249144" }) do
    item(reference, 2, 20, 2)
    local before = itemReads
    check(not de.Estimate(reference) and itemReads == before, "crafted wands and unverified new Forever IDs are excluded before valuation")
end
for _, slot in ipairs({ "", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_BAG", "INVTYPE_QUIVER", "INVTYPE_AMMO", "INVTYPE_NON_EQUIP" }) do
    item("item:10009", 2, 10, 4).slot = slot
    check(not de.Estimate("item:10009"), "quality alone cannot classify non-disenchantable equipment slots")
end
item("item:10009", 2, 10, 7)
check(not de.Estimate("item:10009"), "non-equipment item classes cannot yield a disenchant estimate")
item("item:10009", 1, 10, 4)
check(not de.Estimate("item:10009"), "common quality items are excluded")
item("item:10009", 2, 66, 4)
check(not de.Estimate("item:10009"), "out-of-model levels do not borrow an expansion yield table")
item("item:10009", 2, 10, 4).expansion = 1
check(not de.Estimate("item:10009"), "later-expansion items cannot borrow the original-era model")

for _, field in ipairs({ "name", "quality", "level", "slot", "vendor", "class", "expansion" }) do
    item("item:10010", 2, 10, 4)[field] = secret
    check(not de.Estimate("item:10010"), "restricted metadata is skipped before comparisons or arithmetic")
end
for _, value in ipairs({ secret, 0, -1, math.huge, -math.huge, "123" }) do
    prices[10940] = value
    de.ResetCache()
    check(not de.Estimate("item:10001"), "restricted or nonpositive/nonfinite market values are unavailable")
end
prices[10940] = 0 / 0
de.ResetCache()
check(not de.Estimate("item:10001"), "NaN market values cannot create a profit estimate")
check(not de.Estimate(secret) and not de.Estimate("battlepet:1") and not de.Estimate(-1)
    and not de.Estimate("item:0"), "restricted and invalid references are skipped")

prices[10940], prices[10938] = 100, 200
de.ResetCache()
local cache, beforeItems = {}, itemReads
check(de.Estimate("item:10001", cache) == 153 and de.Estimate("item:10001", cache) == 153 and itemReads == beforeItems + 1,
    "caller cache reuses per-reference metadata without colliding with vendor entries")
cache["item:10001"] = { sellPrice = 153 }
check(cache["item:10001"].sellPrice == 153, "disenchant cache does not replace exact vendor cache records")
prices[10940] = 200
de.ResetCache()
check(de.Estimate("item:10001", cache) == 255, "generation refresh invalidates estimates inside a caller-owned cache")
check(not de.Estimate("item:10011", cache), "missing item metadata stays unavailable")
item("item:10011", 2, 10, 4)
check(de.Estimate("item:10011", cache) == 255, "late metadata can qualify without discarding the caller's scan cache")
prices[10940] = nil
de.ResetCache()
item("item:10012:variantA", 2, 10, 4, 5)
check(not de.Estimate("item:10012:variantA", cache), "missing material price still captures complete public item metadata")
metadata["item:10012:variantA"] = nil -- The engine evicts it while the scan continues.
prices[10940] = 300
de.ResetCache()
net, gross, vendor = de.Estimate("item:10012:variantA", cache)
check(net == 357 and gross == 420 and vendor == 5,
    "final material-price revaluation survives native metadata eviction")
check(not de.Estimate("item:10012:variantB", cache), "retained metadata cannot stand in for another exact item variant")
check(not de.Estimate("item:10012:variantA"), "bag/live calls without a scan cache do not borrow old metadata")
item("item:10013", 2, 10, 4).quality = secret
check(not de.Estimate("item:10013", cache) and not cache.profitMasterDisenchantMetadata["item:10013"],
    "restricted metadata is never retained for final revaluation")
item("item:10014", 1, 10, 4)
local beforeDetails = detailedReads
check(not de.Estimate("item:10014", cache) and detailedReads == beforeDetails,
    "known common equipment skips the native detailed-level lookup")
item("item:10015", 2, 10, 7)
check(not de.Estimate("item:10015", cache) and detailedReads == beforeDetails,
    "known non-equipment classes skip detailed-level lookup")
item("item:10016", 2, 10, 4).slot = "INVTYPE_TABARD"
check(not de.Estimate("item:10016", cache) and detailedReads == beforeDetails,
    "known excluded equipment slots skip detailed-level lookup")
item("item:10017", 2, 10, 4).expansion = 1
check(not de.Estimate("item:10017", cache) and detailedReads == beforeDetails,
    "known unsupported expansion skips detailed-level lookup")
prices[10940] = nil
de.ResetCache()
item("item:10018", 2, 10, 4)
check(not de.Estimate("item:10018", cache) and cache.profitMasterDisenchant.values["item:10018"] == false,
    "known metadata with unavailable materials caches unknown valuation within its price generation")
prices[10940] = 300
check(not de.Estimate("item:10018", cache), "late materials do not change a generation's cached unknown result")
de.ResetCache()
check(de.Estimate("item:10018", cache) == 357,
    "material refresh invalidates an unknown result while retaining the item's public metadata")

-- Bag strategy compares complete supported estimates in both directions. Unknown
-- disenchant data must never turn into a recommendation to sell an item instead.
prices[10940], prices[10938] = 100, 200
de.ResetCache()
item("item:10020", 2, 10, 4, 150)
local strategy, pending = de.Recommendation("item:10020")
check(strategy == "disenchant" and not pending and de.ShouldMark("item:10020"),
    "a complete estimate exactly three copper above vendor recommends disenchant")
metadata["item:10020"].vendor = 156
strategy, pending = de.Recommendation("item:10020")
check(strategy == "vendor" and not pending and not de.ShouldMark("item:10020"),
    "a complete vendor value exactly three copper above expected net recommends selling")
metadata["item:10020"].stack = 200
check(de.Recommendation("item:10020") == "vendor", "strategy compares per-item proceeds regardless of maximum stack count")
metadata["item:10020"].stack = 1
for _, amount in ipairs({ 151, 152, 153, 154, 155 }) do
    metadata["item:10020"].vendor = amount
    check(de.Recommendation("item:10020") == nil and not de.ShouldMark("item:10020"),
        "ties and differences below three copper have no strategy in either direction")
end
metadata["item:10020"].vendor = 0
check(de.Recommendation("item:10020") == "disenchant", "a known zero vendor value cannot create a sell recommendation")
item("item:10021", 3, 21, 4, 3)
prices[10978] = 1
de.ResetCache()
net, gross, vendor = de.Estimate("item:10021")
check(net == 0 and gross == 1 and vendor == 3 and de.Recommendation("item:10021") == "vendor",
    "known zero rounded net is a valid supported estimate rather than missing material data")
metadata["item:10021"].vendor = 0
check(de.Recommendation("item:10021") == nil, "zero vendor and zero expected net are an unmarked tie")

prices[10940] = nil
de.ResetCache()
metadata["item:10020"].vendor = 10000
strategy, pending = de.Recommendation("item:10020")
check(strategy == nil and not pending, "missing material prices cannot recommend selling even a valuable supported item")
prices[10940] = secret
de.ResetCache()
check(de.Recommendation("item:10020") == nil, "restricted material prices cannot infer a sell recommendation")
prices[10940] = 100
de.ResetCache()
item("item:10022", 3, 20, 4, 10000)
check(de.Recommendation("item:10022") == nil, "unknown Forever rare yields cannot infer a sell recommendation")
item("item:10023", 2, 66, 4, 10000)
check(de.Recommendation("item:10023") == nil, "out-of-range yields cannot infer a sell recommendation")
item("item:200001", 2, 10, 4, 10000)
check(de.Recommendation("item:200001") == nil, "unverified new Forever IDs cannot infer a sell recommendation")
item("item:10024", 1, 10, 4, 10000)
check(de.Recommendation("item:10024") == nil, "ordinary common items are not automatically marked for sale")
item("item:10025", 2, 10, 7, 10000)
check(de.Recommendation("item:10025") == nil, "non-equipment items are not marked for sale")
check(de.Recommendation("item:11287") == nil, "non-disenchantable crafted wands cannot infer a sell recommendation")
item("item:10026", 2, 10, 4, 10000).vendor = secret
check(de.Recommendation("item:10026") == nil, "restricted vendor metadata cannot be used in a strategy comparison")
strategy, pending = de.Recommendation("item:10027")
local marked, legacyPending = de.ShouldMark("item:10027")
check(strategy == nil and pending == true and not marked and legacyPending == true,
    "missing metadata preserves pending readiness in both recommendation and legacy marker APIs")
item("item:10027", 2, 10, 4, 156)
strategy, pending = de.Recommendation("item:10027")
check(strategy == "vendor" and not pending, "late metadata can produce a sell icon without a cache reset or reload")
local beforeDisabledReads = itemReads
de.SetEnabled(false)
strategy, pending = de.Recommendation("item:10027")
check(strategy == nil and not pending and itemReads == beforeDisabledReads,
    "disabled disenchant mode cannot infer vendor recommendations or perform item lookups")
de.SetEnabled(true)

local preserved = { version = 1, enabled = true }
check(de.Initialize(preserved) == preserved and de.Enabled(), "saved opt-in preference survives initialization")
check(preserved.safe == true and de.Safe(), "legacy settings migrate to safe valuation while preserving opt-in")
local average = { version = 1, enabled = true, safe = false }
check(de.Initialize(average) == average and not de.Safe(), "explicit average preference survives initialization")
check(not de.Initialize({ version = 1, enabled = true, safe = "false" }) and not de.Enabled(),
    "malformed safe setting fails closed")
local malformed = { version = 99, enabled = true }
check(not de.Initialize(malformed) and malformed.version == 99 and not de.Enabled(), "unsupported saved settings are preserved and fail closed")
check(not de.Initialize({ version = 1, enabled = "true" }), "malformed saved preference cannot enable valuation")

de.Initialize({ version = 1, enabled = true, safe = true })
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", addon)
local safeCache = {}
item("item:10100", 2, 10, 4, 10)
prices[10940], prices[10938] = 100, 10000
de.ResetCache()
net, gross = de.Estimate("item:10100", safeCache)
check(net == 85 and gross == 100, "expensive essence cannot raise the minimum single-dust outcome")
check(not addon.Deal("item:10100", 1, 120), "average-profitable purchase with a losing dust outcome is hidden in safe mode")
local deal = addon.Deal("item:10100", 1, 82)
check(deal and deal.disenchant and deal.profit == 3 and deal.deNet == 85,
    "safe deal includes exactly the configured profit after fees and purchase cost")
check(not addon.Deal("item:10100", 1, 85), "break-even safe estimate never shows profit")
check(not addon.Deal("item:10100", 1, 83), "safe deal still respects minimum profit")
deal = addon.Deal("item:10100", 4, 328)
check(deal and deal.deNet == 340 and deal.profit == 12, "stack valuation scales minimum proceeds and subtracts whole-stack cost")
de.SetSafe(false)
check(de.Estimate("item:10100", safeCache) == 2652 and addon.Deal("item:10100", 1, 120),
    "average mode restores expected valuation and invalidates the caller's cached minimum")
de.SetSafe(true)
check(de.Estimate("item:10100", safeCache) == 85,
    "switching back to safe invalidates cached averages immediately")
metadata["item:10100"].vendor = 100
check(de.Recommendation("item:10100") == "vendor", "bag advice also uses minimum instead of high average")
prices[10938] = 20
de.ResetCache()
check(de.Estimate("item:10100") == 17, "essence can be the cheapest outcome instead of dust")
prices[10938] = nil
de.ResetCache()
check(not de.Estimate("item:10100"), "unknown outcome prices cannot produce a safe valuation")

-- Independent baseline outcome fixtures: minimum dust and essence counts vary
-- across brackets; a rare shard can itself be the cheapest outcome.
local minima = {
    {16,10940,10939,10978,2,1}, {21,10940,10998,10978,4,1},
    {26,11083,11082,11084,1,1}, {31,11083,11134,11138,2,1},
    {36,11137,11135,11139,1,1}, {41,11137,11174,11177,2,1},
    {46,11176,11175,11178,1,1}, {51,11176,16202,14343,2,1},
    {56,16204,16203,14344,1,1}, {61,16204,16203,14344,2,2},
}
for _, outcome in ipairs(minima) do
    for _, class in ipairs({ 2, 4 }) do
        if class == 4 or outcome[1] < 21 or outcome[1] > 30 then
            item("item:10101", 2, outcome[1], class, 1)
            prices[outcome[2]], prices[outcome[3]], prices[outcome[4]] = 10, 1000, 1000
            de.ResetCache()
            check(de.Estimate("item:10101") == math.floor(10 * outcome[5] * .85),
                "safe armor/weapon dust quantity at bracket " .. outcome[1])
            prices[outcome[2]], prices[outcome[3]] = 1000, 10
            de.ResetCache()
            check(de.Estimate("item:10101") == math.floor(10 * outcome[6] * .85),
                "safe armor/weapon essence quantity at bracket " .. outcome[1])
            prices[outcome[3]], prices[outcome[4]] = 1000, 1
            de.ResetCache()
            check(de.Estimate("item:10101") == 0, "rare single-shard outcome cannot be ignored in safe mode")
        end
    end
end
item("item:10102", 3, 56, 4)
prices[14344], prices[20725] = 1000, 10
de.ResetCache()
check(de.Estimate("item:10102") == 8, "even the half-percent crystal outcome limits a rare's safe value")
prices[14344], prices[20725] = 10, 1000
de.ResetCache()
check(de.Estimate("item:10102") == 8, "high-value rare crystal does not inflate the normal shard minimum")
for _, level in ipairs({ 40, 46, 51, 56, 61, 65 }) do
    item("item:10103", 4, level, 2)
    prices[11177], prices[11178], prices[14343], prices[20725] = 100, 100, 100, 100
    de.ResetCache()
    check(de.Estimate("item:10103") == (level <= 55 and 170 or 85),
        "epic safe value uses minimum shard/crystal count at level " .. level)
end
item("item:10104", 2, 25, 2)
check(not de.Estimate("item:10104"), "safe mode preserves the changed Forever weapon exclusion")
item("item:200000", 2, 10, 4)
check(not de.Estimate("item:200000"), "safe mode never invents yields for new Forever gear")
de.Initialize()
de.SetEnabled(false)
check(not de.ShouldMark("item:10001"), "disabling mode hides all recommendation markers")
print("Profit Master disenchant: " .. checks .. " offline assertions passed (Lua 5.1).")
