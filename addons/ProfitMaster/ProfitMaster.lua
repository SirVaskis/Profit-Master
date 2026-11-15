local addonName, addon = ...
local events = CreateFrame("Frame")
local window, tabLibrary
local TAB_ID = "ProfitMaster"
local BUY_DIALOG = "PROFITMASTER_CONFIRM_BUY"
local COMMODITY_DIALOG = "PROFITMASTER_CONFIRM_COMMODITY"
local candidates = {}
local page = 1
local houseOpen, connected, scanBusy = false, false, false
local auctionListener, auctionSubscriptions
local HOUSE_EVENTS = { "REPLICATE_ITEM_LIST_UPDATE", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_SHOW_ERROR", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }
local selectedKey, pendingPurchase, timer, onItemData
local quote, selectedCandidate, verifying, quoteDialog
local pendingDeal, recheck, batchBuy
local pendingError
local queuedSearch
local selectedCommodity, commodityPurchase, commodityRead, commodityDeadline, itemRead
local scanWork
local replicateGeneration = 0
local excluded, liveValued = {}, {}
local purchased = {}
local message = "Run a scan, then click Buy to verify and confirm one auction."
local progressValue, progressText = 0, "Ready to scan"
local scanStartedAt, lastScanAt
local scanLabel = "Auctionator full scan"
local scanCoverage
local attempt, attemptStarted = 0, nil
local priceCheckStarted, priceCheckSent, priceCheckReceived
local ROWS = 8
local SCAN_PUBLISH_INTERVAL = 0.25
local Refresh, PreparePurchase, Buy, ProcessScan, ReadStock, ReadCommodityLive, BuyCommodity, TryQueuedSearch
local ReadLive, RequestMoreResults, UpdateQuote
local COMMODITY_EVENTS = { "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }

local function Trace(event, fields)
    if not addon.Diagnostics.Enabled() then return end
    fields = fields or {}
    local deal = commodityPurchase and commodityPurchase.deal or quote or pendingDeal or selectedCandidate
    fields.attempt = attempt
    fields.item = fields.item or (selectedKey and selectedKey.itemID)
    fields.phase = commodityPurchase and commodityPurchase.phase or (queuedSearch and "queued_search") or (pendingError and "uncertain")
        or (pendingPurchase and "purchase") or (recheck and "stock")
        or (verifying and "search") or (quote and "preview") or "idle"
    if deal then
        fields.expected_unit, fields.vendor, fields.available = deal.cost, deal.vendor, deal.available
        fields.strategy, fields.de_net = deal.disenchant and "disenchant" or "vendor", deal.deNet
        fields.auction = deal.auctionID
        fields.gold = GetMoney()
        fields.throttle_ready = C_AuctionHouse.IsThrottledMessageSystemReady()
        fields.combat = InCombatLockdown and InCombatLockdown() or false
    end
    if commodityPurchase then fields.quantity, fields.expected_total = commodityPurchase.quantity, commodityPurchase.total end
    if attemptStarted and deal then fields.elapsed_ms = math.floor((GetTime() - attemptStarted) * 1000 + 0.5) end
    addon.Diagnostics.Log(event, fields)
end

local function StampPriceCheck(state)
    local profile = addon.LastPriceCheck
    if not profile or profile.attempt ~= attempt or profile.state == "preview" or profile.state == "ended" then return end
    local now = GetTimePreciseSec()
    if state == "sent" then priceCheckSent = now end
    if state == "results" and not priceCheckReceived then priceCheckReceived = now end
    local function Milliseconds(seconds) return math.max(0, math.floor(seconds * 1000 + 0.5)) end
    profile.state, profile.total_ms = state, Milliseconds(now - priceCheckStarted)
    profile.queue_ms = Milliseconds((priceCheckSent or now) - priceCheckStarted)
    if priceCheckSent and priceCheckReceived then profile.reply_ms = Milliseconds(priceCheckReceived - priceCheckSent) end
    if state == "preview" and priceCheckReceived then
        profile.results_to_preview_ms = Milliseconds(now - priceCheckReceived)
    end
    if state == "preview" or state == "ended" then addon.Diagnostics.Log("price_check_timing", profile) end
end

local function StopTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

local function ActiveScanClock(work)
    local now = GetTimePreciseSec()
    return now - (work.pausedSeconds or 0) - (work.profilePauseAt and (now - work.profilePauseAt) or 0)
end

local function StopScanWork(outcome)
    if scanWork and not scanWork.paused then StopTimer() end
    if scanWork then
        if scanWork.SaveProfile then scanWork.SaveProfile(outcome or "cancelled") end
        addon.History.Abort(scanWork.historyScan)
        addon.History.Abort(scanWork.meanScan)
    end
    scanWork, onItemData = nil, nil
    events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function PauseScanWork()
    if addon.BrowseScanner then addon.BrowseScanner.Pause() end
    if scanWork and not scanWork.paused then
        scanWork.paused = true
        scanWork.pausedAt = time()
        scanWork.profilePauseAt = GetTimePreciseSec()
        StopTimer()
    end
end

local function Status(text)
    Trace("status", { text = text })
    message = text
    if window then
        window.status:SetText(text)
    end
end

local function ScanProgress(value, text)
    if window and window.progress then
        if value ~= progressValue then window.progress:SetValue(value) end
        if text ~= progressText then window.progress.text:SetText(text) end
    end
    progressValue, progressText = value, text
end

local function ClearLive(keepScanPaused)
    StampPriceCheck("ended")
    StopTimer()
    if not scanWork then
        onItemData = nil
        events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    events:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    events:UnregisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    events:UnregisterEvent("UI_ERROR_MESSAGE")
    for _, event in ipairs(COMMODITY_EVENTS) do events:UnregisterEvent(event) end
    local cancelCommodity = commodityPurchase ~= nil
    selectedCommodity, commodityPurchase, commodityRead, commodityDeadline, itemRead = false, nil, nil, nil, nil
    selectedKey, pendingPurchase = nil, nil
    quote, selectedCandidate, verifying, quoteDialog = nil, nil, false, nil
    pendingDeal, recheck, batchBuy, pendingError, queuedSearch = nil, nil, nil, nil, nil
    StaticPopup_Hide(BUY_DIALOG)
    StaticPopup_Hide(COMMODITY_DIALOG)
    if cancelCommodity then C_AuctionHouse.CancelCommoditiesPurchase() end
    if scanWork and scanWork.paused and not keepScanPaused then
        local work = scanWork
        if work.extendDeadline then work.extendDeadline(time() - work.pausedAt) end
        work.pausedSeconds = (work.pausedSeconds or 0) + GetTimePreciseSec() - work.profilePauseAt
        work.profilePauseAt = nil
        work.pausedAt = nil
        work.paused = false
        timer = C_Timer.NewTimer(0, function()
            if scanWork == work then work.resume() end
        end)
    end
    if not keepScanPaused and addon.BrowseScanner then addon.BrowseScanner.Resume() end
end

local function RemoveCandidate()
    local removed = false
    if selectedCandidate then
        excluded[selectedCandidate.itemID] = true
        for index, deal in ipairs(candidates) do
            if deal == selectedCandidate then
                table.remove(candidates, index)
                removed = true
                ScanProgress(progressValue, #candidates .. " candidates remain - item removed")
                break
            end
        end
    end
    return removed
end

local function CancelPurchase(text, removeCandidate)
    local removed = removeCandidate and RemoveCandidate() or false
    if removed then text = text .. " Item removed from this scan; other results kept." end
    Trace("attempt_end", { removed = removed, reason = text, candidates = #candidates })
    ClearLive()
    Status(text)
    if Refresh then Refresh() end
end

local function AwaitPurchaseOutcome()
    if pendingError then return end
    pendingError, batchBuy = true, nil
    local removed = RemoveCandidate()
    Trace("purchase_uncertain", { removed = removed, error = "DatabaseError" })
    Status("Internal auction error; purchase outcome uncertain. Item removed from this scan. Waiting for confirmation; do not retry. Check mail/gold.")
    Refresh()
end

local function OfferMoreListings(text)
    StopTimer()
    Status(text .. " Use More listings within 15s, or select another item.")
    timer = C_Timer.NewTimer(15, function()
        timer = nil
        CancelPurchase("Price check ended without a purchase. Results kept; discovery resumed.")
    end)
end

local function ProviderBusy()
    local state = Auctionator and Auctionator.State or {}
    return (state.FullScanFrameRef and state.FullScanFrameRef.inProgress)
        or (state.IncrementalScanFrameRef and state.IncrementalScanFrameRef.doingFullScan)
end

local function IsBusy()
    return scanBusy or ProviderBusy()
end

local function ExternalBrowseBusy()
    local state = Auctionator and Auctionator.State
    local frame = state and state.IncrementalScanFrameRef
    return frame and frame.doingFullScan
end

local function CandidateStatus()
    local age = lastScanAt and math.max(0, time() - lastScanAt) or 0
    return #candidates .. " candidates; scan " .. age .. "s old. "
        .. (scanCoverage or "Buy verifies the current price before confirmation.")
end

local function SameKey(a, b)
    return a and b and a.itemID == b.itemID
        and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0)
        and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end

local function PurchaseReady()
    return connected and houseOpen and AuctionHouseFrame and AuctionHouseFrame:IsShown()
        and not ExternalBrowseBusy()
        and not (InCombatLockdown and InCombatLockdown())
end

local function Ready()
    return PurchaseReady() and C_AuctionHouse.IsThrottledMessageSystemReady()
end

local function RecheckTimedOut()
    CancelPurchase("Purchase confirmed. Stock recheck timed out; unable to verify. Item kept.")
end

local function TryRecheck()
    if not recheck or (recheck.request ~= "refresh" and recheck.request ~= "more"
        and recheck.request ~= "cached") then return end
    if time() >= recheck.deadline then RecheckTimedOut(); return end
    local request = recheck.request
    -- Cached getters need no query slot. Prepare the next verified quote while
    -- the search channel is busy; the purchase still needs its own click.
    if request ~= "cached" and not Ready() then return end
    recheck.request = nil
    Trace("stock_request", { request = request, commodity = selectedCommodity, deadline = recheck.deadline })
    if request == "cached" then
        ReadStock()
    elseif request == "refresh" then
        if selectedCommodity then C_AuctionHouse.RefreshCommoditySearchResults(selectedKey.itemID)
        else C_AuctionHouse.RefreshItemSearchResults(selectedKey) end
    else
        RequestMoreResults()
    end
end

local function QueueRecheck(request)
    StopTimer()
    local state = recheck
    state.request = "queued"
    -- Leave the purchase/event callback before sending another read request.
    -- Pagination shares the original deadline, rather than extending it.
    timer = C_Timer.NewTimer(0, function()
        if time() >= state.deadline then RecheckTimedOut(); return end
        state.request = request
        timer = C_Timer.NewTimer(state.deadline - time(), RecheckTimedOut)
        TryRecheck()
    end)
end

local function Button(parent, text, width, action)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", action)
    return button
end

local function Label(parent, x, y, width, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function StartBrowse(keys)
    addon.Disenchant.ResetCache()
    scanStartedAt, scanLabel = time(), keys and "Profit Master Quick scan" or "Profit Master browse scan"
    Trace("scan_start", { source = keys and "quick" or "profitmaster_browse", keys = keys and #keys })
    local work = ProcessScan({}, true, true, keys)
    work.ownedBrowse, work.latestRows = true, {}
    local onRows = function(rows)
        if scanWork ~= work then return end
        work.latestRows = rows
        work.Feed(rows)
        if not work.paused then
            ScanProgress(0, "Received " .. #rows .. " rows - Buy pauses discovery")
        end
    end
    local onComplete = function(rows)
        if scanWork == work then work.Complete(rows) end
    end
    local onFailed = function(reason)
        if scanWork ~= work then return end
        StopScanWork(reason == "Auction House closed." and "cancelled" or "failed")
        scanBusy = false
        ScanProgress(0, "Browse scan stopped - partial results kept")
        if not (pendingPurchase or verifying or quote) then
            Status(reason .. " Partial results kept; Buy still verifies each offer.")
        end
        if queuedSearch and reason ~= "Auction House closed." then TryQueuedSearch() end
        Refresh()
    end
    local started
    if keys then started = addon.BrowseScanner.StartKeys(keys, onRows, onComplete, onFailed)
    else started = addon.BrowseScanner.Start(onRows, onComplete, onFailed) end
    if not started then
        StopScanWork("failed")
        scanBusy = false
        Status("Auction House is not ready to start browsing. Try Scan again when ready.")
    end
end

local function StartQuickScan()
    if recheck then ClearLive() end
    if not houseOpen or pendingPurchase or verifying or quote or IsBusy() then return end
    local keys = addon.History.QuickKeys()
    if #keys == 0 then
        Status("Run a full scan first to learn profitable items for Quick scan.")
        return
    end
    StartBrowse(keys)
    Refresh()
end

local function StartScan()
    if recheck then ClearLive() end
    if not houseOpen or pendingPurchase or verifying or quote then
        return
    end
    if IsBusy() then
        ScanProgress(progressValue, "Auctionator scan already in progress...")
        Status("Auctionator is scanning. Wait for it to finish.")
        return
    end
    local state = Auctionator.State
    local full, browse = state.FullScanFrameRef, state.IncrementalScanFrameRef
    local fullReady = full and full.CanInitiate and full:CanInitiate()
    local scan
    if fullReady then scan = full
    elseif browse and browse.InitiateScan then scan = browse end
    if not connected then
        ScanProgress(progressValue, "Auctionator full scanner unavailable")
        Status("Auctionator's full scanner is unavailable. Open its Auctionator tab first.")
    elseif not scan then
        if lastScanAt then
            ClearLive()
            page = 1
            ScanProgress(1, "Using previous scan - live prices must be checked")
            Status(CandidateStatus())
        else
            ScanProgress(progressValue, "Scanner unavailable or full scan on cooldown")
            Status("Open Auctionator's tab to initialize its browse scanner, then try again.")
        end
    else
        if scan == browse and addon.BrowseScanner and not C_AuctionHouse.IsThrottledMessageSystemReady() then
            Status("Auction House is not ready for another browse query. Existing results kept; try Scan again shortly.")
            Refresh()
            return
        end
        ClearLive()
        page = 1
        if scan == browse and addon.BrowseScanner then
            StartBrowse()
        else
            ScanProgress(0, "Starting Auctionator scan...")
            scan:InitiateScan()
        end
    end
    Refresh()
end

local function ShowQuote(deal)
    quote = deal
    if not deal.isCommodity then addon.Listings.Remember(selectedKey, deal) end
    events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    events:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    Trace("preview", { commodity = deal.isCommodity or false })
    if deal.isCommodity then
        Status("Choose a quantity, then Buy quantity once. A changed server quote cancels the purchase.")
        if not StaticPopup_Show(COMMODITY_DIALOG, deal.link, nil, deal) then
            CancelPurchase("Purchase confirmation could not open. Results kept.")
        else StampPriceCheck("preview") end
        return
    end
    Status(not PurchaseReady() and "Price verified. Waiting for the Auction House before confirmation."
        or batchBuy and ("Buy 1 is ready; " .. batchBuy.remaining .. " left in your goal at this price.")
        or (deal.disenchant and "Buy 1 is ready. DE goal defaults to half the known same-price stock, capped by your gold."
            or "Buy 1 is ready. Goal defaults to all verified affordable stock; each click buys one auction."))
    if not StaticPopup_Show(BUY_DIALOG, deal.link, nil, deal) then
        CancelPurchase("Purchase confirmation could not open. Results kept; click Buy again.")
    else StampPriceCheck("preview") end
end

ReadStock = function()
    if selectedCommodity then ReadCommodityLive(); return end
    local state = recheck
    if not state then return end
    StopTimer()
    state.request, state.changed = "processing", false
    local index, total = 1, C_AuctionHouse.GetNumItemSearchResults(selectedKey)
    local available, matching, missing, seen, itemCache = 0, nil, 0, {}, {}
    local function CheckBatch()
        if recheck ~= state then return end
        timer = nil
        if time() >= state.deadline then RecheckTimedOut(); return end
        local started = GetTimePreciseSec()
        for i = index, math.min(index + 199, total) do
            local info = C_AuctionHouse.GetItemSearchResultInfo(selectedKey, i)
            local restricted = issecretvalue and (issecretvalue(info) or (info and
                (issecretvalue(info.itemLink) or issecretvalue(info.buyoutAmount) or issecretvalue(info.quantity)
                or issecretvalue(info.auctionID) or issecretvalue(info.containsOwnerItem) or issecretvalue(info.containsAccountItem))))
            if restricted then
                missing = missing + 1
            elseif info and info.itemLink == state.deal.link and info.buyoutAmount == state.deal.cost then
                local deal, unavailable = addon.LiveDeal(info, itemCache)
                if deal and not purchased[deal.auctionID] and not seen[deal.auctionID] then
                    deal.resultIndex = i
                    available, matching = available + deal.available, deal
                    seen[deal.auctionID] = true
                elseif unavailable then missing = missing + 1 end
            end
            index = i + 1
            if GetTimePreciseSec() - started >= 0.004 then break end
        end
        if index <= total then
            timer = C_Timer.NewTimer(0, CheckBatch)
            return
        elseif state.changed then
            state.request = nil
            timer = C_Timer.NewTimer(0, ReadStock)
            return
        end
        state.request = nil
        local full = C_AuctionHouse.HasFullItemSearchResults(selectedKey)
        Trace("stock_result", { full = full, quantity = available, missing = missing, cached = state.cached or false })
        if matching then
            liveValued[selectedCandidate.itemID] = true
            selectedCandidate.available, selectedCandidate.availablePartial = available, not full
            selectedCandidate.cost, selectedCandidate.vendor, selectedCandidate.profit = matching.cost, matching.vendor, matching.profit
            selectedCandidate.disenchant, selectedCandidate.deNet, selectedCandidate.deGross = matching.disenchant, matching.deNet, matching.deGross
            selectedCandidate.link, selectedCandidate.display = matching.link, matching.link
            addon.SortDeals(candidates)
            matching.available, matching.availablePartial = available, not full
            addon.Listings.Remember(selectedKey, matching)
            if batchBuy and batchBuy.remaining > 0 and GetMoney() >= matching.cost then
                StopTimer()
                recheck, verifying = nil, false
                ShowQuote(matching)
                Refresh()
            else
                local stopped = batchBuy and batchBuy.remaining > 0
                    and " Quantity goal stopped: not enough gold for the next copy." or ""
                CancelPurchase("Purchase confirmed. " .. (full and "" or "At least ") .. available
                    .. " available at " .. GetMoneyString(matching.cost) .. "; item kept." .. stopped)
            end
        elseif state.cached then
            -- No unpurchased ID in the client's current results. Ask the server
            -- before deciding that stock is exhausted; grouped rows may rotate IDs.
            -- The cached pass already left the purchase callback; refresh now
            -- rather than adding another timer/frame before the server request.
            state.cached, state.request = nil, "refresh"
            timer = C_Timer.NewTimer(math.max(0, state.deadline - time()), RecheckTimedOut)
            TryRecheck()
        elseif not full then
            QueueRecheck("more")
        elseif missing > 0 then
            CancelPurchase("Purchase confirmed. Stock data unavailable; unable to verify. Item kept.")
        else
            CancelPurchase("Purchase confirmed. No other eligible auction remains at that price.", true)
        end
    end
    CheckBatch()
end

ReadCommodityLive = function()
    if queuedSearch then return end
    if not selectedCommodity or not selectedKey or pendingPurchase or quote or not verifying then return end
    if commodityRead then commodityRead.changed = true; return end
    if recheck and recheck.request then return end
    StopTimer()
    local state = { index = 1, total = C_AuctionHouse.GetNumCommoditySearchResults(selectedKey.itemID) }
    commodityRead = state
    local best, missing, cache, seen = nil, false, {}, {}
    local function Batch()
        if commodityRead ~= state then return end
        timer = nil
        if time() >= state.deadline then
            CancelPurchase("Commodity stock check timed out; unable to verify. Item kept.")
            return
        end
        local started = GetTimePreciseSec()
        for i = state.index, math.min(state.index + 199, state.total) do
            local info = C_AuctionHouse.GetCommoditySearchResultInfo(selectedKey.itemID, i)
            local deal, unavailable = addon.CommodityDeal(info, cache)
            missing = missing or unavailable
            local id = info and not (issecretvalue and (issecretvalue(info) or issecretvalue(info.auctionID))) and info.auctionID
            if deal and deal.itemID == selectedKey.itemID and (not id or not seen[id])
                and (not recheck or deal.cost == recheck.deal.cost) then
                if not best or deal.cost < best.cost then best = deal
                elseif deal.cost == best.cost then best.available = best.available + deal.available end
                if id then seen[id] = true end
            end
            state.index = i + 1
            if GetTimePreciseSec() - started >= 0.004 then break end
        end
        if state.index <= state.total then timer = C_Timer.NewTimer(0, Batch); return end
        commodityRead = nil
        if state.changed then timer = C_Timer.NewTimer(0, ReadCommodityLive); return end
        local full = C_AuctionHouse.HasFullCommoditySearchResults(selectedKey.itemID)
        Trace("commodity_book", { full = full, rows = state.total, available_now = best and best.available or 0,
            price_now = best and best.cost, missing = missing or false })
        if recheck then
            if best then
                selectedCandidate.available, selectedCandidate.availablePartial = best.available, not full
                selectedCandidate.cost, selectedCandidate.vendor, selectedCandidate.profit = best.cost, best.vendor, best.profit
                selectedCandidate.link, selectedCandidate.display = best.link, best.link
                liveValued[selectedCandidate.itemID] = true
                addon.SortDeals(candidates)
                CancelPurchase("Commodity purchase confirmed. Same-price stock remains; item kept.")
            elseif not full then QueueRecheck("more")
            elseif missing then CancelPurchase("Commodity purchase confirmed. Vendor data unavailable; item kept.")
            else CancelPurchase("Commodity purchase confirmed. No stock remains at that price.", true) end
        else
            verifying = false
            if best and GetMoney() >= best.cost then
                best.availablePartial = not full
                ShowQuote(best)
            elseif not best and full then
                CancelPurchase("No purchasable commodity offer was verified.", true)
                return
            elseif not full then
                OfferMoreListings("No affordable commodity deal was found in the received results.")
            else
                CancelPurchase("No affordable commodity deal with verified vendor data was found. Results kept.")
                return
            end
            Refresh()
        end
    end
    state.deadline = recheck and recheck.deadline or commodityDeadline
    Batch()
end

ReadLive = function()
    if queuedSearch then return end
    if not selectedKey or pendingPurchase or quote or not verifying then return end
    if recheck then
        if recheck.request == "processing" then recheck.changed = true; return end
        if recheck.request then return end
        ReadStock()
        return
    end
    if itemRead then itemRead.changed = true; return end
    StopTimer()
    local count = C_AuctionHouse.GetNumItemSearchResults(selectedKey)
    if (issecretvalue and issecretvalue(count)) or type(count) ~= "number" or count < 0
        or count >= math.huge or count ~= math.floor(count) then
        CancelPurchase("Item results are unavailable. Results kept; no purchase sent.")
        return
    end
    local state = { key = selectedKey, index = 1, total = count, deadline = commodityDeadline,
        money = GetMoney(), batches = 0, cpu = 0 }
    itemRead = state
    local best, eligible, missingVendor, minimum = nil, 0, 0, nil
    local itemCache, amounts, seen = {}, {}, {}
    local function Batch()
        if itemRead ~= state then return end
        timer = nil
        if time() >= state.deadline then
            CancelPurchase("Item price check timed out while reading results. Results kept; no purchase sent.")
            return
        end
        local started = GetTimePreciseSec()
        state.batches = state.batches + 1
        -- Time is the primary limit. A generous row cap avoids spreading cheap
        -- cached reads across dozens of frames just to satisfy a tiny batch size.
        for i = state.index, math.min(state.index + 9999, state.total) do
            local info = C_AuctionHouse.GetItemSearchResultInfo(state.key, i)
            if not (issecretvalue and issecretvalue(info)) and type(info) == "table" then
                local amount = info.buyoutAmount
                if not (issecretvalue and issecretvalue(amount)) and type(amount) == "number"
                    and amount > 0 and amount < math.huge then minimum = math.min(minimum or amount, amount) end
            end
            local deal, missing = addon.LiveDeal(info, itemCache)
            if deal and not purchased[deal.auctionID] and not seen[deal.auctionID] then
                deal.resultIndex = i
                seen[deal.auctionID], eligible = true, eligible + 1
                local byPrice = amounts[deal.link]
                if not byPrice then byPrice = {}; amounts[deal.link] = byPrice end
                byPrice[deal.cost] = (byPrice[deal.cost] or 0) + deal.available
                if deal.cost <= state.money and (not best or deal.profit > best.profit
                    or (deal.profit == best.profit and (deal.cost < best.cost
                    or (deal.cost == best.cost and deal.link < best.link)))) then best = deal end
            elseif missing then missingVendor = missingVendor + 1 end
            state.index = i + 1
            if GetTimePreciseSec() - started >= 0.004 then break end
        end
        state.cpu = state.cpu + GetTimePreciseSec() - started
        if state.index <= state.total then timer = C_Timer.NewTimer(0, Batch); return end
        itemRead = nil
        -- A changed book or budget must be evaluated as a single fresh pass,
        -- without sending a new search or extending the original deadline.
        if state.changed or state.money ~= GetMoney() then
            timer = C_Timer.NewTimer(0, ReadLive)
            return
        end
        local full = C_AuctionHouse.HasFullItemSearchResults(state.key)
        if (issecretvalue and issecretvalue(full)) or type(full) ~= "boolean" then
            CancelPurchase("Item result coverage is unavailable. Results kept; no purchase sent.")
            return
        end
        verifying = false
        local coverage = full and "" or " More listings available."
        Trace("item_book", { rows = count, eligible = eligible, missing_vendor = missingVendor, full = full,
            minimum_buyout = minimum, batches = state.batches, cpu_ms = math.floor(state.cpu * 1000 + 0.5) })
        if best then
            best.available, best.availablePartial = amounts[best.link][best.cost], not full
            ShowQuote(best)
        elseif missingVendor > 0 then
            CancelPurchase("Exact vendor data is missing for " .. missingVendor .. " live listings. Results kept; try Buy again shortly." .. coverage)
            return
        elseif eligible == 0 then
            if full then CancelPurchase("No purchasable auction was returned for this item.", true); return end
            OfferMoreListings("No profitable auction found for this item. Results kept." .. coverage)
        else
            CancelPurchase("No affordable profitable auction found. Results kept." .. coverage)
            return
        end
        Refresh()
    end
    Batch()
end

RequestMoreResults = function()
    local key, candidate, state, commodity = selectedKey, selectedCandidate, recheck, selectedCommodity
    local function Current()
        return selectedKey == key and selectedCandidate == candidate and recheck == state
            and selectedCommodity == commodity and verifying and not pendingPurchase and not quote
            and not commodityRead and not itemRead and (not state or not state.request)
    end
    local function PublicTrue(value)
        return not (issecretvalue and issecretvalue(value)) and value == true
    end
    local function Full()
        if commodity then return C_AuctionHouse.HasFullCommoditySearchResults(key.itemID) end
        return C_AuctionHouse.HasFullItemSearchResults(key)
    end
    if not Current() then return end
    local full = Full()
    if not PublicTrue(full) then
        if commodity then full = C_AuctionHouse.RequestMoreCommoditySearchResults(key.itemID)
        else full = C_AuctionHouse.RequestMoreItemSearchResults(key) end
    end
    -- Full results may already be cached, with no later update event. Native
    -- calls can also complete synchronously and replace this purchase state.
    if Current() and (PublicTrue(full) or PublicTrue(Full())) then
        if commodity then ReadCommodityLive() else ReadLive() end
    end
end

TryQueuedSearch = function()
    if not queuedSearch or not Ready() then return end
    local wait = addon.QueryPace.Wait(false)
    if wait ~= 0 then
        if wait then addon.QueryPace.Schedule(wait) end
        return
    end
    -- Missing key metadata can silently discard a native search. Check again
    -- at dispatch, since the request may have waited behind another scanner.
    local info = C_AuctionHouse.GetItemKeyInfo(selectedKey)
    if (issecretvalue and issecretvalue(info)) or type(info) ~= "table"
        or (issecretvalue and issecretvalue(info.isCommodity)) or type(info.isCommodity) ~= "boolean"
        or info.isCommodity ~= selectedCommodity then
        Trace("search_metadata_unavailable")
        CancelPurchase("Item search data became unavailable. No purchase sent; try Buy again shortly.")
        return
    end
    queuedSearch = nil
    StopTimer()
    commodityDeadline = time() + 15
    timer = C_Timer.NewTimer(15, function()
        timer = nil
        CancelPurchase("Price verification timed out. Results kept; click Buy to try again.")
    end)
    Status("Verifying live price for " .. selectedCandidate.name .. " before purchase...")
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }
    StampPriceCheck("sent")
    addon.QueryPace.NoteSearch()
    Trace("search_sent", { commodity = selectedCommodity, level = selectedKey.itemLevel, suffix = selectedKey.itemSuffix })
    if selectedCommodity then C_AuctionHouse.SendSearchQuery(selectedKey, {}, false)
    elseif selectedCandidate.itemKey then C_AuctionHouse.SendSearchQuery(selectedKey, sorts, true)
    else C_AuctionHouse.SendSellSearchQuery(selectedKey, sorts, true) end
    Refresh()
end

PreparePurchase = function(deal)
    if not houseOpen or not AuctionHouseFrame or not AuctionHouseFrame:IsShown()
        or (InCombatLockdown and InCombatLockdown()) or pendingPurchase or (verifying and not recheck) or quote then
        Trace("search_denied", { requested_item = deal.itemID, provider_busy = ProviderBusy() or false,
            throttle_ready = C_AuctionHouse.IsThrottledMessageSystemReady() })
        Status("Auction House is busy, closed, or in combat. Results kept; try Buy again when ready.")
        return
    end
    addon.Disenchant.ResetCache()
    local key, commodity = addon.Listings.Key(deal)
    if not key then
        Status("Item search data is unavailable. Results kept; try Buy again shortly.")
        return
    end
    PauseScanWork()
    addon.Listings.Update(nil, false, purchased)
    ClearLive(true)
    selectedKey, selectedCandidate, verifying = key, deal, true
    attempt, attemptStarted = attempt + 1, GetTime()
    priceCheckStarted, priceCheckSent, priceCheckReceived = GetTimePreciseSec(), nil, nil
    addon.LastPriceCheck = { item = deal.itemID, attempt = attempt, state = "queued", queue_ms = 0, total_ms = 0 }
    selectedCommodity = commodity
    commodityDeadline = time() + 15
    if selectedCommodity then selectedCandidate.isCommodity = true end
    if addon.Listings.Enabled() and not selectedCommodity and not ExternalBrowseBusy() then
        local prepared = addon.Listings.Quote(deal, purchased)
        if prepared then
            verifying = false
            StampPriceCheck("sent")
            StampPriceCheck("results")
            Trace("prepared_listing", { auction = prepared.auctionID, one_click = addon.Listings.OneClick() })
            ShowQuote(prepared)
            if quote == prepared and addon.Listings.OneClick() then
                local limit = math.min(prepared.available, math.floor(GetMoney() / prepared.cost))
                local goal = prepared.disenchant and math.min(limit, math.max(1, math.floor(prepared.available / 2))) or limit
                Buy(prepared, goal)
                if pendingPurchase then StaticPopup_Hide(BUY_DIALOG) end
            end
            Refresh()
            return
        end
        local inFlight, arrived = addon.Listings.TakePending(deal)
        if inFlight then
            -- Join the already dispatched search instead of sending it twice.
            StampPriceCheck("sent")
            Trace("prepared_search_handoff", { results_ready = arrived })
            Status("Finishing the prepared listing check...")
            timer = C_Timer.NewTimer(15, function()
                timer = nil
                CancelPurchase("Prepared listing check timed out. No purchase sent; results kept.")
            end)
            if arrived then
                StampPriceCheck("results")
                ReadLive()
            end
            Refresh()
            return
        end
    end
    queuedSearch = true
    Status(ExternalBrowseBusy() and "Buy selected. Waiting for the external Auctionator scan to release its search channel."
        or "Buy selected. Discovery paused; waiting for the Auction House search channel.")
    Trace("search_queued", { provider_busy = ProviderBusy() or false })
    events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    timer = C_Timer.NewTimer(30, function()
        timer = nil
        CancelPurchase("Queued price check timed out. No purchase sent; results kept.")
    end)
    TryQueuedSearch()
    Refresh()
end

Buy = function(deal, requested)
    if deal ~= quote then return end
    local limit = math.min(deal.available, math.floor(GetMoney() / deal.cost))
    if limit < 1 then
        CancelPurchase("Not enough gold for the next copy. No purchase sent; item kept.")
        return
    end
    if not requested or requested < 1 or requested ~= math.floor(requested) or requested > limit then
        Status("Enter a whole quantity from 1 to " .. limit .. ". No purchase sent.")
        return true
    end
    -- Native buy buttons accept a verified offer without a search-readiness
    -- test. Keep the context, exact listing and funds checks on this click.
    if not PurchaseReady() or pendingPurchase or not selectedKey then
        if not pendingPurchase and selectedKey and houseOpen and AuctionHouseFrame:IsShown()
            and not (InCombatLockdown and InCombatLockdown()) then
            Status("Waiting for the Auction House. Confirm again when the button is ready; no purchase sent.")
            UpdateQuote()
            return true
        end
        CancelPurchase("Auction House is busy, closed, or in combat. Purchase not sent; results kept.")
        return
    end
    addon.Disenchant.ResetCache()
    local current = addon.Listings.Current(selectedKey, deal)
    if not addon.SameListing(deal, current) then
        CancelPurchase("Listing changed or disappeared. Purchase not sent.", true)
        return
    elseif GetMoney() < deal.cost then
        CancelPurchase("You do not have enough gold for this auction. Purchase not sent; results kept.")
        return
    end

    batchBuy = batchBuy or { bought = 0 }
    batchBuy.remaining = requested
    pendingPurchase, pendingDeal = deal.auctionID, deal
    events:RegisterEvent("UI_ERROR_MESSAGE")
    StopTimer()
    -- Establish cleanup first, so even an interrupted purchase handler cannot
    -- leave the results permanently locked. This timer never retries a bid.
    timer = C_Timer.NewTimer(15, function()
        timer = nil
        CancelPurchase(pendingError and "Purchase outcome remains uncertain. Check mail/gold before buying again."
            or "Purchase not confirmed. Check mail/gold before buying again.", true)
    end)
    -- Only a confirmation or prepared-row hardware click calls this. Keep frames and
    -- results intact before the restricted call, matching Auctionator's ordering.
    Trace("item_buy_sent", { quantity = 1 })
    C_AuctionHouse.PlaceBid(deal.auctionID, deal.cost)
    -- A blocked action/error/success event may have arrived synchronously.
    if not pendingPurchase then return end
    quote = nil
    if pendingError then Refresh(); return end
    Status("Purchase requested; waiting for confirmation. Results kept.")
    Refresh()
end

BuyCommodity = function(deal, requested)
    if quote ~= deal or not selectedCommodity or pendingPurchase then return end
    local limit = math.min(deal.available, math.floor(GetMoney() / deal.cost))
    if limit < 1 then CancelPurchase("Not enough gold for this commodity purchase. Item kept."); return end
    if not requested or requested < 1 or requested ~= math.floor(requested) or requested > limit then
        Status("Enter a whole quantity from 1 to " .. limit .. ". No purchase sent.")
        return true
    end
    if not PurchaseReady() then
        if houseOpen and AuctionHouseFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            Status("Waiting for the Auction House. Confirm again when the button is ready; no purchase sent.")
            UpdateQuote()
            return true
        end
        CancelPurchase("Auction House is busy, closed, or in combat. No purchase sent.")
        return
    end
    local fresh = addon.Deal(deal.link, 1, deal.cost)
    if not fresh or fresh.vendor ~= deal.vendor then
        CancelPurchase("Commodity vendor value changed or is unavailable. No purchase sent.", true)
        return
    end
    local state = { deal = deal, quantity = requested, total = requested * deal.cost,
        phase = "quote", deadline = time() + 15 }
    commodityPurchase = state
    pendingPurchase, pendingDeal, quote = deal.itemID, deal, nil
    for _, event in ipairs(COMMODITY_EVENTS) do events:RegisterEvent(event) end
    events:RegisterEvent("UI_ERROR_MESSAGE")
    StopTimer()
    timer = C_Timer.NewTimer(15, function()
        CancelPurchase("Commodity purchase not confirmed. Check mail/gold before buying again.", true)
    end)
    Status("Requesting a server quote for " .. requested .. " at " .. GetMoneyString(deal.cost) .. " each...")
    -- One explicit Buy quantity click starts one bounded quantity transaction.
    Trace("commodity_quote_requested")
    C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, requested)
    if commodityPurchase == state then Refresh() end
end

local function ConfirmCommodity(unitPrice, totalPrice)
    local state = commodityPurchase
    if not state or state.phase ~= "quote" then return end
    local duration = C_AuctionHouse.GetQuoteDurationRemaining()
    local fresh = addon.Deal(state.deal.link, 1, state.deal.cost)
    local restricted = issecretvalue and (issecretvalue(unitPrice) or issecretvalue(totalPrice) or issecretvalue(duration))
    Trace("commodity_quote_received", { received_unit = unitPrice, received_total = totalPrice, quote_seconds = duration })
    if restricted or type(unitPrice) ~= "number" or type(totalPrice) ~= "number"
        or unitPrice ~= state.deal.cost or totalPrice ~= state.total then
        CancelPurchase("Commodity quote changed or is unavailable. No purchase confirmed.", true)
    elseif type(duration) ~= "number" or duration <= 0 or time() >= state.deadline then
        CancelPurchase("Commodity quote expired. No purchase confirmed.", true)
    elseif not houseOpen or not window:IsShown() or not AuctionHouseFrame:IsShown() or ProviderBusy()
        or (InCombatLockdown and InCombatLockdown()) then
        CancelPurchase("Commodity quote expired or the Auction House is unavailable. Item kept.")
    elseif not fresh or fresh.vendor ~= state.deal.vendor then
        CancelPurchase("Commodity vendor value changed or is unavailable. No purchase confirmed.", true)
    elseif GetMoney() < state.total then
        CancelPurchase("Not enough gold for this commodity quantity. No purchase confirmed; item kept.")
    else
        -- Confirm has no hardware-event restriction in the pinned client API.
        -- Only the exact quantity/unit price/total authorized by that click can
        -- reach this step. There is no retry or follow-up transaction.
        state.phase = "confirming"
        Trace("commodity_confirm_sent")
        Status("Buying " .. state.quantity .. " commodities for " .. GetMoneyString(state.total) .. "; waiting for confirmation...")
        C_AuctionHouse.ConfirmCommoditiesPurchase(state.deal.itemID, state.quantity)
    end
end

local function UpdateItemDialog(editBox, deal)
    if not deal or quote ~= deal or selectedCommodity then return end
    local quantity = tonumber(editBox:GetText())
    local limit = math.min(deal.available, math.floor(GetMoney() / deal.cost))
    local valid = quantity and quantity >= 1 and quantity == math.floor(quantity) and quantity <= limit
    local text = deal.link .. " x1 per click\nAuction ID: " .. deal.auctionID
        .. "\n\nBuyout / item: " .. GetMoneyString(deal.cost)
    if deal.disenchant then
        text = text .. "\nDISENCHANT - do not vendor this item"
            .. (addon.Disenchant.Safe() and "\nCheapest baseline outcome: " or "\nExpected materials: ") .. GetMoneyString(deal.deGross)
            .. "\nEstimated proceeds (15% fee allowance): " .. GetMoneyString(deal.deNet)
            .. "\nEstimated profit / item: " .. GetMoneyString(deal.profit)
            .. (addon.Disenchant.Safe()
                and "\nSAFE DE: minimum baseline yield; saved prices, not guaranteed sales."
                or "\nRandom yields; baseline estimate using saved material prices.")
            .. "\nForever yields unverified. Prices may change."
            .. "\nDeposits/relisting costs excluded. Requires disenchanting."
    else
        text = text .. "\nVendor / item: " .. GetMoneyString(deal.vendor)
            .. "\nProfit / item: " .. GetMoneyString(deal.profit)
    end
    text = text .. "\n\nKnown same-price stock: " .. (deal.availablePartial and ">=" or "") .. deal.available
        .. "\nEach click buys one auction. Every copy needs another confirmation."
    if valid then
        text = text .. "\nSelected remaining goal: " .. quantity
            .. "\nTotal purchase cost: " .. GetMoneyString(quantity * deal.cost)
            .. (deal.disenchant and "\nEstimated total proceeds: " or "\nTotal vendor value: ")
                .. GetMoneyString(quantity * (deal.deNet or deal.vendor))
            .. "\nPotential total profit: " .. GetMoneyString(quantity * deal.profit)
            .. "\nThis click buys 1 for " .. GetMoneyString(deal.cost) .. "."
    elseif limit < 1 then text = text .. "\nNo affordable verified stock remains. No purchase sent."
    else text = text .. "\nEnter a whole quantity from 1 to " .. limit .. ". No purchase sent." end
    if batchBuy then text = text .. "\nAlready bought in this goal: " .. batchBuy.bought end
    local ready = PurchaseReady()
    if not ready then text = text .. "\nWaiting for the Auction House; no purchase sent." end
    local dialog = editBox:GetParent()
    dialog:SetText(text)
    dialog:GetButton1():SetText(not ready and "Waiting..." or valid and quantity > 1 and ("Buy 1 of " .. quantity) or "Buy 1")
    dialog:GetButton1():SetEnabled(valid and ready and true or false)
    if dialog:IsShown() then dialog:Resize() end
end

local function UpdateCommodityDialog(editBox, deal)
    if not deal or quote ~= deal then return end
    local quantity = tonumber(editBox:GetText())
    local limit = math.min(deal.available, math.floor(GetMoney() / deal.cost))
    local valid = quantity and quantity >= 1 and quantity == math.floor(quantity) and quantity <= limit
    local text = deal.link .. "\nCommodity - one purchase for the selected quantity"
        .. "\nPrice / item: " .. GetMoneyString(deal.cost)
        .. "\nVendor / item: " .. GetMoneyString(deal.vendor) .. "\nProfit / item: " .. GetMoneyString(deal.profit)
        .. "\nKnown same-price stock: " .. (deal.availablePartial and ">=" or "") .. deal.available
    if valid then
        text = text .. "\n\nBuy " .. quantity .. " for " .. GetMoneyString(quantity * deal.cost)
            .. "\nTotal vendor value: " .. GetMoneyString(quantity * deal.vendor)
            .. "\nPotential profit: " .. GetMoneyString(quantity * deal.profit)
    else text = text .. "\n\nEnter a whole quantity from 1 to " .. math.max(0, limit) .. "." end
    text = text .. "\nChanged server quotes cancel this purchase."
    local ready = PurchaseReady()
    if not ready then text = text .. "\nWaiting for the Auction House; no purchase sent." end
    local dialog = editBox:GetParent()
    dialog:SetText(text)
    dialog:GetButton1():SetText(not ready and "Waiting..." or valid and ("Buy " .. quantity) or "Buy quantity")
    dialog:GetButton1():SetEnabled(valid and ready and true or false)
    if dialog:IsShown() then dialog:Resize() end
end

UpdateQuote = function()
    if not quote or not quoteDialog or not quoteDialog:IsShown() then return end
    if selectedCommodity then UpdateCommodityDialog(quoteDialog:GetEditBox(), quote)
    else UpdateItemDialog(quoteDialog:GetEditBox(), quote) end
end

StaticPopupDialogs[COMMODITY_DIALOG] = {
    text = "%s", button1 = "Buy quantity", button2 = CANCEL,
    timeout = 30, hideOnEscape = true, hasEditBox = true,
    editBoxWidth = 80, editBoxInstructions = "Quantity to buy", maxLetters = 6,
    OnShow = function(dialog, deal)
        quoteDialog = dialog
        local quantity = math.min(deal.available, math.floor(GetMoney() / deal.cost))
        dialog:GetEditBox():SetText(tostring(quantity))
        dialog:GetEditBox():HighlightText()
        UpdateCommodityDialog(dialog:GetEditBox(), deal)
    end,
    EditBoxOnTextChanged = UpdateCommodityDialog,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    OnAccept = function(dialog, deal)
        if deal ~= quote or not selectedCommodity then return end
        return BuyCommodity(deal, tonumber(dialog:GetEditBox():GetText()))
    end,
    OnHide = function(dialog, deal)
        if quoteDialog == dialog then quoteDialog = nil end
        if deal and quote == deal and not pendingPurchase then CancelPurchase("Commodity purchase canceled. Results kept.") end
    end,
}

StaticPopupDialogs[BUY_DIALOG] = {
    text = "%s",
    button1 = "Buy 1",
    button2 = CANCEL,
    timeout = 30,
    hideOnEscape = true,
    hasEditBox = true,
    editBoxWidth = 80,
    editBoxInstructions = "Quantity goal",
    maxLetters = 6,
    OnShow = function(dialog, deal)
        quoteDialog = dialog
        local limit = math.min(deal.available, math.floor(GetMoney() / deal.cost))
        local goal = batchBuy and batchBuy.remaining
            or (deal.disenchant and math.max(1, math.floor(deal.available / 2)) or limit)
        dialog:GetEditBox():SetText(tostring(math.min(goal, limit)))
        dialog:GetEditBox():HighlightText()
        UpdateItemDialog(dialog:GetEditBox(), deal)
    end,
    OnAccept = function(dialog, deal)
        if deal ~= quote then return end
        return Buy(deal, tonumber(dialog:GetEditBox():GetText()))
    end,
    EditBoxOnTextChanged = UpdateItemDialog,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    OnHide = function(dialog, deal)
        if quoteDialog == dialog then quoteDialog = nil end
        if deal and quote == deal and not pendingPurchase then
            CancelPurchase("Purchase canceled or expired. Results kept.")
        end
    end,
}

-- Only our own controls use these cached display values. Avoid native layout and
-- money formatting work when a scan update leaves the visible rows unchanged.
local function UpdateText(control, text)
    if control.displayedText == text then return end
    control.displayedText = text
    control:SetText(text)
end

local function UpdateMoney(control, amount, color)
    if control.displayedAmount == amount and control.displayedColor == color then return end
    control.displayedAmount, control.displayedColor = amount, color
    local text = GetMoneyString(amount)
    control:SetText(color and (color .. text .. "|r") or text)
end

local function UpdateEnabled(control, enabled)
    enabled = not not enabled
    if control.displayedEnabled == enabled then return end
    control.displayedEnabled = enabled
    control:SetEnabled(enabled)
end

local function KeepVendorDeal(deal)
    if not deal.disenchant then return deal.profit > 0 and deal.profit >= addon.GetMinimumProfit() end
    local profit = deal.vendor - deal.cost
    if profit <= 0 or profit < addon.GetMinimumProfit() then return false end
    deal.profit, deal.disenchant, deal.deNet, deal.deGross = profit, false, nil, nil
    return true
end

function addon.ChangeDebug(enabled)
    addon.Diagnostics.SetEnabled(enabled)
    Trace("debug_context", { ah_open = houseOpen, provider_busy = ProviderBusy() or false,
        scan_busy = scanBusy, candidates = #candidates })
    Refresh()
end

function addon.ChangeDisenchant(enabled)
    if selectedKey or pendingPurchase or verifying or quote or recheck or (enabled and IsBusy()) then Refresh(); return end
    addon.Disenchant.SetEnabled(enabled)
    if not enabled then
        if scanWork then scanWork.DisableDisenchant() end
        for i = #candidates, 1, -1 do
            if not KeepVendorDeal(candidates[i]) then table.remove(candidates, i) end
        end
        addon.SortDeals(candidates)
    end
    if addon.BagMarkers then addon.BagMarkers.Refresh() end
    Trace("disenchant_setting", { enabled = addon.Disenchant.Enabled() })
    Status(addon.Disenchant.Enabled()
        and "Disenchant estimates enabled. Run a fresh scan. Bag DE icons compare selected DE proceeds with vendor value."
        or "Disenchant estimates disabled; vendor results kept. Run a fresh scan for more offers.")
    Refresh()
end

function addon.ChangeSafeDisenchant(enabled)
    if selectedKey or pendingPurchase or verifying or quote or recheck or IsBusy() then Refresh(); return end
    addon.Disenchant.SetSafe(enabled)
    -- Remove old DE valuations immediately; fresh scans use the new mode.
    for i = #candidates, 1, -1 do
        if not KeepVendorDeal(candidates[i]) then table.remove(candidates, i) end
    end
    addon.SortDeals(candidates)
    page = 1
    if addon.BagMarkers then addon.BagMarkers.Refresh() end
    Trace("safe_disenchant_setting", { safe = addon.Disenchant.Safe() })
    Status((addon.Disenchant.Safe() and "Safe DE: cheapest baseline outcome less 15%."
        or "Average DE: random outcomes can lose gold.")
        .. " Run a fresh scan. Finish scans and price checks before changing this mode.")
    Refresh()
end

function addon.ChangeMinimumProfit(value)
    local previous = addon.GetMinimumProfit()
    if value == previous then addon.SetMinimumProfit(value); return end
    if selectedKey or pendingPurchase or verifying or quote or recheck then
        Status("Finish or cancel the current price check before changing minimum profit.")
        Refresh()
        return
    end
    if not addon.SetMinimumProfit(value) then
        Status("Enter a nonnegative whole copper amount, up to 9 digits. Profit settings must be available.")
        Refresh()
        return
    end
    if scanWork then scanWork.ApplyMinimumProfit() end
    for i = #candidates, 1, -1 do
        if candidates[i].profit < value then table.remove(candidates, i) end
    end
    page = 1
    if not IsBusy() then
        ScanProgress(progressValue, "Minimum " .. value .. "c - " .. #candidates .. " candidates")
    end
    Trace("minimum_profit_setting", { minimum = value, previous = previous,
        scan_busy = scanBusy, candidates = #candidates })
    Status("Minimum profit: " .. value .. "c per item. " .. #candidates .. " candidates kept."
        .. (value < previous and " Run a fresh scan to find newly eligible offers." or ""))
    Refresh()
end

function addon.ChangePrepareListings(enabled)
    if selectedKey or pendingPurchase or verifying or quote or recheck then Refresh(); return end
    addon.Listings.SetEnabled(enabled)
    Status(enabled and "Preparing up to 20 affordable item listings while this tab is idle. Buy still checks the actual auction."
        or "Background listing preparation disabled.")
    Refresh()
end

function addon.ChangeOneClickPrepared(enabled)
    if selectedKey or pendingPurchase or verifying or quote or recheck then Refresh(); return end
    addon.Listings.SetOneClick(enabled)
    Status(enabled and "Prepared Buy 1 buttons buy one auction on your click. Unprepared listings load for confirmation."
        or "Prepared listings open a confirmation before buying.")
    Refresh()
end

Refresh = function()
    local editable = not selectedKey and not pendingPurchase and not verifying and not quote and not recheck
    if addon.Settings then
        addon.Settings.Refresh(editable and (addon.Disenchant.Enabled() or not IsBusy()),
            editable and not IsBusy(), editable, message)
    end
    if not window then
        return
    end
    local list = candidates
    local pages = math.max(1, math.ceil(#list / ROWS))
    page = math.min(page, pages)
    UpdateText(window.heading, addon.Disenchant.Enabled()
        and (addon.Disenchant.Safe()
            and "Safe DE = cheapest baseline outcome less 15%; saved prices, unverified yields"
            or "DE = average baseline yield less 15%; saved prices, unverified yields")
        or ("Estimates per item (min " .. addon.GetMinimumProfit() .. "c) - Buy qty for commodities; Buy for individual auctions"))
    window.debug:SetChecked(addon.Diagnostics.Enabled())
    window.disenchant:SetChecked(addon.Disenchant.Enabled())
    window.safeDisenchant:SetChecked(addon.Disenchant.Safe())
    if not window.minimumProfit:HasFocus() then
        local text = tostring(addon.GetMinimumProfit())
        if window.minimumProfit:GetText() ~= text then window.minimumProfit:SetText(text) end
    end
    UpdateText(window.database, addon.History.Summary())
    UpdateText(window.headers[3], "Buyout / item")
    UpdateText(window.headers[4], addon.Disenchant.Enabled()
        and (addon.Disenchant.Safe() and "Vendor / DE min." or "Vendor / DE est.") or "Vendor / item")
    UpdateText(window.headers[5], "Profit / item")
    UpdateText(window.page, page .. " / " .. pages)
    local idle = not pendingPurchase and (not verifying or recheck ~= nil) and not quote
    local deIcon = addon.Disenchant.Enabled() and addon.Disenchant.Icon()
    local dePrefix = (deIcon and ("|T" .. deIcon .. ":16|t ") or "") .. "|cffcc99ffDE|r "
    UpdateEnabled(window.disenchant, idle and not recheck and not selectedKey
        and (addon.Disenchant.Enabled() or not IsBusy()))
    UpdateEnabled(window.safeDisenchant, idle and not recheck and not selectedKey and not IsBusy())
    UpdateEnabled(window.minimumProfit, not selectedKey and not pendingPurchase and not verifying and not quote and not recheck)
    UpdateEnabled(window.scan, connected and houseOpen and not IsBusy() and idle)
    UpdateEnabled(window.quick, connected and houseOpen and not IsBusy() and idle)
    UpdateText(window.scan, scanBusy and "Scanning..." or "Scan Auction House")
    UpdateEnabled(window.more, selectedKey ~= nil and idle and not recheck
        and not (selectedCommodity and C_AuctionHouse.HasFullCommoditySearchResults(selectedKey.itemID)
            or not selectedCommodity and C_AuctionHouse.HasFullItemSearchResults(selectedKey)))
    UpdateEnabled(window.previous, idle and page > 1)
    UpdateEnabled(window.next, idle and page < pages)
    for i, row in ipairs(window.rows) do
        local deal = list[(page - 1) * ROWS + i]
        row.deal = deal
        local shown = deal ~= nil
        if row.displayedShown ~= shown then row.displayedShown = shown; row:SetShown(shown) end
        if deal then
            UpdateText(row.item, (deal.disenchant and dePrefix or "") .. (deal.display or deal.link))
            UpdateText(row.quantity, deal.availablePartial and (">=" .. deal.available) or deal.available or deal.quantity)
            UpdateMoney(row.cost, deal.cost)
            UpdateMoney(row.vendor, deal.deNet or deal.vendor)
            UpdateMoney(row.profit, deal.profit, deal.disenchant and "|cffcc99ff" or "|cff44ff44")
            UpdateText(row.action, verifying and selectedCandidate == deal and "Wait..." or deal.isCommodity and "Buy qty"
                or addon.Listings.OneClick() and addon.Listings.Has(deal) and "Buy 1" or "Buy")
            UpdateEnabled(row.action, houseOpen and idle and not (recheck and selectedCandidate == deal))
        end
    end
    addon.Listings.Update(list, houseOpen and window:IsShown() and editable and not IsBusy(), purchased)
end

local function EnsureTab()
    if not AuctionHouseFrame then return false end
    tabLibrary = LibStub and LibStub("LibAHTab-1-0", true)
    if not tabLibrary then return false end
    if not window then
        window = CreateFrame("Frame", nil, AuctionHouseFrame, "InsetFrameTemplate")
        window:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 5, -35)
        window:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -5, 32)
        window:EnableMouse(true)
        Label(window, 20, -20, 260, "GameFontNormalLarge"):SetText("Profit Master")
        window.debug = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        window.debug:SetSize(24, 24)
        window.debug:SetPoint("TOPLEFT", 152, -14)
        Label(window, 180, -22, 70, "GameFontNormalSmall"):SetText("Enable debug")
        window.debug:SetScript("OnClick", function(self)
            addon.ChangeDebug(self:GetChecked())
        end)
        window.disenchant = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        window.disenchant:SetSize(24, 24)
        window.disenchant:SetPoint("TOPLEFT", 258, -14)
        Label(window, 286, -22, 108, "GameFontNormalSmall"):SetText("Disenchant profits")
        window.disenchant:SetScript("OnClick", function(self)
            addon.ChangeDisenchant(self:GetChecked() == true)
        end)
        window.safeDisenchant = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        window.safeDisenchant:SetSize(24, 24)
        window.safeDisenchant:SetPoint("TOPLEFT", 20, -43)
        Label(window, 48, -51, 150, "GameFontNormalSmall"):SetText("Safe disenchant")
        window.safeDisenchant:SetScript("OnClick", function(self)
            addon.ChangeSafeDisenchant(self:GetChecked())
        end)
        Label(window, 400, -22, 72, "GameFontNormalSmall"):SetText("Min profit:")
        window.minimumProfit = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        window.minimumProfit:SetSize(50, 22)
        window.minimumProfit:SetPoint("TOPLEFT", 480, -15)
        window.minimumProfit:SetAutoFocus(false)
        window.minimumProfit:SetNumeric(true)
        window.minimumProfit:SetMaxLetters(9)
        Label(window, 534, -22, 10, "GameFontNormalSmall"):SetText("c")
        local function ResetMinimum(editBox)
            local text = tostring(addon.GetMinimumProfit())
            if editBox:GetText() ~= text then editBox:SetText(text) end
        end
        local function CommitMinimum(editBox)
            addon.ChangeMinimumProfit(tonumber(editBox:GetText()))
            ResetMinimum(editBox)
        end
        window.minimumProfit:SetScript("OnEnterPressed", function(self) CommitMinimum(self); self:ClearFocus() end)
        window.minimumProfit:SetScript("OnEditFocusLost", function(self) CommitMinimum(self); self:HighlightText(0, 0) end)
        window.minimumProfit:SetScript("OnEscapePressed", function(self) ResetMinimum(self); self:ClearFocus() end)
        window.progress = CreateFrame("StatusBar", nil, window)
        window.progress:SetSize(220, 20)
        window.progress:SetPoint("TOPRIGHT", -20, -18)
        window.progress:EnableMouse(false)
        window.progress:SetMinMaxValues(0, 1)
        window.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        window.progress:SetStatusBarColor(0.12, 0.4, 0.7)
        local background = window.progress:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.05, 0.05, 0.05, 1)
        window.progress.text = Label(window.progress, 8, -3, 204)
        window.progress.text:SetJustifyH("CENTER")
        window.progress:SetValue(progressValue)
        window.progress.text:SetText(progressText)
        window.heading = Label(window, 210, -48, 550, "GameFontNormalSmall")
        window.headers = {}
        for i, column in ipairs({ {20, 245, "Item"}, {270, 40, "Avail."},
            {315, 125, "Buyout / item"}, {445, 125, "Vendor / item"}, {575, 125, "Profit / item"} }) do
            window.headers[i] = Label(window, column[1], -83, column[2], "GameFontNormalSmall")
            window.headers[i]:SetText(column[3])
        end
        window.rows = {}
        for i = 1, ROWS do
            local row = CreateFrame("Frame", nil, window)
            row:SetSize(750, 30)
            row:SetPoint("TOPLEFT", 20, -105 - (i - 1) * 31)
            row.item = Label(row, 0, -6, 245)
            row.quantity = Label(row, 250, -6, 40)
            row.cost = Label(row, 295, -6, 125)
            row.vendor = Label(row, 425, -6, 125)
            row.profit = Label(row, 555, -6, 125)
            row.action = Button(row, "Buy", 65, function()
                if row.deal then
                    PreparePurchase(row.deal)
                end
            end)
            row.action:SetPoint("TOPRIGHT", 0, 0)
            window.rows[i] = row
        end
        window.status = Label(window, 20, -362, 750)
        window.status:SetHeight(36)
        window.status:SetText(message)
        window.database = Label(window, 20, -403, 750)
        window.scan = Button(window, "Scan Auction House", 135, StartScan)
        window.scan:SetPoint("BOTTOMLEFT", 20, 15)
        window.quick = Button(window, "Quick scan", 80, StartQuickScan)
        window.quick:SetPoint("LEFT", window.scan, "RIGHT", 6, 0)
        window.more = Button(window, "More listings", 90, function()
            if selectedKey and not pendingPurchase and not quote and not verifying and Ready() then
                PauseScanWork()
                StopTimer()
                verifying = true
                commodityDeadline = time() + 15
                timer = C_Timer.NewTimer(15, function()
                    timer = nil
                    CancelPurchase("More-listings request timed out. Results kept.")
                end)
                RequestMoreResults()
                Refresh()
            end
        end)
        window.more:SetPoint("LEFT", window.quick, "RIGHT", 6, 0)
        window.log = Button(window, "Debug log", 75, addon.Diagnostics.Show)
        window.log:SetPoint("LEFT", window.more, "RIGHT", 6, 0)
        window.previous = Button(window, "Previous", 80, function() page = page - 1; Refresh() end)
        window.previous:SetPoint("BOTTOMRIGHT", -190, 15)
        window.page = Label(window, 0, 0, 80)
        window.page:ClearAllPoints()
        window.page:SetPoint("LEFT", window.previous, "RIGHT", 12, 0)
        window.next = Button(window, "Next", 80, function() page = page + 1; Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -20, 15)
        window:SetScript("OnShow", function()
            if lastScanAt and not IsBusy() and not pendingPurchase and not verifying and not quote then Status(CandidateStatus()) end
            Refresh()
        end)
        window:SetScript("OnHide", function()
            addon.Listings.Update(nil, false, purchased)
            if addon.BrowseScanner and addon.BrowseScanner.Active() then
                addon.BrowseScanner.Stop()
                if scanWork and scanWork.ownedBrowse and scanWork.receiving then
                    scanWork.partial = true
                    scanWork.Complete(scanWork.latestRows)
                end
            end
            -- Tab changes preserve a pending purchase response and bounded scan work.
            if commodityPurchase and commodityPurchase.phase == "quote" then
                CancelPurchase("Commodity quote canceled after switching tabs. Results kept.")
                return
            end
            if not pendingPurchase and not recheck and selectedKey then
                CancelPurchase("Purchase canceled after switching tabs. Results kept.")
            end
        end)
        window:Hide()
        -- Share Auctionator's existing library; do not modify Blizzard's Tabs array.
        tabLibrary:CreateTab(TAB_ID, window, "Profit Master")
    end
    return true
end

addon.RefreshSettings = Refresh

local function ShowWindow()
    if houseOpen and AuctionHouseFrame and AuctionHouseFrame:IsShown() and EnsureTab() then
        tabLibrary:SetSelected(TAB_ID)
    end
end

local function ReplicateCount()
    if not C_AuctionHouse.GetNumReplicateItems then return nil end
    local count = C_AuctionHouse.GetNumReplicateItems()
    if not (issecretvalue and issecretvalue(count)) and type(count) == "number"
        and count >= 0 and count < math.huge and count == math.floor(count) then return count end
end

ProcessScan = function(data, isBrowse, receiving, quickKeys)
    local previous = quickKeys and candidates
    StopScanWork()
    ClearLive(true)
    scanBusy = true
    excluded, liveValued = {}, {}
    scanCoverage, lastScanAt = nil, nil
    candidates, page = quickKeys and previous or {}, 1
    local work = { paused = false, receiving = receiving, isBrowse = isBrowse, startedAt = GetTime(), batchSeconds = 0,
        preciseStart = GetTimePreciseSec(), vendorRequests = 0, vendorActive = 0, vendorReferences = 0,
        vendorPendingSeconds = 0, vendorPendingAfterInput = 0, vendorLoadingSeconds = 0,
        vendorReadySeconds = 0, vendorReadyMax = 0, valuationSeconds = 0, vendorRetrySeconds = 0, deSeconds = 0 }
    if not receiving then work.inputClosedAt, work.inputClosedActive = work.startedAt, work.preciseStart end
    scanWork = work
    local total, snapshotAt = #data, scanStartedAt or time()
    local repricingRows, repricingPrices = {}, {}
    local historyScan = addon.History.BeginScan(isBrowse and "browse" or "replicate", snapshotAt, false)
    work.historyScan = historyScan
    if not isBrowse and not receiving then
        work.replicateCount, work.replicateGeneration = ReplicateCount(), replicateGeneration
    end
    local best, itemCache, index = {}, {}, 1
    local watched, refreshed = {}, {}
    if quickKeys then
        for _, key in ipairs(quickKeys) do watched[key.itemID] = true end
        for _, deal in ipairs(previous) do best[deal.itemID] = deal end
    end
    local retryRows, loadIDs, queued, loadReferences, previews = {}, {}, {}, {}, {}
    local retried, dirty, lastPublished = false, false, -math.huge
    local stats = { priced = 0, unavailable = 0, noVendor = 0, notCheap = 0, belowMinimum = 0, unsupported = 0, filtered = 0,
        loadOK = 0, loadFailed = 0, recordOK = 0 }
    local Batch, LoadItems

    local function PendingSeconds(now)
        local pending, tail = work.vendorPendingSeconds, work.vendorPendingAfterInput
        if work.vendorUnionStart then
            pending = pending + now - work.vendorUnionStart
            if work.inputClosedActive then
                tail = tail + math.max(0, now - math.max(work.vendorUnionStart, work.inputClosedActive))
            end
        end
        return pending, tail
    end

    local function CloseVendorPending(now)
        work.vendorPendingSeconds, work.vendorPendingAfterInput = PendingSeconds(now)
        work.vendorUnionStart = nil
    end

    local function Milliseconds(seconds)
        return math.max(0, math.floor((seconds or 0) * 1000 + 0.5))
    end

    work.SaveProfile = function(outcome)
        if work.profileSaved then return end
        work.profileSaved = true
        local rawNow, now = GetTimePreciseSec(), ActiveScanClock(work)
        local pending, tail = PendingSeconds(now)
        local paused = (work.pausedSeconds or 0) + (work.profilePauseAt and (rawNow - work.profilePauseAt) or 0)
        local profile = {
            outcome = outcome, source = quickKeys and "quick" or isBrowse and "browse" or "replicate", at = time(), rows = total,
            minimum_profit = addon.GetMinimumProfit(), scan_ms = Milliseconds(rawNow - work.preciseStart),
            active_ms = Milliseconds(now - work.preciseStart), pause_ms = Milliseconds(paused),
            provider_ms = Milliseconds((work.inputClosedAt or GetTime()) - work.startedAt),
            post_input_ms = work.inputClosedActive and Milliseconds(now - work.inputClosedActive) or nil,
            vendor_missing_ids = #loadIDs, vendor_missing_refs = work.vendorReferences,
            vendor_requests = work.vendorRequests, vendor_ready = stats.loadOK, vendor_failed = stats.loadFailed,
            vendor_unresolved = work.vendorActive + (work.vendorUnresolved or 0),
            vendor_queued = math.max(0, #loadIDs - work.vendorRequests),
            vendor_pending_ms = Milliseconds(pending), vendor_pending_after_input_ms = Milliseconds(tail),
            vendor_ready_avg_ms = stats.loadOK > 0 and Milliseconds(work.vendorReadySeconds / stats.loadOK) or 0,
            vendor_ready_max_ms = Milliseconds(work.vendorReadyMax),
            vendor_loading_cpu_ms = Milliseconds(work.vendorLoadingSeconds),
            vendor_retry_cpu_ms = Milliseconds(work.vendorRetrySeconds),
            valuation_cpu_ms = Milliseconds(work.valuationSeconds), de_cpu_ms = Milliseconds(work.deSeconds),
            history_ms = Milliseconds(work.historySeconds), batch_ms = Milliseconds(work.batchSeconds),
        }
        addon.LastScanProfile = profile
        addon.Diagnostics.Log("scan_profile", profile)
    end

    -- Loading may synchronously invoke its own readiness callback. Count the
    -- outermost slice once rather than charging that nested work twice.
    local loadingDepth, loadingStarted = 0, nil
    local function ProfileVendor(callback)
        return function(...)
            if loadingDepth == 0 then loadingStarted = GetTimePreciseSec() end
            loadingDepth = loadingDepth + 1
            callback(...)
            loadingDepth = loadingDepth - 1
            if loadingDepth == 0 then
                work.vendorLoadingSeconds = work.vendorLoadingSeconds + GetTimePreciseSec() - loadingStarted
            end
        end
    end

    local function Value(entry)
        if isBrowse then return addon.BrowseDeal(entry, itemCache) end
        return addon.ReplicateDeal(entry, itemCache)
    end

    local function Consider(deal)
        if not deal or deal.profit <= 0 or deal.profit < addon.GetMinimumProfit()
            or excluded[deal.itemID] or liveValued[deal.itemID] then return end
        local previous = best[deal.itemID]
        if not previous or deal.profit > previous.profit then
            best[deal.itemID], dirty = deal, true
            addon.History.RememberOpportunity(deal)
        end
    end

    local function Publish(force)
        if scanWork ~= work or work.paused or not dirty then return end
        if not force and GetTime() - lastPublished < SCAN_PUBLISH_INTERVAL then return end
        candidates = {}
        for id, deal in pairs(best) do
            if not excluded[id] and deal.profit > 0 and deal.profit >= addon.GetMinimumProfit()
                and (not deal.disenchant or addon.Disenchant.Enabled()) then
                candidates[#candidates + 1] = deal
            end
        end
        addon.SortDeals(candidates)
        dirty, lastPublished = false, GetTime()
        lastScanAt = snapshotAt
        scanCoverage = work.receiving and "Partial scan; comparing results as they arrive."
            or "Partial valuation; more items are still being checked."
        if work.receiving then
            Status(#candidates .. " candidates found so far. Comparing incoming rows; Buy checks when the Auction House is ready.")
        end
        Refresh()
    end

    work.DisableDisenchant = function()
        for id, deal in pairs(best) do
            if not KeepVendorDeal(deal) then best[id] = nil end
        end
        dirty = true
    end

    work.ApplyMinimumProfit = function()
        local minimum = addon.GetMinimumProfit()
        for id, deal in pairs(best) do
            if deal.profit < minimum then best[id] = nil end
        end
        dirty = true
    end

    local function Finish()
        if quickKeys and not work.partial then
            for id in pairs(watched) do
                if not refreshed[id] and not liveValued[id] then best[id], dirty = nil, true end
            end
        end
        Publish(true)
        scanWork, scanBusy = nil, false
        lastScanAt, scanStartedAt = snapshotAt, nil
        scanCoverage = "Scanned " .. total .. "; priced " .. stats.priced
            .. "; unavailable " .. stats.unavailable .. "; unsupported " .. stats.unsupported
            .. "; no vendor " .. stats.noVendor .. "; not below vendor " .. stats.notCheap
            .. "; below profit minimum when checked " .. stats.belowMinimum
            .. "; other excluded " .. stats.filtered .. "."
        if addon.Disenchant.Enabled() then
            local deCount = 0
            for _, deal in ipairs(candidates) do if deal.disenchant then deCount = deCount + 1 end end
            scanCoverage = "Scanned " .. total .. "; priced " .. stats.priced .. "; unavailable " .. stats.unavailable
                .. "; DE estimates " .. deCount .. ". Unknown yields/prices skipped; random outcomes, 15% fee allowance."
        end
        if stats.recordOK > 0 or stats.loadOK > 0 or stats.loadFailed > 0 then
            scanCoverage = scanCoverage .. " Item records: " .. stats.recordOK .. " OK; vendor data: "
                .. stats.loadOK .. " ready, " .. stats.loadFailed .. " failed."
        end
        if isBrowse then
            scanCoverage = scanCoverage .. " Browse minima saved; full snapshot needed for trimmed means."
        elseif work.meanCount and work.meanCount > 0 then
            scanCoverage = scanCoverage .. " Trimmed market means saved: " .. work.meanCount .. " items."
        else
            scanCoverage = scanCoverage .. " Trimmed means not saved: incomplete price snapshot."
        end
        if quickKeys then scanCoverage = "Quick scan: " .. #quickKeys .. " known keys only. " .. scanCoverage end
        if work.partial then
            scanCoverage = "Partial discovery stopped. " .. scanCoverage
            ScanProgress(1, "Partial scan - " .. #candidates .. " candidates")
        elseif stats.unavailable > 0 then
            ScanProgress(1, "Incomplete data - " .. #candidates .. " candidates; " .. stats.unavailable .. " unavailable")
        elseif total == 0 then
            ScanProgress(1, "Scan returned no listings")
        else
            ScanProgress(1, "Scan complete - " .. #candidates .. " candidates; " .. stats.priced .. " priced")
        end
        Status(CandidateStatus())
        work.SaveProfile(work.partial and "partial" or "complete")
        Trace("scan_complete", { rows = total, priced = stats.priced, unavailable = stats.unavailable,
            candidates = #candidates, source = quickKeys and "quick" or isBrowse and "browse" or "replicate",
            minimum_profit = addon.GetMinimumProfit(),
            scan_ms = math.floor((GetTime() - work.startedAt) * 1000 + 0.5),
            batch_ms = math.floor(work.batchSeconds * 1000 + 0.5),
            history_means = work.meanCount or 0,
            history_rows = work.historyRows or 0,
            history_ms = math.floor((work.historySeconds or 0) * 1000 + 0.5),
            provider_ms = math.floor(((work.inputClosedAt or GetTime()) - work.startedAt) * 1000 + 0.5) })
        if addon.BagMarkers then addon.BagMarkers.Refresh() end
        Refresh()
    end

    local historyIndex, historyStep = 0, nil
    local function FinishHistory()
        if scanWork ~= work or work.paused then return end
        timer = nil
        -- Browse only supplies minima. A full scan's raw numeric snapshot also
        -- contains rows Auctionator may omit while waiting for item descriptions.
        if isBrowse or work.partial or not C_AuctionHouse.GetReplicateItemInfo
            or work.replicateCount == nil or work.replicateCount ~= ReplicateCount()
            or work.replicateGeneration ~= replicateGeneration then
            addon.History.Abort(work.meanScan)
            Finish()
            return
        end
        if not work.meanScan then
            work.meanScan = addon.History.BeginScan("replicate", snapshotAt, true)
            if not work.meanScan then Finish(); return end
            ScanProgress(0.99, "Saving trimmed market prices...")
        end
        local started = GetTimePreciseSec()
        local finalize = historyStep ~= nil
        if not historyStep then
            local last = math.min(historyIndex + 999, work.replicateCount - 1)
            for i = historyIndex, last do
                local valid, reason = addon.History.RecordReplicateDistribution(work.meanScan, { C_AuctionHouse.GetReplicateItemInfo(i) })
                historyIndex = i + 1
                work.historyRows = historyIndex
                if not valid then
                    Trace("history_snapshot_rejected", { index = i, reason = reason })
                    local elapsed = GetTimePreciseSec() - started
                    work.historySeconds = (work.historySeconds or 0) + elapsed
                    work.batchSeconds = work.batchSeconds + elapsed
                    addon.History.Abort(work.meanScan)
                    Finish()
                    return
                end
                if GetTimePreciseSec() - started >= 0.004 then break end
            end
            if historyIndex == work.replicateCount then
                historyStep = addon.History.Finish(work.meanScan, true)
            end
        end
        if finalize then
            local done, saved = historyStep()
            if done then
                work.meanCount = saved
                local elapsed = GetTimePreciseSec() - started
                work.historySeconds = (work.historySeconds or 0) + elapsed
                work.batchSeconds = work.batchSeconds + elapsed
                Finish()
                return
            end
        end
        local elapsed = GetTimePreciseSec() - started
        work.historySeconds = (work.historySeconds or 0) + elapsed
        work.batchSeconds = work.batchSeconds + elapsed
        timer = C_Timer.NewTimer(0, FinishHistory)
    end

    local loadStep
    LoadItems = function()
        if loadStep then loadStep(); return end
        local nextID, active, completed, pumping = 1, {}, 0, false
        local recordSeen, previewPending = {}, {}
        local activeCount = 0
        -- While input is open, load alongside the provider without an idle timer.
        -- The final 60-second loading budget starts when incoming valuation drains.
        local deadline
        work.extendDeadline = function(seconds) if deadline then deadline = deadline + seconds end end
        local Pump, Arm
        local function PreviewReady()
            for id in pairs(previewPending) do
                for _, preview in pairs(previews[id]) do Consider(Value(preview.entry)) end
                previewPending[id] = nil
            end
            Publish(false)
        end
        local Retry
        Retry = ProfileVendor(function()
            if scanWork ~= work then return end
            if work.paused then work.resume = Retry; return end
            work.vendorUnresolved = activeCount
            CloseVendorPending(ActiveScanClock(work))
            work.vendorActive = 0
            StopTimer()
            onItemData = nil
            events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            data, retryRows = retryRows, {}
            for _, references in pairs(loadReferences) do
                for reference in pairs(references) do
                    if itemCache[reference] == false then itemCache[reference] = nil end
                end
            end
            index, retried = 1, true
            work.extendDeadline = nil
            work.resume = Batch
            ScanProgress(0, "Rechecking loaded vendor prices...")
            timer = C_Timer.NewTimer(0, Batch)
        end)
        Arm = function()
            if scanWork ~= work or work.paused then return end
            StopTimer()
            local remaining = deadline and math.max(0, deadline - time())
            if not remaining then
                if dirty then
                    timer = C_Timer.NewTimer(math.max(0, SCAN_PUBLISH_INTERVAL - (GetTime() - lastPublished)), function()
                        timer = nil
                        if scanWork == work and not work.paused then Publish(true) end
                    end)
                end
                return
            end
            local render = dirty and remaining > SCAN_PUBLISH_INTERVAL
            timer = C_Timer.NewTimer(render and SCAN_PUBLISH_INTERVAL or remaining, function()
                if scanWork ~= work or work.paused then return end
                timer = nil
                if render and time() < deadline then
                    Publish(true)
                    timer = C_Timer.NewTimer(math.max(0, deadline - time()), Retry)
                else Retry() end
            end)
        end
        Pump = function()
            if scanWork ~= work or work.paused or pumping then return end
            pumping = true
            local sent, started = 0, GetTimePreciseSec()
            while activeCount < 32 and nextID <= #loadIDs and sent < 32 do
                local id = loadIDs[nextID]
                nextID, sent = nextID + 1, sent + 1
                local now = ActiveScanClock(work)
                if activeCount == 0 then work.vendorUnionStart = now end
                active[id], activeCount = now, activeCount + 1
                work.vendorActive, work.vendorRequests = activeCount, work.vendorRequests + 1
                C_Item.RequestLoadItemDataByID(id)
                if GetTimePreciseSec() - started >= 0.004 then break end
            end
            pumping = false
        end
        loadStep = ProfileVendor(function()
            if scanWork ~= work or work.paused then return end
            StopTimer()
            work.waiting = true
            if not work.receiving and not deadline then
                deadline = time() + 60
                ScanProgress(0, "Loading item data: " .. completed .. " / " .. #loadIDs)
                Status("Loading vendor data; ready candidates can already be bought.")
            end
            PreviewReady()
            if deadline and time() >= deadline then Retry(); return end
            Pump()
            PreviewReady()
            if activeCount == 0 and nextID <= #loadIDs then
                -- Synchronous completions still yield between bounded dispatches.
                timer = C_Timer.NewTimer(0, loadStep)
            elseif not work.receiving and activeCount == 0 then Retry()
            else Arm() end
        end)
        work.resume = function()
            if index <= #data then Batch() else loadStep() end
        end
        onItemData = ProfileVendor(function(id, success, event)
            if not active[id] then return end
            local publicSuccess = not (issecretvalue and issecretvalue(success))
            if event == "ITEM_DATA_LOAD_RESULT" and publicSuccess and success == true and not recordSeen[id] then
                recordSeen[id] = true
                stats.recordOK = stats.recordOK + 1
            end
            local ready = true
            for reference in pairs(loadReferences[id]) do
                if type(itemCache[reference]) ~= "table" and not addon.CaptureVendorInfo(reference, itemCache) then ready = false end
            end
            if not ready and not (publicSuccess and success == false) then return end
            local now, sentAt = ActiveScanClock(work), active[id]
            active[id], activeCount = nil, activeCount - 1
            work.vendorActive = activeCount
            if activeCount == 0 then CloseVendorPending(now) end
            if ready then
                stats.loadOK = stats.loadOK + 1
                local elapsed = math.max(0, now - sentAt)
                work.vendorReadySeconds = work.vendorReadySeconds + elapsed
                work.vendorReadyMax = math.max(work.vendorReadyMax, elapsed)
                previewPending[id] = true
            else stats.loadFailed = stats.loadFailed + 1 end
            completed = completed + 1
            if completed % 32 == 0 or completed == #loadIDs then
                Trace("vendor_load", { completed = completed, total = #loadIDs, ready = stats.loadOK, failed = stats.loadFailed })
                if not work.receiving then
                    ScanProgress(math.min(0.99, completed / #loadIDs), "Loading item data: " .. completed .. " / " .. #loadIDs)
                end
            end
            -- Never replace a pending valuation or purchase timer from a callback.
            if not pumping and not work.paused and work.waiting then loadStep() end
        end)
        events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        Trace("vendor_load_start", { total = #loadIDs, receiving = work.receiving or false })
        loadStep()
    end

    Batch = function()
        if scanWork ~= work or work.paused then return end
        timer = nil
        work.waiting = false
        if not houseOpen then return end
        local started = GetTimePreciseSec()
        local cpuStage = work.deOnly and "deSeconds" or retried and "vendorRetrySeconds" or "valuationSeconds"
        for i = index, math.min(index + 999, #data) do
            local entry = data[i]
            local info = entry and entry.replicateInfo
            if quickKeys and not retried and entry and entry.itemKey then
                local id = entry.itemKey.itemID
                if watched[id] and not refreshed[id] then
                    refreshed[id] = true
                    if not liveValued[id] then best[id], dirty = nil, true end
                end
            end
            if work.deOnly then
                Consider(Value(entry))
            else
                if not retried then
                    if isBrowse then addon.History.RecordBrowse(historyScan, entry)
                    else addon.History.RecordReplicate(historyScan, entry) end
                end
                local deal, missing, reason = Value(entry)
                if not retried and addon.Disenchant.Enabled() and (deal or missing or reason == "notCheap"
                    or reason == "noVendor" or reason == "belowMinimum") then
                    -- Browse estimates use a base ID; replicate estimates use an
                    -- exact link. Only the cheapest offer per reference can win.
                    local reference = isBrowse and entry.itemKey.itemID or entry.itemLink
                    local price = isBrowse and entry.minPrice or info[10] / info[3]
                    if not repricingPrices[reference] or price < repricingPrices[reference] then
                        repricingRows[reference], repricingPrices[reference] = entry, price
                    end
                end
                if deal or reason == "notCheap" or reason == "noVendor" or reason == "belowMinimum" then stats.priced = stats.priced + 1 end
                if deal then Consider(deal)
                elseif missing then
                    local id = isBrowse and entry.itemKey.itemID or info[17]
                    if not retried and type(id) == "number" and id > 0 then
                        retryRows[#retryRows + 1] = entry
                        if not queued[id] then
                            queued[id] = true
                            loadIDs[#loadIDs + 1] = id
                            loadReferences[id], previews[id] = {}, {}
                        end
                        local reference = isBrowse and id or entry.itemLink
                        if not loadReferences[id][reference] then work.vendorReferences = work.vendorReferences + 1 end
                        loadReferences[id][reference] = true
                        local price = isBrowse and entry.minPrice or info[10] / info[3]
                        local preview = previews[id][reference]
                        if not preview or price < preview.price then previews[id][reference] = { entry = entry, price = price } end
                    else stats.unavailable = stats.unavailable + 1 end
                elseif reason == "noVendor" or reason == "notCheap" or reason == "belowMinimum" then stats[reason] = stats[reason] + 1
                elseif reason == "commodity" or reason == "pet" then stats.unsupported = stats.unsupported + 1
                else stats.filtered = stats.filtered + 1 end
            end
            index = i + 1
            if GetTimePreciseSec() - started >= 0.004 then break end
        end
        Publish(false)
        local batchSeconds = GetTimePreciseSec() - started
        work.batchSeconds = work.batchSeconds + batchSeconds
        work[cpuStage] = work[cpuStage] + batchSeconds
        Trace("valuation_batch", { processed = index - 1, queued = #data, receiving = work.receiving or false,
            priced = stats.priced, unavailable = stats.unavailable, stage = work.deOnly and "disenchant" or "vendor",
            batch_ms = math.floor(batchSeconds * 1000 + 0.5) })
        if index <= #data then
            if not work.receiving then
                ScanProgress((index - 1) / #data, (work.deOnly and "Repricing DE estimates: " or "Checking vendor prices: ")
                    .. (index - 1) .. " / " .. #data)
            end
            timer = C_Timer.NewTimer(0, Batch)
        elseif not retried and #loadIDs > 0 and (isBrowse or not work.receiving) then LoadItems()
        elseif work.receiving then
            -- No idle polling: the next provider batch or completion resumes us.
            work.waiting = true
            if dirty then
                timer = C_Timer.NewTimer(math.max(0, SCAN_PUBLISH_INTERVAL - (GetTime() - lastPublished)), function()
                    timer = nil
                    Publish(true)
                end)
            end
        elseif addon.Disenchant.Enabled() and not work.deOnly then
            -- Auctionator updates material prices at completion. Reconcile estimates
            -- against that snapshot without repeating history or vendor counts.
            addon.Disenchant.ResetCache()
            for id, deal in pairs(best) do
                if deal.disenchant and not liveValued[id] then best[id], dirty = nil, true end
            end
            data = {}
            for _, entry in pairs(repricingRows) do data[#data + 1] = entry end
            index, retried, work.deOnly = 1, true, true
            work.resume = Batch
            timer = C_Timer.NewTimer(0, Batch)
        else
            work.resume = FinishHistory
            if not isBrowse and C_AuctionHouse.GetReplicateItemInfo then
                timer = C_Timer.NewTimer(0, FinishHistory)
            else FinishHistory() end
        end
    end
    work.resume = Batch
    if receiving then
        local seen, cursors = {}, {}
        work.Feed = function(rows, last)
            if scanWork ~= work or type(rows) ~= "table" then return end
            last = last or #rows
            for i = (cursors[rows] or 0) + 1, last do
                local entry = rows[i]
                -- The provider's final payload reuses the prepared row tables.
                -- Ignore those already queued, including delayed sparse rows.
                if type(entry) == "table" and not (issecretvalue and issecretvalue(entry)) and not seen[entry] then
                    seen[entry] = true
                    data[#data + 1] = entry
                end
            end
            cursors[rows], total = math.max(cursors[rows] or 0, last), #data
            if work.waiting and not work.paused then
                work.waiting = false
                StopTimer()
                Batch()
            end
        end
        work.Complete = function(rows)
            work.inputClosedAt = GetTime()
            work.inputClosedActive = ActiveScanClock(work)
            work.receiving = false
            if not isBrowse and work.replicateGeneration == nil then
                work.replicateCount, work.replicateGeneration = ReplicateCount(), replicateGeneration
            end
            work.Feed(rows)
        end
    end
    ScanProgress(0, "Checking vendor prices: 0 / " .. #data)
    Status("Publishing candidates as vendor prices are checked; Buy takes priority.")
    Refresh()
    Batch()
    return work
end

local function ConnectAuctionator()
    if not houseOpen then return end
    if Auctionator and Auctionator.Variables and Auctionator.Variables.GetConnectedRealmRoot then
        addon.History.SetMarket(Auctionator.Variables.GetConnectedRealmRoot())
    end
    if connected then return end
    if not Auctionator or not Auctionator.EventBus or not Auctionator.FullScan
        or not Auctionator.State or not C_AuctionHouse or not C_AuctionHouse.SendSellSearchQuery then
        Status("This version needs Auctionator's modern full scanner and the Forever auction API.")
        return
    end
    local scanEvents = Auctionator.FullScan.Events
    local browseEvents = Auctionator.IncrementalScan and Auctionator.IncrementalScan.Events or {}
    local listener = {}
    function listener:ReceiveEvent(event, data)
        if not houseOpen then return end
        if event == scanEvents.ScanStart or event == browseEvents.ScanStart then
            if addon.BrowseScanner then addon.BrowseScanner.Stop() end
            addon.Disenchant.ResetCache()
            Trace("scan_start", { source = event })
            StopScanWork()
            scanBusy = true
            scanStartedAt = time()
            scanLabel = event == browseEvents.ScanStart and "Auctionator browse scan" or "Auctionator full scan"
            if not pendingPurchase then ClearLive() end
            if houseOpen and not pendingPurchase and not verifying and not quote then
                local work = ProcessScan({}, event == browseEvents.ScanStart, true)
                -- Ignore a previous/canceled browse buffer until the provider
                -- replaces it on the first fresh BROWSE_RESULTS_UPDATED event.
                work.oldBrowse = Auctionator.State.IncrementalScanFrameRef
                    and Auctionator.State.IncrementalScanFrameRef.rawScan
            end
            ScanProgress(0, scanLabel .. ": 0% - waiting for server")
            Status(scanLabel .. " in progress...")
            Refresh()
        elseif (event == scanEvents.ScanProgress or event == browseEvents.ScanProgress) and houseOpen and scanBusy then
            if type(data) == "number" and not (issecretvalue and issecretvalue(data)) then
                -- Auctionator can report 100% before its database finishes processing.
                local value = math.max(progressValue, math.min(0.99, math.max(0, data)))
                local text = scanLabel .. ": " .. math.floor(value * 100) .. "%"
                if value <= 0.1 then text = text .. " - waiting for server"
                elseif value >= 0.99 then text = text .. " - finishing scan" end
                ScanProgress(value, text)
                Trace("scan_progress", { progress = value })
                local work = scanWork
                if work and work.receiving and work.isBrowse == (event == browseEvents.ScanProgress) then
                    if not work.isBrowse and data >= 0.2 and work.replicateGeneration == nil then
                        -- Auctionator 346 reports 0.2 after the native snapshot
                        -- arrives; ScanStart still sees the previous cache.
                        work.replicateCount, work.replicateGeneration = ReplicateCount(), replicateGeneration
                    end
                    if work.isBrowse then
                        local source = Auctionator.State.IncrementalScanFrameRef
                        if source and source.rawScan ~= work.oldBrowse then work.Feed(source.rawScan) end
                    elseif data > 0.2 and data < 0.99 then
                        local source = Auctionator.State.FullScanFrameRef
                        if source and source.inProgress and source.scanData then
                            -- Auctionator 346 fires progress before each 250-row
                            -- batch. Only read positions it has already visited.
                            local count = C_AuctionHouse.GetNumReplicateItems()
                            if type(count) == "number" and not (issecretvalue and issecretvalue(count)) then
                                work.Feed(source.scanData, math.min(count, math.floor((data - 0.2) / 0.8 * count)))
                            end
                        end
                    end
                    if not ProviderBusy() then
                        if queuedSearch then TryQueuedSearch() end
                        Refresh()
                    end
                end
            end
        elseif event == scanEvents.ScanFailed or event == browseEvents.ScanFailed then
            StopScanWork("failed")
            scanBusy = false
            ScanProgress(0, scanLabel .. " failed")
            Status("Auctionator scan failed. Reopen the Auction House and try again.")
            if queuedSearch then TryQueuedSearch() end
            Refresh()
        elseif event == scanEvents.ScanComplete or event == browseEvents.ScanComplete then
            if houseOpen and type(data) == "table" and scanWork and scanWork.receiving
                and scanWork.isBrowse == (event == browseEvents.ScanComplete) then
                scanWork.Complete(data)
            elseif houseOpen and type(data) == "table" and not pendingPurchase and not verifying and not quote then
                scanBusy = false
                ProcessScan(data, event == browseEvents.ScanComplete)
            else
                scanBusy = false
            end
            if queuedSearch then TryQueuedSearch() end
        end
    end
    -- Internal integration verified against installed Auctionator 346.
    local subscriptions = { scanEvents.ScanStart, scanEvents.ScanProgress, scanEvents.ScanFailed, scanEvents.ScanComplete }
    if browseEvents.ScanStart then
        for _, event in ipairs({ browseEvents.ScanStart, browseEvents.ScanProgress, browseEvents.ScanFailed, browseEvents.ScanComplete }) do
            subscriptions[#subscriptions + 1] = event
        end
    end
    Auctionator.EventBus:Register(listener, subscriptions)
    auctionListener, auctionSubscriptions = listener, subscriptions
    connected = true
end

local function OpenHouse()
    if not houseOpen then
        houseOpen = true
        addon.Listings.SetActive(true)
        addon.QueryPace.SetActive(true, function()
            if queuedSearch then TryQueuedSearch(); return end
            if pendingPurchase or verifying or quote or recheck then return end
            if addon.BrowseScanner then addon.BrowseScanner.Wake() end
            addon.Listings.Wake()
        end)
    end
    for _, name in ipairs(HOUSE_EVENTS) do events:RegisterEvent(name) end
    ConnectAuctionator()
    EnsureTab()
    Refresh()
end

events:SetScript("OnEvent", function(_, event, arg, success)
    if (pendingPurchase or verifying or quote or recheck) and event ~= "ITEM_DATA_LOAD_RESULT"
        and event ~= "GET_ITEM_INFO_RECEIVED" then
        Trace("event", { event = event, arg1 = arg, arg2 = success })
    end
    if event == "ADDON_LOADED" and arg == addonName then
        local deSaved = addon.Disenchant.Initialize(ProfitMasterDisenchantDB)
        if deSaved then ProfitMasterDisenchantDB = deSaved end
        local debugSaved = addon.Diagnostics.Initialize(ProfitMasterDebugDB)
        if debugSaved then ProfitMasterDebugDB = debugSaved end
        local saved = addon.History.Initialize(ProfitMasterDB)
        if saved then ProfitMasterDB = saved end
        addon.InitializeProfitSettings(saved)
        addon.Listings.Initialize(saved, function(candidate, prepared)
            if selectedKey or IsBusy() or not houseOpen or not prepared then return end
            for _, deal in ipairs(candidates) do
                if deal == candidate then
                    for _, field in ipairs({ "link", "quantity", "cost", "vendor", "profit", "disenchant", "deNet", "deGross",
                        "available", "availablePartial" }) do deal[field] = prepared[field] end
                    deal.display = prepared.link
                    addon.SortDeals(candidates)
                    Refresh()
                    return
                end
            end
        end)
        if addon.Settings then addon.Settings.Initialize(saved) end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if addon.OwnedAuctions then addon.OwnedAuctions.Initialize() end
        ConnectAuctionator()
        if addon.BagMarkers then
            addon.BagMarkers.Initialize()
            addon.BagMarkers.SetActive(true)
        end
        if addon.Settings then addon.Settings.CreateMinimapButton() end
        events:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "AUCTION_HOUSE_SHOW" then
        OpenHouse()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and arg == Enum.PlayerInteractionType.Auctioneer then
        OpenHouse()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" and houseOpen then
        replicateGeneration = replicateGeneration + 1
        -- The provider may dispatch its first progress callback before this
        -- frame receives the same native event. Keep that initial token aligned.
        if scanWork and scanWork.receiving and not scanWork.isBrowse then
            scanWork.replicateCount, scanWork.replicateGeneration = ReplicateCount(), replicateGeneration
        end
    elseif event == "AUCTION_HOUSE_CLOSED" and houseOpen then
        addon.Listings.SetActive(false)
        addon.QueryPace.SetActive(false)
        if addon.BrowseScanner then addon.BrowseScanner.Stop() end
        StopScanWork()
        if scanBusy then ScanProgress(0, "Scan stopped - Auction House closed") end
        houseOpen, scanBusy = false, false
        scanStartedAt = nil
        ClearLive()
        for _, name in ipairs(HOUSE_EVENTS) do events:UnregisterEvent(name) end
        if connected and Auctionator.EventBus.Unregister then
            Auctionator.EventBus:Unregister(auctionListener, auctionSubscriptions)
            connected, auctionListener, auctionSubscriptions = false, nil, nil
        end
        -- Release temporary listings and per-scan caches. Saved history and the
        -- bounded diagnostic summaries remain available when manually requested.
        candidates, excluded, liveValued, purchased = {}, {}, {}, {}
        lastScanAt, scanCoverage = nil, nil
        addon.Disenchant.ResetCache()
        if window then
            for _, row in ipairs(window.rows) do row.deal = nil end
        end
        if window then window:Hide() end
        Status("Open an Auction House to scan or buy.")
        Refresh()
    elseif (event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED") and onItemData then
        onItemData(arg, success, event)
    elseif (event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED")
        and not selectedCommodity and SameKey(selectedKey, arg) then
        if verifying and not recheck and not queuedSearch then StampPriceCheck("results") end
        ReadLive()
    elseif (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED")
        and selectedCommodity and selectedKey and not (issecretvalue and issecretvalue(arg))
        and arg == selectedKey.itemID then
        if verifying and not recheck and not queuedSearch then StampPriceCheck("results") end
        ReadCommodityLive()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if queuedSearch then TryQueuedSearch()
        elseif recheck then TryRecheck() end
        if quote then UpdateQuote() end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
        if quote then UpdateQuote() end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        ConfirmCommodity(arg, success)
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" and commodityPurchase and commodityPurchase.phase == "quote" then
        CancelPurchase("Commodity quote unavailable. No purchase confirmed.", true)
    elseif event == "COMMODITY_PURCHASE_FAILED" and commodityPurchase then
        CancelPurchase("Commodity purchase failed. No purchase confirmed.", true)
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and commodityPurchase and commodityPurchase.phase == "confirming" then
        Trace("purchase_success", { commodity = true })
        local deal = commodityPurchase.deal
        commodityPurchase = nil
        for _, name in ipairs(COMMODITY_EVENTS) do events:UnregisterEvent(name) end
        events:UnregisterEvent("UI_ERROR_MESSAGE")
        pendingPurchase, pendingDeal = nil, nil
        recheck, verifying = { deal = deal, deadline = time() + 15 }, true
        StaticPopup_Hide(COMMODITY_DIALOG)
        events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        Status("Commodity purchase confirmed. Checking remaining stock at the same price...")
        QueueRecheck("refresh")
        Refresh()
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" and not selectedCommodity and pendingPurchase == arg then
        Trace("purchase_success", { commodity = false })
        purchased[arg] = true
        if pendingError then
            CancelPurchase("Purchase confirmed after an internal auction error. Item remains removed; scan again for fresh stock.")
            return
        end
        if batchBuy then
            batchBuy.bought = batchBuy.bought + 1
            batchBuy.remaining = batchBuy.remaining - 1
        end
        events:UnregisterEvent("UI_ERROR_MESSAGE")
        recheck = { deal = pendingDeal, deadline = time() + 15, cached = true }
        pendingPurchase, pendingDeal, quote = nil, nil, nil
        verifying = true
        StaticPopup_Hide(BUY_DIALOG)
        events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        Status("Purchase confirmed. Checking for another auction at the same price...")
        QueueRecheck("cached")
        Refresh()
    elseif event == "UI_ERROR_MESSAGE" and pendingPurchase
        and not (issecretvalue and issecretvalue(success))
        and type(success) == "string" and success == ERR_AUCTION_DATABASE_ERROR then
        if not selectedCommodity then AwaitPurchaseOutcome()
        else CancelPurchase("Internal auction error. No purchase confirmed.", true) end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" and selectedKey then
        if recheck then
            CancelPurchase("Purchase confirmed. Stock recheck failed; unable to verify. Item kept.")
        elseif pendingError and pendingPurchase then
            Trace("purchase_error_while_uncertain", { error = arg })
        elseif pendingPurchase and not selectedCommodity and not (issecretvalue and issecretvalue(arg))
            and arg == Enum.AuctionHouseError.DatabaseError then
            AwaitPurchaseOutcome()
        else
            CancelPurchase("Auction House rejected the request. No purchase confirmed.", pendingPurchase ~= nil)
        end
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN")
        and (pendingPurchase or verifying or quote) then
        local name = not (issecretvalue and issecretvalue(arg)) and type(arg) == "string" and arg or "unknown addon"
        local action = not (issecretvalue and issecretvalue(success)) and type(success) == "string" and success or "unknown action"
        local context = recheck and "Purchase confirmed; stock recheck blocked: " or "Client blocked "
        CancelPurchase(context .. action .. " (" .. name .. "). Check mail/gold; /reload before retrying.",
            pendingPurchase ~= nil)
    end
end)
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
    events:RegisterEvent(event)
end

SlashCmdList["PROFITMASTER"] = function(input)
    local command = type(input) == "string" and input:lower():match("^%s*(.-)%s*$") or ""
    if command == "log" then addon.Diagnostics.Show()
    elseif command == "quick" then ShowWindow(); StartQuickScan()
    elseif command == "settings" then addon.Settings.Toggle()
    elseif command == "debug on" or command == "debug off" then
        addon.ChangeDebug(command == "debug on")
    else ShowWindow() end
end
SLASH_PROFITMASTER1 = "/profitmaster"
SLASH_PROFITMASTER2 = "/pmaster"
