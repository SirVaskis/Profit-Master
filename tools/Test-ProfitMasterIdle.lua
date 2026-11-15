-- Closed-AH work/memory checks using production code, mocked native APIs only.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[
local function CheckClosedHouseIdle()
    local beforeChecks = checks
    local function requests() return queries + exactQueries + refreshes + more + scans + browseScans end
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    values["item:49801"] = 100
    listener:ReceiveEvent("complete", { scanned(49801, "item:49801", 1, 50) })
    runImmediate()
    check(window.rows[1].deal and window.rows[1].deal.itemID == 49801, "fresh AH scan has a transient candidate to release")
    local weak = setmetatable({ window.rows[1].deal }, { __mode = "v" })
    local historyCount = ProfitMasterDB.items[49801].vendorPrice
    event("AUCTION_HOUSE_CLOSED")
    drain()
    collectgarbage("collect")
    check(weak[1] == nil and not window.rows[1].deal,
        "closing releases candidate objects rather than retaining them in hidden rows")
    check(ProfitMasterDB.items[49801].vendorPrice == historyCount,
        "transient cleanup preserves saved price history")
    check(next(subscribed) == nil, "Auctionator scan listeners detach outside the AH")
    for name in pairs(eventFrame.events) do
        check(name == "AUCTION_HOUSE_SHOW" or name == "AUCTION_HOUSE_CLOSED"
            or name == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "closed main frame only watches AH lifecycle")
    end
    local bagEvents = 0
    for _, frame in ipairs(frames) do
        if frame.events.BAG_UPDATE_DELAYED then bagEvents = bagEvents + 1 end
    end
    check(bagEvents == 1, "closing the Auction House retains the one event-driven bag advice listener")
    for _, timer in ipairs(timers) do check(timer.cancelled, "closing cancels every active work timer") end
    local beforeRequests, beforeBids, beforeItems, beforeWrites = requests(), bidAttempts, itemLookups, textWrites
    local beforeLogs = ProfitMasterDebugDB.sequence
    local empty = {}
    local function idleCycles()
        for i = 1, 10000 do
            listener:ReceiveEvent("start", empty) -- late/stale provider callbacks
            listener:ReceiveEvent("progress", .5)
            listener:ReceiveEvent("failed", empty)
            listener:ReceiveEvent("complete", empty)
            event("ITEM_DATA_LOAD_RESULT", 49801, true)
            event("GET_ITEM_INFO_RECEIVED", 49801, true)
            event("REPLICATE_ITEM_LIST_UPDATE")
            event("AUCTION_HOUSE_CLOSED") -- duplicate notifications stay inert
        end
    end
    idleCycles() -- Warm the host LuaJIT before measuring addon allocations.
    collectgarbage("collect")
    collectgarbage("stop")
    local beforeMemory = collectgarbage("count")
    idleCycles()
    local memoryGrowth = collectgarbage("count") - beforeMemory
    collectgarbage("restart")
    check(requests() == beforeRequests and bidAttempts == beforeBids and itemLookups == beforeItems
        and textWrites == beforeWrites and ProfitMasterDebugDB.sequence == beforeLogs,
        "ten thousand closed-AH auction callbacks cause no queries, item reads, UI updates, purchases or diagnostic growth")
    check(memoryGrowth < 1, "inactive callbacks allocate less than 1 KiB over ten thousand mocked cycles; measured " .. memoryGrowth .. " KiB")
    check(#timers == 0, "inactive events cannot restart a timer")

    -- Close with outstanding vendor metadata work, then deliver its late result.
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    values["item:49802"] = nil
    listener:ReceiveEvent("complete", { scanned(49802, "item:49802", 1, 50) })
    check(eventFrame.events.ITEM_DATA_LOAD_RESULT, "test has outstanding item metadata work")
    event("AUCTION_HOUSE_CLOSED")
    beforeRequests, beforeItems = requests(), itemLookups
    values["item:49802"] = 100
    event("ITEM_DATA_LOAD_RESULT", 49802, true)
    drain()
    check(not window.rows[1].deal and requests() == beforeRequests and itemLookups == beforeItems,
        "late metadata and canceled timer callbacks cannot revive closed-house work")
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    check(next(subscribed) ~= nil, "reopening reconnects Auctionator once")
    listener:ReceiveEvent("complete", { scanned(49802, "item:49802", 1, 50) })
    runImmediate()
    check(window.rows[1].deal and window.rows[1].deal.itemID == 49802,
        "fresh scanning and metadata valuation recover after idle cleanup")
    event("AUCTION_HOUSE_CLOSED")
    drain()
    print("Profit Master idle: " .. (checks - beforeChecks) .. " offline assertions passed; 10000 closed cycles grew "
        .. string.format("%.3f", memoryGrowth) .. " KiB (Lua 5.1 mock, not client RAM).")
end
CheckClosedHouseIdle()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterIdle"))()
