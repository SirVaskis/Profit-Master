-- Offline native-browse lifecycle tests. No game requests or purchases.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local secret = {}
issecretvalue = function(value) return value == secret end
local now, timers, eventFrame = 0, {}, nil
GetTime = function() return now end
local function activeTimers()
    local count = 0
    for _, timer in ipairs(timers) do if not timer.cancelled and not timer.fired then count = count + 1 end end
    return count
end
C_Timer = { NewTimer = function(delay, callback)
    check(activeTimers() == 0, "scanner owns at most one watchdog/deferred page timer")
    local timer = { due = now + delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function advance(seconds)
    now = now + seconds
    for _ = 1, 100 do
        local fired = false
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired and timer.due <= now then
                timer.fired, fired = true, true
                timer.callback()
            end
        end
        if not fired then return end
    end
    error("deferred browse pages did not terminate")
end
CreateFrame = function()
    eventFrame = { events = {} }
    function eventFrame:RegisterEvent(name) self.events[name] = true end
    function eventFrame:UnregisterEvent(name) self.events[name] = nil end
    function eventFrame:SetScript(_, callback) self.callback = callback end
    return eventFrame
end
local function event(name, rows)
    if eventFrame.events[name] then eventFrame.callback(eventFrame, name, rows) end
end
local ready, full, browse, sends, more, reads = true, false, {}, 0, 0, 0
C_AuctionHouse = {
    SendBrowseQuery = function(query)
        check(query.searchString == "" and #query.sorts == 0 and #query.filters == 0 and #query.itemClassFilters == 0,
            "initial native request is an unfiltered browse scan")
        sends, ready = sends + 1, false
    end,
    RequestMoreBrowseResults = function() more, ready = more + 1, false end,
    GetBrowseResults = function() reads = reads + 1; return browse end,
    HasFullBrowseResults = function() return full end,
    IsThrottledMessageSystemReady = function() return ready end,
    PlaceBid = function() error("browse scanning must never submit a purchase") end,
}
local addon = {}
assert(loadfile("addons/ProfitMaster/BrowseScanner.lua"))("ProfitMaster", addon)
local scanner, received, completed, failed, snapshot = addon.BrowseScanner, 0, 0, 0, nil
local function rows(value) received, snapshot = received + 1, value end
local function done(value)
    check(not scanner.Active(), "scanner releases its state before completion callback")
    completed, snapshot = completed + 1, value
end
local function failure(reason)
    check(type(reason) == "string" and not scanner.Active(), "failure is explicit and releases scanner state")
    failed = failed + 1
end
local function row(id, suffix)
    return { itemKey = { itemID = id, itemLevel = 10, itemSuffix = suffix or 0, battlePetSpeciesID = 0 },
        minPrice = 50, totalQuantity = 2 }
end

check(not scanner.Active() and not scanner.Paused(), "scanner is idle until an explicit start")
ready = false
check(not scanner.Start(rows, done, failure) and sends == 0, "native throttle prevents the initial query")
ready = secret
check(not scanner.Start(rows, done, failure), "restricted readiness is not inspected as a boolean")
ready = true
check(scanner.Start(rows, done, failure) and scanner.Active() and sends == 1, "explicit start sends exactly one browse request")
check(not scanner.Start(rows, done, failure) and sends == 1, "a second click cannot start another scan")
event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { row(99) })
check(received == 0, "an old added event cannot replace the initial query snapshot")
browse = { row(1) }
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
local growing = snapshot
check(received == 1 and #snapshot == 1 and reads == 1 and more == 0,
    "initial browse snapshot streams immediately and waits for native throttle readiness")
ready = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(more == 1 and activeTimers() == 1, "ready event requests one next page with one watchdog")
advance(1)
scanner.Pause()
scanner.Pause()
check(scanner.Paused() and activeTimers() == 0, "pause is idempotent and stops the watchdog")
advance(30)
check(failed == 0 and scanner.Active(), "reviewing a purchase cannot expire the paused browse request")
event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { row(2), row(1), row(2) })
check(snapshot == growing and #snapshot == 2 and more == 1, "in-flight results append once while paused without requesting a page")
browse = { row(999) }
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(reads == 1 and snapshot == growing and #snapshot == 2, "item-query browse updates cannot reset the scan snapshot")
scanner.Resume()
check(not scanner.Paused() and more == 1, "resume respects the native throttle")
ready = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(more == 2, "resume continues from the next browse page rather than restarting the query")
full = true
event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { row(3), row(3, -5) })
check(completed == 1 and #snapshot == 4 and snapshot == growing,
    "full result coverage completes with distinct exact suffix keys and the original row buffer")
check(activeTimers() == 0 and not next(eventFrame.events), "completion stops all scanner events and timers")

ready, full = true, false
scanner.Start(rows, done, failure)
advance(9)
scanner.Pause()
advance(100)
scanner.Resume()
advance(5)
check(scanner.Active(), "resume preserves the six seconds left in the original in-flight deadline")
advance(1)
check(failed == 1 and not scanner.Active(), "an unanswered request has a bounded remaining deadline")
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(completed == 1, "late results after timeout cannot complete a stopped scan")

ready = true
scanner.Start(rows, done, failure)
browse = { row(4) }
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
advance(15)
check(failed == 2, "a missing throttle-ready event cannot leave the scanner waiting forever")

ready = true
scanner.Start(rows, done, failure)
scanner.Pause()
event("AUCTION_HOUSE_BROWSE_FAILURE")
check(failed == 3 and not scanner.Active(), "server browse failure clears a paused scan")
ready = true
scanner.Start(rows, done, failure)
event("AUCTION_HOUSE_CLOSED")
check(failed == 4 and activeTimers() == 0, "Auction House close terminates scanner work")
ready = true
scanner.Start(rows, done, failure)
scanner.Stop()
scanner.Stop()
advance(100)
check(failed == 4 and not scanner.Active(), "explicit stop is idempotent and does not report a failure")

ready, full = true, false
scanner.Start(rows, done, failure)
local invalid = row(10)
invalid.itemKey.itemID = secret
browse = { invalid, secret, row(11) }
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(#snapshot == 1 and snapshot[1].itemKey.itemID == 11, "restricted row values are skipped before key formatting")
full = secret
event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {})
check(failed == 5, "restricted coverage fails honestly without inventing a completed scan")

ready, full = true, false
scanner.Start(function(value) rows(value); scanner.Stop() end, done, failure)
browse = { row(12) }
local before = more
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(not scanner.Active() and more == before, "an onRows callback may stop scanning before another request is sent")

-- Even synchronous mocks must yield between pages instead of recursively scanning.
local originalSend, originalMore = C_AuctionHouse.SendBrowseQuery, C_AuctionHouse.RequestMoreBrowseResults
local page = 0
C_AuctionHouse.SendBrowseQuery = function()
    sends, page, ready, full = sends + 1, 1, true, false
    browse = { row(101) }
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
end
C_AuctionHouse.RequestMoreBrowseResults = function()
    more, page, ready = more + 1, page + 1, true
    full = page == 20
    event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { row(100 + page) })
