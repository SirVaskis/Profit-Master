local _, addon = ...
local listings = {}
addon.Listings = listings

-- Prepare a small set of visible opportunities; never buy from a callback.
-- The native result book must still contain the exact auction on a player click.
local frame = CreateFrame("Frame")
local active, running, saved, targets, bought, changed, pending, timer, dispatching
local records, tried = {}, {}
local FRESH, RETRY, LIMIT = 60, 30, 20
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Number(value) return Public(value) and type(value) == "number" and value == value and value > 0 and value < math.huge end
local function Integer(value, minimum)
    return Public(value) and type(value) == "number" and value == value and value < math.huge
        and value >= minimum and value == math.floor(value)
end

local function Identity(key)
    if not Public(key) or type(key) ~= "table" then return nil end
    local id, level, suffix, pet = key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID
    if not Public(level) or not Public(suffix) or not Public(pet) then return nil end
    level, suffix, pet = level or 0, suffix or 0, pet or 0
    if not Integer(id, 1) or not Integer(level, 0) or not Integer(suffix, -math.huge) or not Integer(pet, 0) then return nil end
    return table.concat({ id, level, suffix, pet }, ":")
end

local function Trim(map)
    local count, oldest, at = 0, nil, math.huge
    for key, value in pairs(map) do
        count = count + 1
        local seen = type(value) == "table" and value.at or value
        if seen < at then oldest, at = key, seen end
    end
    if count > 40 then map[oldest] = nil end
end

function listings.Key(deal)
    local key = deal.itemKey or C_AuctionHouse.MakeItemKey(deal.itemID)
    if not Identity(key) then return nil end
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if not Public(info) or type(info) ~= "table" or not Public(info.isCommodity)
        or type(info.isCommodity) ~= "boolean" then return nil end
    if not deal.itemKey and info.isCommodity ~= true then
        key = { itemID = key.itemID, itemLevel = 0, itemSuffix = 0,
            battlePetSpeciesID = key.battlePetSpeciesID or 0 }
    end
    return key, info.isCommodity == true, Identity(key)
end

local function CancelTimer()
    if timer then timer:Cancel(); timer = nil end
end

function listings.Enabled() return saved and saved.prepareListings ~= false or false end
function listings.OneClick() return saved and saved.oneClickPrepared ~= false or false end
function listings.SetEnabled(enabled)
    if not saved then return end
    saved.prepareListings = enabled == true
    if not enabled then CancelTimer(); pending = nil end
end
function listings.SetOneClick(enabled)
    if saved then saved.oneClickPrepared = enabled == true end
end

function listings.Initialize(database, callback)
    saved, changed = nil, callback
    if type(database) ~= "table" or database.version ~= 1 then return end
    saved = database
    if saved.prepareListings == nil then saved.prepareListings = true end
    if saved.oneClickPrepared == nil then saved.oneClickPrepared = true end
end

function listings.SetActive(enabled)
    active = enabled == true
    for _, event in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }) do
        if active then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
    end
    if not active then
        CancelTimer()
        running, targets, bought, pending = false, nil, nil, nil
        records, tried = {}, {}
    end
end

function listings.Remember(key, deal)
    local identity = Identity(key)
    if not active or not identity or not deal or not deal.auctionID then return end
    records[identity] = { at = GetTimePreciseSec(), quote = deal }
    Trim(records)
end

function listings.Has(deal)
    if not listings.Enabled() then return false end
    local _, commodity, identity = listings.Key(deal)
    local record = identity and records[identity]
    return not commodity and record and GetTimePreciseSec() - record.at < FRESH
        and record.quote.cost == deal.cost and record.quote.link == deal.link or false
end

function listings.TakePending(deal)
    local _, commodity, identity = listings.Key(deal)
    if commodity or not pending or pending.identity ~= identity or not pending.sent then return false end
    local arrived = pending.reading == true
    CancelTimer()
    pending = nil
    return true, arrived
end

function listings.Current(key, quote)
    -- Try the recorded position first. Native book changes may move it, so an
    -- index is only a hint: the auction ID and all values are still rechecked.
    local function At(index)
        local info = C_AuctionHouse.GetItemSearchResultInfo(key, index)
        if Public(info) and type(info) == "table" and Public(info.auctionID) and info.auctionID == quote.auctionID then
            local deal = addon.LiveDeal(info)
            if deal then deal.resultIndex = index end
            return true, deal
        end
    end
    if Integer(quote.resultIndex, 1) then
        local found, current = At(quote.resultIndex)
        if found then return current, current and "present" or "listing_unavailable" end
    end
    local count = C_AuctionHouse.GetNumItemSearchResults(key)
    if not Integer(count, 0) then return nil, "native_book_unavailable" end
    if count == 0 then return nil, "empty_native_book" end
    for i = 1, count do
        if i ~= quote.resultIndex then
            local found, current = At(i)
            if found then return current, current and "present" or "listing_unavailable" end
        end
    end
    return nil, "auction_missing"
end

