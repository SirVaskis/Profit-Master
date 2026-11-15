-- Compare real handlers with synthetic native results; never controls WoW.
-- Optional PROFITMASTER_CORE_SOURCE selects a saved pre-change core file.
-- Optional PROFITMASTER_COMPARE_PATH points to the supplied ProfitTop folder.
local input = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = input:read("*a")
input:close()
local baseline = os.getenv("PROFITMASTER_CORE_SOURCE")
if baseline then
    local count
    source, count = source:gsub('assert%(loadfile%("addons/ProfitMaster/ProfitMaster%.lua"%)%)', function()
        return "assert(loadfile(" .. string.format("%q", baseline) .. "))"
    end)
    assert(count == 1, "expected one production core entry point")
end
local cases = [=[
local function BenchmarkBooks()
    local originalRead, originalTimer, originalClock = C_AuctionHouse.GetItemSearchResultInfo, C_Timer.NewTimer, GetTimePreciseSec
    local readUS = tonumber(os.getenv("PROFITMASTER_READ_US")) or 20
    local fakeClock, maxReads, maxCPU, slices = now, 0, 0, 0
    local function Slice(callback)
        local reads, started = resultReads, os.clock()
        callback()
        if resultReads > reads then slices = slices + 1 end
        maxReads = math.max(maxReads, resultReads - reads)
        maxCPU = math.max(maxCPU, os.clock() - started)
    end
    local function reset(size)
        event("AUCTION_HOUSE_CLOSED")
        runImmediate()
        now = now + 120
        fakeClock = now
        commodity, full, throttle, keyInfoAvailable, money = false, true, true, true, 100000
        addon.Listings.SetEnabled(false)
        addon.Listings.SetOneClick(false)
        addon.Disenchant.SetEnabled(false)
        assert(addon.SetMinimumProfit(3))
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
        values["item:58501"] = 100
        listener:ReceiveEvent("complete", { scanned(58501, "item:58501", 1, 50) })
        runImmediate()
        results = {}
        for i = 1, size do
            local row = listing(100000 + i, "item:58501", i % 4 + 1, 10 + (i * 37) % 80)
            if i % 17 == 0 then row.containsOwnerItem = true end
            if i % 23 == 0 then row = results[i - 1] end
            results[i] = row
        end
    end
    local signatures = {}
    for _, size in ipairs({ 200, 2000, 20000 }) do
        reset(size)
        GetTimePreciseSec = function() return fakeClock end
        C_AuctionHouse.GetItemSearchResultInfo = function(key, index)
            fakeClock = fakeClock + readUS / 1000000
            return originalRead(key, index)
        end
        C_Timer.NewTimer = function(delay, callback)
            return originalTimer(delay, function() Slice(callback) end)
        end
        maxReads, maxCPU, slices = 0, 0, 0
        click(window.rows[1].action)
        local readsBefore, cpuBefore = resultReads, os.clock()
        Slice(function() event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58501)) end)
        runImmediate()
        local cpuMS = (os.clock() - cpuBefore) * 1000
        check(popup.shown and popup.data.cost == 10, "large book still offers the best verified price")
        signatures[size] = { cost = popup.data.cost, profit = popup.data.profit, available = popup.data.available }
        print(string.format("BOOK mode=%s rows=%d reads=%d max_slice_reads=%d modeled_slice_ms=%.3f slices=%d yield_wait_60fps_ms=%.3f cpu_ms=%.3f max_slice_cpu_ms=%.3f cost=%d profit=%d available=%d",
            os.getenv("PROFITMASTER_CORE_SOURCE") and "0.2.0" or "current", size, resultReads - readsBefore,
            maxReads, maxReads * readUS / 1000, slices, (slices - 1) * 1000 / 60, cpuMS, maxCPU * 1000,
            popup.data.cost, popup.data.profit, popup.data.available))
        GetTimePreciseSec, C_AuctionHouse.GetItemSearchResultInfo, C_Timer.NewTimer = originalClock, originalRead, originalTimer
        cancelPopup()
    end
    local comparePath = os.getenv("PROFITMASTER_COMPARE_PATH")
    if comparePath then
        local function Plain(value) if not (issecretvalue and issecretvalue(value)) then return value end end
        local pt = { On = function() end, now = GetTime, Buy = { bought = {} }, Plain = Plain,
            PlainNumber = function(value) if Plain(value) and type(value) == "number" and value > 0 and value < math.huge then return value end end,
            VariantKey = function(key) return table.concat({ key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0 }, ":") end,
            AuctionUnits = function() return 1 end }
        assert(loadfile(comparePath .. "/Deals.lua"))("ProfitTop", { PT = pt })
        for _, size in ipairs({ 200, 2000, 20000 }) do
            reset(size)
            local readsBefore, cpuBefore = resultReads, os.clock()
            local _, buys, _, count = pt.Deals.ReadItemSearch(C_AuctionHouse.MakeItemKey(58501), now)
            local cpuMS = (os.clock() - cpuBefore) * 1000
            local key = pt.VariantKey(C_AuctionHouse.MakeItemKey(58501))
            check(count == size and buys[key].price == signatures[size].cost,
                "supplied search reader sees the same cheapest non-stackable item price")
            print(string.format("BOOK mode=ProfitTop-0.1.13 rows=%d reads=%d max_slice_reads=%d modeled_slice_ms=%.3f cpu_ms=%.3f cost=%d",
                size, resultReads - readsBefore, resultReads - readsBefore, (resultReads - readsBefore) * readUS / 1000, cpuMS, buys[key].price))
        end
    end
    event("AUCTION_HOUSE_CLOSED")
    drain()
    print("Timings are offline Lua/mock measurements. modeled_slice_ms charges native reads only; no network or game latency is measured.")
end
BenchmarkBooks()
]=]
assert(loadstring(source .. cases, "@Benchmark-ProfitMasterBooks"))()
