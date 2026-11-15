-- Offline Lua 5.1 comparison; no WoW process, server requests or real timers.
-- Measures valuation-loop overhead, not native API cost or in-game FPS.
-- Remove optional JIT warm-up/trace effects from this interpreter comparison.
local runtime = _VERSION
if jit then
    runtime = runtime .. "; " .. jit.version .. " (JIT disabled)"
    jit.off()
    jit.flush()
end
local addon = {}
local lookups = 0
C_Item = { GetItemInfo = function(link)
    lookups = lookups + 1
    local id = assert(tonumber(link:match("item:(%d+)")))
    return link, link, 1, 1, 1, "", "", 1, "", 1, id + 100
end }
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", addon)

local rows = {}
for i = 1, 200000 do
    local id = (i - 1) % 1000 + 1
    rows[i] = { link = "item:" .. id, cost = id + (i % 3 == 0 and 101 or 90) }
end

local function Run(kind)
    collectgarbage("collect")
    lookups = 0
    local cache, best = {}, {}
    local eligible, profit, slices = 0, 0, 0
    local function Value(index)
        local row = rows[index]
        local deal = addon.Deal(row.link, 1, row.cost, cache)
        if deal then
            eligible, profit = eligible + 1, profit + deal.profit
            local previous = best[deal.link]
            if not previous or deal.profit > previous.profit then best[deal.link] = deal end
        end
    end
    local step
    if kind == "batches" then
        local index = 1
        step = function()
            local started = os.clock()
            for i = index, math.min(index + 999, #rows) do
                Value(i)
                index = i + 1
                if os.clock() - started >= 0.004 then break end
            end
            return index > #rows
        end
    else
        local worker = coroutine.create(function()
            local started, count = os.clock(), 0
            for i = 1, #rows do
                Value(i)
                count = count + 1
                if i < #rows and (count >= 1000 or os.clock() - started >= 0.004) then
                    coroutine.yield()
                    started, count = os.clock(), 0
                end
            end
        end)
        step = function()
            local ok, message = coroutine.resume(worker)
            assert(ok, message)
            return coroutine.status(worker) == "dead"
        end
    end
    local started = os.clock()
    repeat
        slices = slices + 1
    until step()
    local elapsed = os.clock() - started
    return elapsed, eligible, profit, lookups, slices
end

-- Warm both paths, then alternate order to reduce warm-up/order bias.
Run("batches"); Run("coroutine")
local times = { batches = {}, coroutine = {} }
local expected
for trial = 1, 7 do
    local order = trial % 2 == 0 and { "coroutine", "batches" } or { "batches", "coroutine" }
    for _, kind in ipairs(order) do
        local elapsed, eligible, profit, calls, slices = Run(kind)
        local result = eligible .. ":" .. profit .. ":" .. calls
        expected = expected or result
        assert(result == expected, "scheduling changed valuation results or engine-call counts")
        times[kind][#times[kind] + 1] = elapsed
        assert(slices >= 200, "work must remain sliced")
    end
end
table.sort(times.batches)
table.sort(times.coroutine)
local batches, coroutineTime = times.batches[4], times.coroutine[4]
print(runtime)
print(string.format("200000 rows, 1000 cached item links; 7 alternating trials. Median: batches %.4fs; coroutine %.4fs (ratio %.3f).",
    batches, coroutineTime, coroutineTime / batches))
print("Identical eligible-row/profit/lookup totals: " .. expected)
print("Synthetic CPU comparison only. Native WoW APIs, server delays, rendering and C_Timer scheduling are not measured.")