function listings.Quote(deal, purchased)
    local key, commodity, identity = listings.Key(deal)
    local record = identity and records[identity]
    local age = record and GetTimePreciseSec() - record.at
    local reason = commodity and "commodity" or not record and "not_prepared"
        or age >= FRESH and "expired" or (record.quote.cost ~= deal.cost or record.quote.link ~= deal.link) and "display_changed"
    if reason then
        addon.Diagnostics.Log("prepared_lookup", { item = deal.itemID, result = reason, age_ms = age and math.floor(age * 1000 + 0.5) })
        return nil
    end
    local quote = record.quote
    local current, unavailable
    if not purchased[quote.auctionID] then current, unavailable = listings.Current(key, quote) end
    if addon.SameListing(quote, current) then
        addon.Diagnostics.Log("prepared_lookup", { item = deal.itemID, result = "hit", auction = quote.auctionID })
        current.available, current.availablePartial = quote.available, quote.availablePartial
        return current, key
    end
    addon.Diagnostics.Log("prepared_lookup", { item = deal.itemID,
        result = purchased[quote.auctionID] and "purchased" or current and "value_changed" or unavailable })
    records[identity] = nil
end

local Pump
local function Finish(work, quote, missing)
    if pending ~= work then return end
    CancelTimer()
    pending = nil
    if quote then
        local full = C_AuctionHouse.HasFullItemSearchResults(work.key)
        quote.availablePartial = not Public(full) or full ~= true
        records[work.identity] = { at = GetTimePreciseSec(), quote = quote }
        Trim(records)
    end
    addon.Diagnostics.Log("listing_prepared", { item = work.candidate.itemID,
        ready = quote ~= nil, missing_vendor = missing or 0,
        elapsed_ms = math.floor((GetTimePreciseSec() - work.startedAt) * 1000 + 0.5) })
    if active and running then
        timer = C_Timer.NewTimer(0, function() timer = nil; Pump() end)
    end
    if changed then changed(work.candidate, quote) end
end

local function Read(work)
    if pending ~= work or work.reading then return end
    CancelTimer()
    work.reading = true
    local index, total, best, missing, cache, amounts, seen = 1, C_AuctionHouse.GetNumItemSearchResults(work.key), nil, 0, {}, {}, {}
    if not Integer(total, 0) then Finish(work); return end
    local function Batch()
        if not active or pending ~= work then return end
        if not running then Finish(work); return end
        if GetTimePreciseSec() >= work.deadline then Finish(work); return end
        local started = GetTimePreciseSec()
        for i = index, math.min(index + 199, total) do
            local info = C_AuctionHouse.GetItemSearchResultInfo(work.key, i)
            local deal, unavailable = addon.LiveDeal(info, cache)
            if deal and not (bought and bought[deal.auctionID]) and not seen[deal.auctionID] then
                deal.resultIndex = i
                seen[deal.auctionID] = true
                local byPrice = amounts[deal.link]
                if not byPrice then byPrice = {}; amounts[deal.link] = byPrice end
                byPrice[deal.cost] = (byPrice[deal.cost] or 0) + deal.available
                if deal.cost <= GetMoney() and (not best or deal.profit > best.profit
                    or (deal.profit == best.profit and (deal.cost < best.cost
                    or (deal.cost == best.cost and deal.link < best.link)))) then best = deal end
            elseif unavailable then missing = missing + 1 end
            index = i + 1
            if GetTimePreciseSec() - started >= 0.004 then break end
        end
        if index <= total then timer = C_Timer.NewTimer(0, Batch)
        elseif work.changed then
            work.reading, work.changed = false, nil
            timer = C_Timer.NewTimer(0, function() timer = nil; Read(work) end)
        else
            if best then best.available = amounts[best.link][best.cost] end
            Finish(work, best, missing)
        end
    end
    Batch()
end

Pump = function()
    if not active or not running or not listings.Enabled() or pending or dispatching or timer or not targets then return end
    local money, now, considered = GetMoney(), GetTimePreciseSec(), 0
    for _, candidate in ipairs(targets) do
        if Number(candidate.cost) and candidate.cost <= money then
            local key, commodity, identity = listings.Key(candidate)
            if key and not commodity then
                considered = considered + 1
                local record = records[identity]
                if (not record or now - record.at >= FRESH) and (not tried[identity] or now - tried[identity] >= RETRY) then
                    local wait = addon.QueryPace.Wait(true)
                    if wait ~= 0 then
                        if wait then addon.QueryPace.Schedule(wait) end
                        return
                    end
                    -- Metadata is checked here, immediately before dispatch,
                    -- rather than assuming a key stayed loaded while queued.
                    local work = { key = key, identity = identity, candidate = candidate, startedAt = now, deadline = now + 5, sent = true }
                    pending, tried[identity] = work, now
                    Trim(tried)
                    timer = C_Timer.NewTimer(5, function() Finish(work) end)
                    addon.QueryPace.NoteSearch()
                    addon.Diagnostics.Log("listing_prepare_sent", { item = candidate.itemID })
                    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }
                    dispatching = true
                    if candidate.itemKey then C_AuctionHouse.SendSearchQuery(key, sorts, true)
                    else C_AuctionHouse.SendSellSearchQuery(key, sorts, true) end
                    dispatching = false
                    return
                end
                if considered >= LIMIT then return end
            end
        end
    end
end

function listings.Update(list, canRun, purchased)
    running, targets, bought = canRun == true, canRun and list or nil, purchased
    if not running and not pending then CancelTimer() end
    Pump()
end

function listings.Wake() Pump() end

frame:SetScript("OnEvent", function(_, _, key)
    local identity = Identity(key)
    if not identity then return end
    if pending and pending.identity == identity then
        if pending.reading then pending.changed = true else Read(pending) end
    end
end)
