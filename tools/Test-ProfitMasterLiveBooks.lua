-- Actual foreground/preparation handlers; deterministic offline native results.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[
local function CheckLiveBooks()
    local beforeChecks = checks
    local function emit(name, arg)
        local listeners = {}
        for _, frame in ipairs(frames) do
            if frame.events[name] then listeners[#listeners + 1] = frame end
        end
        for _, frame in ipairs(listeners) do frame.scripts.OnEvent(frame, name, arg) end
    end
    local function reset()
        event("AUCTION_HOUSE_CLOSED")
        runImmediate()
        now = now + 120
        commodity, full, throttle, keyInfoAvailable, money = false, true, true, true, 100000
        addon.Listings.SetEnabled(false)
        addon.Listings.SetOneClick(false)
        addon.Disenchant.SetEnabled(false)
        assert(addon.SetMinimumProfit(3))
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
        values["item:58001"], values["item:58001:variant"] = 100, 2000
        listener:ReceiveEvent("complete", { scanned(58001, "item:58001", 1, 50) })
        runImmediate()
    end
    reset()
    money = 100
    results = { listing(58011, "item:58001:variant", 1, 500), listing(58012, "item:58001", 3, 50) }
    addon.ChangePrepareListings(true)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    runImmediate()
    check(window.rows[1].deal.cost == 50 and window.rows[1].deal.available == 3,
        "preparation chooses an affordable live variant instead of the largest unaffordable profit")
    addon.ChangePrepareListings(false)

    reset()
    results = {}
    for i = 1, 1500 do results[i] = listing(950000 + i, "item:58001", 1, 50) end
    addon.ChangePrepareListings(true)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    local searchesBeforeHandoff = queries + exactQueries
    local readsBeforeHandoff = resultReads
    click(window.rows[1].action)
    runImmediate()
    check(popup.shown and popup.data.available == 1500 and queries + exactQueries == searchesBeforeHandoff
        and resultReads == readsBeforeHandoff + 1500,
        "clicking a preparation whose reply already arrived reads the existing book instead of waiting for a second event")
    cancelPopup()

    reset()
    results = {}
    for i = 1, 25000 do results[i] = listing(59000 + i, "item:58001", 1, 50) end
    local beforeBids, beforeQueries = bidAttempts, queries + exactQueries
    local originalDeal = addon.LiveDeal
    local weakCache = setmetatable({}, { __mode = "v" })
    addon.LiveDeal = function(info, cache)
        if cache then weakCache[1] = cache end
        return originalDeal(info, cache)
    end
    click(window.rows[1].action)
    local beforeReads = resultReads
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    check(resultReads - beforeReads <= 10000 and not popup.shown,
        "a large foreground book yields after at most 10,000 rows before opening a quote")
    emit("ITEM_SEARCH_RESULTS_ADDED", C_AuctionHouse.MakeItemKey(58001))
    results[25000] = listing(900001, "item:58001", 1, 40)
    runImmediate()
    addon.LiveDeal = originalDeal
    collectgarbage("collect")
    collectgarbage("collect")
    check(weakCache[1] == nil, "a shown quote does not retain the completed book's vendor cache through a fired timer")
    check(popup.shown and popup.data.cost == 40 and popup.data.auctionID == 900001
        and popup.data.available == 1, "an update during processing restarts local validation before offering the best auction")
    check(bidAttempts == beforeBids and queries + exactQueries == beforeQueries + 1,
        "bounded validation and event coalescing send no extra search or purchase")
    cancelPopup()

    reset()
    results = { listing(58021, "item:58001", 4, 50), listing(58021, "item:58001", 4, 50),
        listing(58022, "item:58001", 2, 50), listing(58023, "item:58001:variant", 1, 1500) }
    money = 100
    click(window.rows[1].action)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    check(popup.shown and popup.data.cost == 50 and popup.data.available == 6,
        "foreground selection excludes unaffordable variants and counts each auction ID only once")
    cancelPopup()

    reset()
    results = {}
    for i = 1, 25000 do results[i] = listing(62000 + i, "item:58001", 1, 50) end
    results[25000] = listing(900002, "item:58001:variant", 1, 500)
    money = 100
    click(window.rows[1].action)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    money = 1000
    runImmediate()
    check(popup.shown and popup.data.cost == 500, "a gold change during reading re-evaluates affordability before choosing a quote")
    cancelPopup()

    reset()
    local originalRead, originalClock = C_AuctionHouse.GetItemSearchResultInfo, GetTimePreciseSec
    local simulated = now
    GetTimePreciseSec = function() return simulated end
    C_AuctionHouse.GetItemSearchResultInfo = function(key, index)
        simulated = simulated + 0.001
        return originalRead(key, index)
    end
    click(window.rows[1].action)
    beforeReads = resultReads
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    check(resultReads - beforeReads <= 5 and not popup.shown, "slow native getters yield at the four-millisecond budget before the row cap")
    C_AuctionHouse.GetItemSearchResultInfo, GetTimePreciseSec = originalRead, originalClock
    runImmediate()
    check(popup.shown, "a time-budgeted foreground book eventually opens confirmation")
    cancelPopup()

    reset()
    results = {}
    for i = 1, 25000 do results[i] = listing(61000 + i, "item:58001", 1, 50) end
    click(window.rows[1].action)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    event("AUCTION_HOUSE_CLOSED")
    beforeReads = resultReads
    runImmediate()
    check(resultReads == beforeReads and not popup.shown, "closing the AH cancels a partially read foreground book")

    reset()
    click(window.rows[1].action)
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(58001))
    beforeQueries = queries + exactQueries
    now = now + 16
    runImmediate()
    check(not popup.shown and queries + exactQueries == beforeQueries,
        "a large local read retains its original verification deadline and never retries a purchase")
    event("AUCTION_HOUSE_CLOSED")
    drain()
    print("Profit Master live books: " .. (checks - beforeChecks) .. " assertions passed (Lua 5.1).")
end
CheckLiveBooks()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterLiveBooks"))()