end
ready = true
scanner.Start(rows, done, failure)
check(page == 2 and scanner.Active(), "synchronous initial completion dispatches only one additional page before yielding")
advance(0)
check(completed == 2 and #snapshot == 20 and not scanner.Active() and activeTimers() == 0,
    "bounded synchronous page dispatch eventually completes without recursion or idle timers")
C_AuctionHouse.SendBrowseQuery, C_AuctionHouse.RequestMoreBrowseResults = originalSend, originalMore

local batches, keys = {}, {}
for id = 1, 350 do keys[id] = row(id).itemKey end
C_AuctionHouse.SearchForItemKeys = function(batch)
    batches[#batches + 1], ready = batch, false
end
ready, full = true, true
check(scanner.StartKeys(keys, rows, done, failure), "Quick scan starts from known item keys")
check(#batches == 1 and #batches[1] == 50, "Quick scan sends at most fifty keys in its first query")
keys[1].itemID = 9999
check(batches[1][1].itemID == 1, "caller mutation cannot change the dispatched watchlist snapshot")
for batch = 1, 6 do
    browse = { row((batch - 1) * 50 + 1) }
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    if batch < 6 then
        check(#batches == batch, "next batch waits for the native channel")
        scanner.Pause()
        ready = true
        event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        check(#batches == batch, "buying can pause the gap between Quick scan batches")
        scanner.Resume()
        check(#batches == batch + 1 and #batches[batch + 1] == 50, "resume sends only the next fifty-key batch")
    end
end
check(#batches == 6 and #snapshot == 6 and not scanner.Active(), "Quick scan caps coverage at 300 keys and releases all work")
ready, full = true, true
scanner.StartKeys({ row(1).itemKey }, rows, done, failure)
local beforeFailures = failed
browse = { row(900) }
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(failed == beforeFailures + 1 and not scanner.Active(), "a foreign query cannot be accepted as watchlist coverage")
ready = true
scanner.StartKeys({ row(1).itemKey }, rows, done, failure)
browse = {}
beforeFailures = failed
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(scanner.Active() and failed == beforeFailures, "first empty watchlist reply is retried instead of deleting candidates")
ready = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(failed == beforeFailures + 1 and not scanner.Active(), "two empty replies leave coverage explicitly uncertain")
check(activeTimers() == 0 and not next(eventFrame.events), "Quick scan leaves no background timer or event listeners")
print("Profit Master browse scanner: " .. checks .. " offline assertions passed (Lua 5.1).")
