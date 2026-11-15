-- Pure price-filter/settings checks. No game events, purchases or file writes.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local secret = setmetatable({}, { __tostring = function() error("restricted preference was formatted") end })
issecretvalue = function(value) return value == secret end
C_Item = { GetItemInfo = function(reference)
    local id = type(reference) == "number" and reference or tonumber(reference:match("item:(%d+)"))
    if id == 1 or id == 2 then return "Equipment " .. id, "item:" .. id, 2, 10, 1, "", "", 1, "INVTYPE_CHEST", 1, 100 end
end }
C_AuctionHouse = { GetItemKeyInfo = function(key) return { isCommodity = key.itemID == 2, isPet = false } end }
local deEnabled, deNet = false, 200
local addon = { Disenchant = {
    Enabled = function() return deEnabled end,
    Estimate = function(link) if link == "item:1" then return deNet, 240 end end,
} }
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", addon)
local function key(id) return { itemID = id, itemLevel = 10, itemSuffix = 0, battlePetSpeciesID = 0 } end
local function replicated(cost)
    return { itemLink = "item:1", replicateInfo = { [17] = 1, [3] = 10, [10] = cost * 10 } }
end
local sources = {
    { "vendor", function(cost) return addon.Deal("item:1", 1, cost, {}) end },
    { "browse", function(cost) return addon.BrowseDeal({ itemKey = key(1), totalQuantity = 10, minPrice = cost }, {}) end },
    { "replicate", function(cost) return addon.ReplicateDeal(replicated(cost), {}) end },
    { "commodity", function(cost) return addon.CommodityDeal({ itemID = 2, quantity = 100, unitPrice = cost,
        numOwnerItems = 0, containsOwnerItem = false, containsAccountItem = false }, {}) end },
    { "live", function(cost) return addon.LiveDeal({ auctionID = 42, itemLink = "item:1", quantity = 139,
        buyoutAmount = cost, containsOwnerItem = false, containsAccountItem = false }, {}) end },
}
local function allSources(cost, expected)
    for _, source in ipairs(sources) do
        local deal = source[2](cost)
        check((deal ~= nil) == expected, source[1] .. " uses the configured minimum consistently")
        if deal then check(deal.cost == cost and deal.profit == 100 - cost,
            source[1] .. " keeps actual per-item profit instead of multiplying grouped stock") end
    end
end

check(addon.GetMinimumProfit() == 3, "default minimum is three copper before saved data initializes")
check(not addon.SetMinimumProfit(10), "an unbound preference cannot write a SavedVariables target")
local db = { version = 1, items = { marker = {} }, markets = { Realm = { days = {} } } }
local originalItems, originalMarkets = db.items, db.markets
check(addon.InitializeProfitSettings(db) and db.minimumProfit == 3 and addon.GetMinimumProfit() == 3,
    "a missing preference initializes three copper inside the existing valid database")
check(db.version == 1 and db.items == originalItems and db.markets == originalMarkets,
    "preference initialization preserves the existing schema and item/market history")
allSources(97, true)
allSources(98, false)
check(addon.SetMinimumProfit(10) and addon.GetMinimumProfit() == 10 and db.minimumProfit == 10,
    "whole copper edits update the active cutoff and existing saved table")
allSources(90, true)
allSources(91, false)
check(addon.SetMinimumProfit(10), "setting an unchanged valid amount still reports successful validation")
check(not addon.ReplicateDeal(replicated(90.1), {}),
    "a normalized fractional-copper profit below ten copper is not rounded up to the threshold")
check(addon.SetMinimumProfit(0), "zero is an allowed minimum")
allSources(99, true)
allSources(100, false)
allSources(101, false)
local fractional = addon.ReplicateDeal({ itemLink = "item:1", replicateInfo = { [17] = 1, [3] = 10, [10] = 995 } }, {})
check(fractional and fractional.cost == 99.5 and fractional.profit == 0.5,
    "minimum zero retains any strictly positive fractional per-unit profit")
addon.SetMinimumProfit(1)
check(not addon.ReplicateDeal({ itemLink = "item:1", replicateInfo = { [17] = 1, [3] = 10, [10] = 995 } }, {}),
    "a one-copper minimum excludes half-copper normalized profits without changing their actual prices")

