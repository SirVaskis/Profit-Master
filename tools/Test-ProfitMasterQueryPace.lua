-- Native readiness and a rolling budget, using a deterministic offline clock.
local checks, now, ready, frame, timers = 0, 1000, true, nil, {}
local function check(value, text) checks = checks + 1; assert(value, text) end
GetTimePreciseSec = function() return now end
issecretvalue = function(value) return value == "SECRET" end
C_AuctionHouse = { IsThrottledMessageSystemReady = function() return ready end }
CreateFrame = function()
    frame = { events = {} }
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:UnregisterEvent(name) self.events[name] = nil end
    function frame:SetScript(_, callback) self.callback = callback end
    return frame
end
C_Timer = { NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local addon, wakes = {}, 0
assert(loadfile("addons/ProfitMaster/QueryPace.lua"))("ProfitMaster", addon)
local pace = addon.QueryPace
pace.SetActive(true, function() wakes = wakes + 1 end)
for _ = 1, 75 do check(pace.Wait(true) == 0, "background work has room below its reserved budget"); pace.NoteSearch() end
check(pace.Wait(true) == 60 and pace.Wait(false) == 0, "75 background queries leave 25 foreground slots")
for _ = 1, 25 do check(pace.Wait(false) == 0, "foreground checks can use their reserved slots"); pace.NoteSearch() end
check(pace.Wait(false) == 60, "all searches obey the rolling 100-per-minute allowance")
now = now + 59
check(pace.Wait(false) == 1, "the oldest request must actually age out")
now = now + 1
check(pace.Wait(false) == 0, "requests become available at the rolling window boundary")
ready = false
check(pace.Wait(false) == nil, "own budget cannot override a busy native channel")
ready = "SECRET"
check(pace.Wait(true) == nil, "restricted readiness cannot dispatch a search")
ready = true
pace.NoteSearch()
now = now + 0.4
frame.callback(frame, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(pace.Wait(true) > 0 and pace.Wait(false) == 0, "observed response pacing delays background work only")
frame.callback(frame, "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
check(pace.Wait(true) >= 1, "a dropped request backs off background work")
pace.Schedule(1)
pace.Schedule(2)
check(timers[1].cancelled and not timers[2].cancelled, "all pacing wakeups share one cancelable timer")
pace.SetActive(false)
check(timers[2].cancelled and not next(frame.events), "closing cancels the wakeup and removes native subscriptions")
local before = wakes
timers[2].callback()
check(wakes == before, "late callbacks cannot restart closed-house work")
print("Profit Master query pacing: " .. checks .. " assertions passed (Lua 5.1).")
