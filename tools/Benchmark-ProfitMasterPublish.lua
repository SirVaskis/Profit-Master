-- Offline publication cost, using the actual Deals.lua sort implementation.
-- Virtual arrival times model one newly valued candidate per millisecond.
-- Does not measure native UI methods, network time, timers or in-game FPS.
if jit then jit.off(); jit.flush() end
local addon = {}
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", addon)
local sort = table.sort
local function Median(values)
    sort(values)
    return values[math.floor(#values / 2) + 1]
end

local function Run(count, interval, countComparisons)
    collectgarbage("collect")
    local best, candidates = {}, {}
    local publishedAt, publications, comparisons = -math.huge, 0, 0
    local elapsed, longest = 0, 0
    local function Publish()
        local started = os.clock()
        candidates = {}
        for _, deal in pairs(best) do candidates[#candidates + 1] = deal end
        if countComparisons then
            table.sort = function(rows, compare)
                sort(rows, function(a, b)
                    comparisons = comparisons + 1
                    return compare(a, b)
                end)
            end
        end
        addon.SortDeals(candidates)
        table.sort = sort
        local duration = os.clock() - started
        elapsed, longest = elapsed + duration, math.max(longest, duration)
        publications = publications + 1
    end
    for id = 1, count do
        best[id] = {itemID=id, link="item:" .. (100000 + id),
            cost=100 + id % 29, profit=3 + (id * 104729) % 10007}
        local virtualTime = id / 1000
        if virtualTime - publishedAt >= interval then
            Publish()
            publishedAt = virtualTime
        end
    end
    Publish() -- Forced completion remains immediate at every interval.
    local signature = 0
    for rank, deal in ipairs(candidates) do signature = signature + rank * deal.itemID end
    return elapsed, longest, publications, comparisons, signature
end

for _, count in ipairs({6000, 12000}) do
    local expectedSignature
    for _, interval in ipairs({.05, .25}) do
        local totals, peaks, publications = {}, {}
        for trial = 1, 5 do
            local total, peak, published, _, signature = Run(count, interval, false)
            if expectedSignature then assert(signature == expectedSignature, "Final results differ")
            else expectedSignature = signature end
            totals[trial], peaks[trial], publications = total, peak, published
        end
        local _, _, _, comparisons, signature = Run(count, interval, true)
        assert(signature == expectedSignature, "Instrumented results differ")
        print(string.format("%d candidates, %.0fms publication interval: %d publications, %d comparisons, %.3fms median total, %.3fms median longest publication; modeled <=%d UI writes / %d money formats.",
            count, interval * 1000, publications, comparisons, Median(totals) * 1000,
            Median(peaks) * 1000, publications * 78, publications * 24))
    end
end
print("Five trials, Lua 5.1-compatible runtime, JIT disabled. Output and final ordering identical. UI counts assume eight displayed rows and all Refresh setters run; they are call counts, not native timings.")
