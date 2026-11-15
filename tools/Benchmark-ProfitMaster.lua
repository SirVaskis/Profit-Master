-- Synthetic repeated-listing comparison. This does not measure server/game speed.
local baseline = assert(os.getenv("PROFITMASTER_BASELINE_DIR"), "Set PROFITMASTER_BASELINE_DIR to saved 0.1.2 Lua source")
local old, current = {}, {}
local calls = 0
local prices = {}
for i = 1, 100 do prices["item:" .. i] = i * 10 end
C_Item = { GetItemInfo = function(link)
    calls = calls + 1
    return link, link, 1, 1, 1, "", "", 20, "", 1, prices[link]
end }
assert(loadfile(baseline .. "/Deals.lua"))("ProfitMaster", old)
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", current)
local rows = {}
for i = 1, 200000 do
    local id = (i - 1) % 100 + 1
    local count = (i - 1) % 20 + 1
    local cost = prices["item:" .. id] * count + (id % 2 == 0 and 1 or -1)
    rows[i] = { "item:" .. id, count, cost }
end
local function run(dealFunction)
    collectgarbage("collect")
    calls = 0
    local cache, deals, profit = {}, 0, 0
    local started = os.clock()
    for _, row in ipairs(rows) do
        local deal = dealFunction(row[1], row[2], row[3], cache)
        if deal then
            deals, profit = deals + 1, profit + deal.profit
        end
    end
    return os.clock() - started, calls, deals, profit
end
local oldTime, oldCalls, oldDeals, oldProfit = run(old.Deal)
local newTime, newCalls, newDeals, newProfit = run(current.Deal)
assert(oldDeals == newDeals and oldProfit == newProfit, "Profit results changed")
assert(oldCalls == #rows and newCalls == 100, "Repeated-link cache did not reduce lookups")
print(string.format("200000 repeated listings / 100 exact links: old %.3fs, %d vendor lookups; new %.3fs, %d lookups. Same %d deals / %d copper profit.",
    oldTime, oldCalls, newTime, newCalls, newDeals, newProfit))
print("Synthetic Lua 5.1 comparison only; not an in-game or network timing result.")