deEnabled = true
addon.SetMinimumProfit(10)
for _, source in ipairs({ sources[1], sources[2], sources[3], sources[5] }) do
    local deal = source[2](190)
    check(deal and deal.disenchant and deal.deNet == 200 and deal.profit == 10,
        source[1] .. " applies the same inclusive minimum to expected disenchant profit")
    check(not source[2](191), source[1] .. " excludes expected disenchant profits below the configured minimum")
end
deNet = 102
local vendorChoice = addon.Deal("item:1", 1, 90, {})
check(vendorChoice and not vendorChoice.disenchant and vendorChoice.profit == 10,
    "the configurable offer minimum does not alter the three-copper DE-versus-vendor strategy advantage")
deNet = 103
local deChoice = addon.Deal("item:1", 1, 90, {})
check(deChoice and deChoice.disenchant and deChoice.profit == 13,
    "exactly three copper expected DE advantage still selects that strategy independently of the offer cutoff")
deEnabled = false

local invalid = { -1, 0.5, 1000000000, math.huge, -math.huge, 0 / 0, "10", false, secret }
for _, value in ipairs(invalid) do
    check(not addon.SetMinimumProfit(value) and addon.GetMinimumProfit() == 10 and db.minimumProfit == 10,
        "negative, fractional, oversized, nonfinite, nonnumeric and restricted edits leave preferences unchanged")
end
check(addon.SetMinimumProfit(999999999) and addon.GetMinimumProfit() == 999999999,
    "the largest supported whole-copper preference is accepted exactly")
check(not addon.Deal("item:1", 1, 1, {}), "large configured cutoffs are used by valuation rather than truncated")
for _, value in ipairs(invalid) do
    local corrupted = { version = 1, items = {}, markets = {}, minimumProfit = value }
    check(addon.InitializeProfitSettings(corrupted) and addon.GetMinimumProfit() == 3,
        "a malformed existing preference falls back to three copper without disabling valid history")
    local unchanged = value ~= value and corrupted.minimumProfit ~= corrupted.minimumProfit or corrupted.minimumProfit == value
    check(unchanged and addon.SetMinimumProfit(9) and corrupted.minimumProfit == 9,
        "corrupt saved values stay untouched until an explicit valid user edit replaces them")
end
for _, unsupported in ipairs({
    { version = 99, items = {}, markets = {}, minimumProfit = 6 },
    { version = 1, items = "bad", markets = {}, minimumProfit = 6 },
    { version = 1, items = {}, markets = false, minimumProfit = 6 },
    { version = secret, items = {}, markets = {}, minimumProfit = 6 },
}) do
    check(not addon.InitializeProfitSettings(unsupported) and addon.GetMinimumProfit() == 3
        and not addon.SetMinimumProfit(8) and unsupported.minimumProfit == 6,
        "unsupported or restricted database schemas are preserved and cannot become persistence targets")
end
check(not addon.InitializeProfitSettings(nil) and addon.GetMinimumProfit() == 3,
    "unavailable history leaves the safe default and no persistence target")

local persisted = { version = 1, items = {}, markets = {}, minimumProfit = 42 }
check(addon.InitializeProfitSettings(persisted) and addon.GetMinimumProfit() == 42, "valid saved preferences are restored on initialization")
local function serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local parts = { "{" }
    for k, v in pairs(value) do parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(v) .. "," end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end
local restored = assert(loadstring("return " .. serialize(persisted)))()
local fresh = {}
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", fresh)
check(fresh.InitializeProfitSettings(restored) and fresh.GetMinimumProfit() == 42,
    "the existing database preference survives a SavedVariables-style round trip")
check(fresh.SetMinimumProfit(17) and restored.minimumProfit == 17 and persisted.minimumProfit == 42,
    "a reloaded module updates only its own currently bound database table")
restored.version = 99
check(not fresh.SetMinimumProfit(18) and restored.minimumProfit == 17,
    "a target that stops matching the supported schema cannot be overwritten by a later edit")
print("Profit Master minimum profit: " .. checks .. " offline assertions passed (Lua 5.1).")
