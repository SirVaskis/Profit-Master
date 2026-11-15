local _, addon = ...
local scanner = {}
addon.BrowseScanner = scanner

-- Public browse API/events checked against Forever 1.60.1.70938. Item searches
-- update browse summaries too, so only the initial UPDATED starts this snapshot.
local frame = CreateFrame("Frame")
local state
local EVENTS = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_CLOSED" }
local NextPage

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Integer(value, minimum)
    return Public(value) and type(value) == "number" and value == value
        and value < math.huge and value > -math.huge and value >= minimum and value == math.floor(value)
end

local function CancelTimer(work)
    if work.timer then work.timer:Cancel(); work.timer = nil end
end

function scanner.Stop()
    if not state then return end
    CancelTimer(state)
    state = nil
    for _, name in ipairs(EVENTS) do frame:UnregisterEvent(name) end
end

local function Finish(work, failure)
    if state ~= work then return end
    scanner.Stop()
    if failure then work.onFailed(failure)
    else work.onComplete(work.rows) end
end

local function Arm(work, seconds)
    CancelTimer(work)
    work.remaining = seconds or 15
    work.deadline = GetTime() + work.remaining
    work.timer = C_Timer.NewTimer(work.remaining, function()
        if state == work and not work.paused then Finish(work, "Browse request timed out.") end
    end)
end

local function Full(work)
    local value = C_AuctionHouse.HasFullBrowseResults()
    if not Public(value) or type(value) ~= "boolean" then
        Finish(work, "Browse coverage is unavailable.")
        return nil
    end
    return value
end

