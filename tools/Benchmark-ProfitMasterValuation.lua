-- Synthetic Lua/API-count comparison, not a game/network/FPS measurement.
-- Default baseline is a read-only source snapshot captured before optimization.
local baseline = os.getenv("PROFITMASTER_VALUATION_BASELINE_DIR") or "scratch/performance-0.1.19"
if jit then jit.off() end
local rows, unique, trials = 200000, 1000, 7
local links, costs, metadata = {}, {}, {}
for i = 1, unique do
    local id = 10000 + i
    local category = i % 4
    links[i], costs[i] = "item:" .. id, 50 + i % 150
    metadata[links[i]] = {
        quality = category == 0 and 1 or category == 3 and 3 or 2,
        class = category == 0 and 7 or category == 2 and 2 or 4,
        level = category == 3 and 56 or category == 2 and 50 or 35,
        slot = category == 0 and "" or category == 2 and "INVTYPE_WEAPON" or "INVTYPE_CHEST",
    }
end

local function Run(directory, mode)
    local reads, levels, market, evicted, repriced = 0, 0, 0, false, false
    C_Item = {
        GetItemInfo = function(reference)
            reads = reads + 1
            local item = not evicted and metadata[reference]
            if item then return reference, reference, item.quality, item.level, 1, "", "", 1,
                item.slot, 1, 100, item.class, 0, 0, 0 end
        end,
        GetDetailedItemLevelInfo = function(reference)
            levels = levels + 1
            local item = not evicted and metadata[reference]
            if item then return item.level, false, item.level end
        end,
    }
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller)
        assert(caller == "ProfitMaster")
        market = market + 1
        if mode == "unknown" then return nil end
        return repriced and 150 or 100
    end } } }
    local addon = { History = { RecordVendor = function() end } }
    assert(loadfile(directory .. "/Disenchant.lua"))("ProfitMaster", addon)
    assert(loadfile(directory .. "/Deals.lua"))("ProfitMaster", addon)
    addon.Disenchant.Initialize({ version = 1, enabled = mode ~= "off" })
    local cache, count, deCount, profit = {}, 0, 0, 0
    collectgarbage("collect")
    local started = os.clock()
    for i = 1, rows do
        if mode == "eviction_refresh" and i == unique + 1 then
            evicted, repriced = true, true
            addon.Disenchant.ResetCache()
        end
        local key = (i - 1) % unique + 1
        local deal = addon.Deal(links[key], 1, costs[key], cache)
        if deal then
            count, profit = count + 1, profit + deal.profit
            if deal.disenchant then deCount = deCount + 1 end
        end
    end
    return { seconds = os.clock() - started, reads = reads, levels = levels, market = market,
        count = count, deCount = deCount, profit = profit }
end

local function Median(values)
    table.sort(values)
    return values[math.ceil(#values / 2)]
end
for _, mode in ipairs({ "off", "known", "unknown", "eviction_refresh" }) do
    local beforeTimes, afterTimes, before, after = {}, {}
    for trial = 1, trials do
        if trial % 2 == 1 then before, after = Run(baseline, mode), Run("addons/ProfitMaster", mode)
        else after, before = Run("addons/ProfitMaster", mode), Run(baseline, mode) end
        assert(before.count == after.count and before.deCount == after.deCount and before.profit == after.profit,
            "Profit outputs changed for " .. mode)
        beforeTimes[trial], afterTimes[trial] = before.seconds, after.seconds
    end
    print(string.format("%s: median %.4fs -> %.4fs; GetItemInfo %d -> %d; detailed levels %d -> %d; material lookups %d -> %d; identical %d deals/%d DE/%d copper profit",
        mode, Median(beforeTimes), Median(afterTimes), before.reads, after.reads, before.levels, after.levels,
        before.market, after.market, after.count, after.deCount, after.profit))
end
print(string.format("%d rows, %d exact links, %d alternating trials; Lua 5.1-compatible runtime with JIT disabled.", rows, unique, trials))
print("Eviction case retains exact-reference metadata before eviction, then reprices materials after ResetCache. Native API costs and game timing are not simulated.")
