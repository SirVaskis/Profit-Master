local _, addon = ...
local pace = {}
addon.QueryPace = pace

-- A shared rolling budget for our explicit searches and listing preparation.
-- Native readiness remains authoritative; purchases never enter this queue.
local frame = CreateFrame("Frame")
local active, timer, wake, sentAt, nextAt = false, nil, nil, nil, 0
local times, interval, backoff = {}, nil, 1
local function Public(value) return not (issecretvalue and issecretvalue(value)) end

local function CancelTimer()
    if timer then timer:Cancel(); timer = nil end
end

function pace.SetActive(enabled, callback)
    CancelTimer()
    active, wake = enabled == true, callback
    for _, event in ipairs({ "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" }) do
        if active then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
    end
    if not active then sentAt, nextAt = nil, 0 end
end

function pace.Wait(background)
    local now = GetTimePreciseSec()
    while times[1] and now - times[1] >= 60 do table.remove(times, 1) end
    -- Leave 25 search slots for player-selected checks instead of spending the
    -- documented 100/minute allowance entirely on background preparation.
    local cap = background and 75 or 100
    local budget = #times >= cap and math.max(0.01, times[#times - cap + 1] + 60 - now) or 0
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady()
    if not Public(ready) or ready ~= true then return nil end
    return math.max(budget, background and math.max(0, nextAt - now) or 0)
end

function pace.NoteSearch()
    local now = GetTimePreciseSec()
    times[#times + 1], sentAt = now, now
end

function pace.Schedule(seconds)
    if not active or not seconds or seconds <= 0 then return end
    CancelTimer()
    timer = C_Timer.NewTimer(seconds, function()
        timer = nil
        if active and wake then wake() end
    end)
end

frame:SetScript("OnEvent", function(_, event)
    if not active then return end
    local now = GetTimePreciseSec()
    if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        backoff, sentAt = math.min(8, backoff * 2), nil
        nextAt = now + math.max(1, (interval or 0.5) * backoff)
    else
        if sentAt then
            local elapsed = now - sentAt
            if elapsed > 0 and elapsed < 30 then interval = interval and interval * 0.7 + elapsed * 0.3 or elapsed end
            sentAt, backoff = nil, math.max(1, backoff * 0.75)
        end
        nextAt = now + (interval or 0) * 0.25 * backoff
    end
    if wake then wake() end
end)