local function Append(work, rows)
    if not Public(rows) or type(rows) ~= "table" then return false end
    for _, row in ipairs(rows) do
        if Public(row) and type(row) == "table" then
            local key = row.itemKey
            if Public(key) and type(key) == "table" then
                local id, level, suffix, pet = key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID
                local quantity, price = row.totalQuantity, row.minPrice
                if Public(level) and Public(suffix) and Public(pet) then
                    level, suffix, pet = level or 0, suffix or 0, pet or 0
                    if Integer(id, 1) and Integer(level, 0) and Integer(suffix, -math.huge) and Integer(pet, 0)
                        and Integer(quantity, 1) and Integer(price, 1) then
                        local identity = table.concat({ id, level, suffix, pet }, ":")
                        if work.expected and not work.expected[id] then return false end
                        if work.batches then work.batchRows = work.batchRows + 1 end
                        if not work.seen[identity] then
                            work.seen[identity] = true
                            work.rows[#work.rows + 1] = row
                        end
                    end
                end
            end
        end
    end
    return true
end

local function Received(work, rows)
    CancelTimer(work)
    work.pending, work.remaining = false, nil
    if not Append(work, rows) then Finish(work, "Browse results are unavailable."); return end
    work.onRows(work.rows)
    if state ~= work then return end
    local full = Full(work)
    if full and work.batches and work.batchRows == 0 then
        -- The comparison addon reports an initial empty reply on Forever.
        -- Retry once; two empty replies leave coverage uncertain rather than
        -- deleting all watched candidates as if the market were empty.
        if work.emptyRetry then Finish(work, "Quick scan returned no rows for a batch; use a full scan to confirm.")
        else work.emptyRetry, work.nextBatch = true, true; NextPage(work) end
    elseif full and work.batches and work.batch < #work.batches then
        work.emptyRetry = nil
        work.batch, work.nextBatch = work.batch + 1, true
        NextPage(work)
    elseif full then Finish(work)
    elseif full == false then NextPage(work) end
end

NextPage = function(work)
    if state ~= work or work.paused or work.pending or (work.initial and not work.nextBatch) then return end
    if work.sending then work.nextNeeded = true; return end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady()
    if not Public(ready) or ready ~= true then
        -- The same bounded watchdog covers a missing throttle-ready notification.
        if not work.timer then Arm(work) end
        return
    end
    if work.nextBatch and addon.QueryPace then
        local wait = addon.QueryPace.Wait(true)
        if wait ~= 0 then
            if wait then Arm(work, wait + 15); addon.QueryPace.Schedule(wait) end
            return
        end
    end
    work.pending, work.sending = true, true
    Arm(work)
    if work.nextBatch then
        work.initial, work.nextBatch = true, nil
        work.batchRows = 0
        work.expected = {}
        for _, key in ipairs(work.batches[work.batch]) do
            work.expected[key.itemID] = true
        end
        if addon.QueryPace then addon.QueryPace.NoteSearch() end
        C_AuctionHouse.SearchForItemKeys(work.batches[work.batch], {})
    else C_AuctionHouse.RequestMoreBrowseResults() end
    work.sending = false
    if state == work and work.nextNeeded and not work.paused then
        work.nextNeeded = nil
        CancelTimer(work)
        work.timer = C_Timer.NewTimer(0, function()
            if state == work then work.timer = nil; NextPage(work) end
        end)
    end
end

function scanner.Wake()
    if state then NextPage(state) end
end

function scanner.Active()
    return state ~= nil
end

function scanner.Paused()
    return state and state.paused == true or false
end

function scanner.Pause()
    if not state or state.paused then return end
    state.paused = true
    if state.timer then
        state.remaining = math.max(0, state.deadline and state.deadline - GetTime() or 15)
        CancelTimer(state)
    end
end

function scanner.Resume()
    local work = state
    if not work or not work.paused then return end
    work.paused = false
    if work.pending then Arm(work, work.remaining)
    else NextPage(work) end
end

function scanner.Start(onRows, onComplete, onFailed)
    if state or type(onRows) ~= "function" or type(onComplete) ~= "function" or type(onFailed) ~= "function"
        or not C_AuctionHouse or not C_AuctionHouse.SendBrowseQuery
        or not C_AuctionHouse.RequestMoreBrowseResults or not C_AuctionHouse.HasFullBrowseResults
        or not C_AuctionHouse.GetBrowseResults or not C_AuctionHouse.IsThrottledMessageSystemReady then return false end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady()
    if not Public(ready) or ready ~= true then return false end
    local work = { rows = {}, seen = {}, initial = true, pending = true, paused = false,
        onRows = onRows, onComplete = onComplete, onFailed = onFailed }
    state = work
    for _, name in ipairs(EVENTS) do frame:RegisterEvent(name) end
    Arm(work)
    C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    return true
end

-- Refresh known item keys without claiming coverage of the entire market.
-- Fifty keys per request keeps each batch small; the persisted list is capped.
function scanner.StartKeys(keys, onRows, onComplete, onFailed)
    if state or type(keys) ~= "table" or type(onRows) ~= "function" or type(onComplete) ~= "function"
        or type(onFailed) ~= "function" or not C_AuctionHouse.SearchForItemKeys then return false end
    local batches, seen, count = {}, {}, 0
    for _, key in ipairs(keys) do
        if not Public(key) or type(key) ~= "table" then return false end
        local id, level, suffix, pet = key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID
        if not Public(level) or not Public(suffix) or not Public(pet) then return false end
        level, suffix, pet = level or 0, suffix or 0, pet or 0
        if not Integer(id, 1) or not Integer(level, 0) or not Integer(suffix, -math.huge) or not Integer(pet, 0) then return false end
        local identity = table.concat({ id, level, suffix, pet }, ":")
        if not seen[identity] then
            seen[identity] = true
            if count >= 300 then break end
            local index = math.floor(count / 50) + 1
            if not batches[index] then batches[index] = {} end
            local batch = batches[index]
            batch[#batch + 1] = { itemID = id, itemLevel = level, itemSuffix = suffix, battlePetSpeciesID = pet }
            count = count + 1
        end
    end
    if #batches == 0 then return false end
    local work = { rows = {}, seen = {}, batches = batches, batch = 1, nextBatch = true,
        onRows = onRows, onComplete = onComplete, onFailed = onFailed }
    state = work
    for _, name in ipairs(EVENTS) do frame:RegisterEvent(name) end
    Arm(work)
    NextPage(work)
    return true
end

frame:SetScript("OnEvent", function(_, event, rows)
    local work = state
    if not work then return end
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        if not work.initial or not work.pending then return end
        work.initial = false
        Received(work, C_AuctionHouse.GetBrowseResults())
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if not work.initial and not work.nextBatch then Received(work, rows) end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        NextPage(work)
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then Finish(work, "Browse request failed.")
    elseif event == "AUCTION_HOUSE_CLOSED" then Finish(work, "Auction House closed.") end
end)
