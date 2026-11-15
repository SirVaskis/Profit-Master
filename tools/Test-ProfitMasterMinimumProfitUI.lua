-- Extend the production integration harness; no game interaction or real purchases.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[

local function CheckMinimumProfitUI()
    local minimumChecks = checks
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    commodity, full, throttle = false, true, true
    addon.Disenchant.SetEnabled(false)
    local field = window.minimumProfit
    local function enter(text)
        field:SetFocus()
        field:SetText(text)
        field.scripts.OnEnterPressed(field)
    end
    local function shown(id)
        for _, row in ipairs(window.rows) do
            if row.deal and row.deal.itemID == id then return row.deal end
        end
    end
    local function publish(rows)
        listener:ReceiveEvent("start")
        listener:ReceiveEvent("complete", rows)
        runImmediate()
    end
    local function fresh(id, cost)
        local link = "item:" .. id
        values[link] = 100
        return scanned(id, link, 1, cost)
    end
    local function nativeRequests()
        return queries + exactQueries + refreshes + more + scans + browseScans
    end

    check(addon.GetMinimumProfit() == 3 and ProfitMasterDB.minimumProfit == 3 and field:GetText() == "3",
        "new saved settings and the visible minimum-profit field default to three copper")
    check(field.template == "InputBoxTemplate" and field.numeric and field.maxLetters == 9 and field.autoFocus == false,
        "minimum-profit editing uses a native numeric input without stealing initial focus")
    check(field.enabled and not field:HasFocus(), "idle minimum-profit editing is available without keyboard focus")

    local low, boundary = fresh(49201, 91), fresh(49202, 90)
    publish({ low, boundary })
    local beforeRequests, beforeBids = nativeRequests(), bidAttempts
    field:SetFocus()
    field:SetText("10")
    SlashCmdList.PROFITMASTER("debug off")
    check(field:GetText() == "10" and addon.GetMinimumProfit() == 3 and shown(49201),
        "uncommitted focused text survives refresh without changing eligibility")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and ProfitMasterDB.minimumProfit == 10
        and field:GetText() == "10" and not field:HasFocus(), "Enter commits and saves whole copper then releases focus")
    check(not shown(49201) and shown(49202) and shown(49202).profit == 10 and not window.rows[2].deal,
        "raising minimum hides nine-copper profit immediately and retains the exact ten-copper boundary")
    check(window.heading.text:find("min 10c", 1, true)
        and window.progress.text.text:find("1 candidates", 1, true), "cutoff and retained count update after a completed scan")
    check(addon.InitializeProfitSettings(ProfitMasterDB) and addon.GetMinimumProfit() == 10,
        "reinitializing from saved data retains the user's minimum")

    for _, bad in ipairs({ "", "-1", "1.5", "abc", "1000000000" }) do
        enter(bad)
        check(addon.GetMinimumProfit() == 10 and ProfitMasterDB.minimumProfit == 10 and field:GetText() == "10",
            "invalid input restores the committed setting: " .. bad)
    end
    field:SetFocus()
    field:SetText("20")
    field.scripts.OnEscapePressed(field)
    check(field:GetText() == "10" and addon.GetMinimumProfit() == 10 and not field:HasFocus(),
        "Escape restores the saved value without committing or retaining focus")
    field:SetFocus()
    field:SetText("11")
    field:ClearFocus()
    check(addon.GetMinimumProfit() == 11 and ProfitMasterDB.minimumProfit == 11 and not window.rows[1].deal,
        "native focus loss commits once and filters current results")
    enter("10")
    check(window.status.text:find("Run a fresh scan", 1, true) and not window.rows[1].deal,
        "lowering the setting requests a fresh scan instead of inventing previously rejected results")
    check(nativeRequests() == beforeRequests and bidAttempts == beforeBids,
        "typing, committing, rejecting and canceling minimum-profit input sends no queries or bids")
    publish({ low, boundary })
    check(shown(49202) and not shown(49201), "a fresh scan applies the saved minimum")
    enter("0")
    check(addon.GetMinimumProfit() == 0 and ProfitMasterDB.minimumProfit == 0, "zero is an accepted minimum")
    enter("999999999")
    check(addon.GetMinimumProfit() == 999999999 and not window.rows[1].deal, "the nine-digit upper boundary is accepted")
    enter("3")

    canFullScan = true
    click(window.scan)
    check(not window.scan.enabled and field.enabled, "a manually started full scan leaves minimum editing available")
    enter("10")
    check(addon.GetMinimumProfit() == 10 and not window.scan.enabled, "committing during manual server wait preserves that scan")
    listener:ReceiveEvent("complete", { low, boundary })
    runImmediate()
    check(shown(49202) and not shown(49201), "manual scan valuation uses the threshold committed during server wait")
    enter("3")

    -- A private best entry must be pruned, not merely hidden for one publication.
    local stream = { { itemKey = C_AuctionHouse.MakeItemKey(49201), totalQuantity = 1, minPrice = 91 },
        { itemKey = C_AuctionHouse.MakeItemKey(49202), totalQuantity = 1, minPrice = 90 } }
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = stream
    listener:ReceiveEvent("browse_progress", 0.2)
    check(shown(49201) and field.enabled and not window.scan.enabled,
        "the minimum remains editable during an automatic provider scan")
    beforeRequests, beforeBids = nativeRequests(), bidAttempts
    enter("10")
    check(not shown(49201) and shown(49202) and not window.scan.enabled,
        "raising the threshold immediately filters streamed candidates without stopping the scan")
    enter("3")
    fresh(49203, 80)
    stream[3] = { itemKey = C_AuctionHouse.MakeItemKey(49203), totalQuantity = 1, minPrice = 80 }
    now = now + 0.3
    listener:ReceiveEvent("browse_progress", 0.5)
    check(shown(49203) and shown(49202) and not shown(49201),
        "a later publication after lowering cannot resurrect a pruned private best result")
    check(nativeRequests() == beforeRequests and bidAttempts == beforeBids,
        "mid-scan threshold changes and local publication do not start an automatic scan or purchase")
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", stream)
    runImmediate()
    check(window.scan.enabled and not shown(49201), "completion cannot restore a private result pruned during the scan")

    -- Force multiple CPU slices, then change the cutoff before later rows run.
    local budgetRows, clock = {}, now
    for id = 49301, 49320 do budgetRows[#budgetRows + 1] = fresh(id, id % 2 == 0 and 90 or 91) end
    local originalInfo, originalTime = C_Item.GetItemInfo, GetTimePreciseSec
    C_Item.GetItemInfo = function(reference) clock = clock + 0.001; return originalInfo(reference) end
    GetTimePreciseSec = function() return clock end
    listener:ReceiveEvent("complete", budgetRows)
    check(not window.scan.enabled and field.enabled and window.rows[1].deal,
        "the numeric control stays available between cooperative valuation slices")
    enter("10")
    runImmediate()
    check(window.scan.enabled, "changing the cutoff does not interrupt scheduled scan completion")
    for _, row in ipairs(window.rows) do
        check(not row.deal or row.deal.profit >= 10, "later CPU slices and final publication respect the new minimum")
    end
    C_Item.GetItemInfo, GetTimePreciseSec = originalInfo, originalTime

    -- A delayed metadata callback must use the current threshold as well.
    enter("3")
    values["item:49401"], values["item:49402"] = nil, nil
    listener:ReceiveEvent("complete", { low, scanned(49401, "item:49401", 1, 91), scanned(49402, "item:49402", 1, 90) })
    check(shown(49201) and not window.scan.enabled and eventFrame.events.ITEM_DATA_LOAD_RESULT and field.enabled,
        "minimum editing remains available while vendor metadata is outstanding")
    enter("10")
    values["item:49401"], values["item:49402"] = 100, 100
    event("ITEM_DATA_LOAD_RESULT", 49401, true)
    event("ITEM_DATA_LOAD_RESULT", 49402, true)
    runImmediate()
    check(window.scan.enabled and shown(49402) and not shown(49401) and not shown(49201),
        "metadata previews, retry valuation and final publication cannot restore under-minimum offers")

    -- A partially received live search owns the setting even without an open quote.
    publish({ boundary })
    results, full = {}, false
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49202))
    check(not popup.shown and findButton("More listings") and not field.enabled,
        "idle pagination retains the minimum-profit lock while a selected search remains active")
    field:SetText("11")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and field:GetText() == "10",
        "a selected search rejects stale commits even between verification callbacks")
    timeout()
    full = true
    check(field.enabled, "abandoning the partial price check releases the setting")

    -- Even a stale callback cannot change the cutoff while a quote owns the UI.
    publish({ boundary })
    results = { listing(492201, "item:49202", 1, 90) }
    click(window.rows[1].action)
    check(not field.enabled, "minimum editing locks as soon as live verification starts")
    field:SetText("11")
    field.scripts.OnEditFocusLost(field)
    check(addon.GetMinimumProfit() == 10 and field:GetText() == "10", "stale focus-loss commit is rejected during verification")
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49202))
    check(popup.shown and not field.enabled, "an open exact-price quote keeps minimum editing locked")
    field:SetText("11")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and popup.shown and field:GetText() == "10",
        "stale Enter cannot alter an already authorized live quote")
    confirmPopup()
    check(not field.enabled, "pending purchase keeps minimum editing locked")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 492201)
    check(not field.enabled, "confirmed purchase stock recheck keeps minimum editing locked")
    field:SetText("11")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and field:GetText() == "10", "recheck rejects an already queued text commit")
    results = { listing(492202, "item:49202", 1, 90) }
    runImmediate()
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49202))
    check(not popup.shown and field.enabled, "stock verification releases the minimum-profit control")

    local oldCommodityCount, oldCommodityInfo = C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetCommoditySearchResultInfo
    C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
    C_AuctionHouse.GetCommoditySearchResultInfo = function()
        return { auctionID = 492203, itemID = 200001, quantity = 2, unitPrice = 90, numOwnerItems = 0 }
    end
    commodity = true
    publish({ fresh(200001, 90) })
    click(window.rows[1].action)
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    check(popup.shown and popup.which == "PROFITMASTER_CONFIRM_COMMODITY" and not field.enabled,
        "commodity quantity quotes also lock the minimum-profit field")
    field:SetText("11")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and field:GetText() == "10" and popup.shown,
        "stale text cannot change a live commodity authorization")
    cancelPopup()
    commodity = false
    C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetCommoditySearchResultInfo = oldCommodityCount, oldCommodityInfo

    -- DE profit may qualify, but vendor fallback must meet the configured cutoff.
    local oldEstimate = addon.Disenchant.Estimate
    addon.Disenchant.Estimate = function(link)
        if link == "item:49501" or link == "item:49502" or link == "item:49503" then return 153, 180 end
        return oldEstimate(link)
    end
    fresh(49501, 91); fresh(49502, 90)
    addon.Disenchant.SetEnabled(true)
    publish({ scanned(49501, "item:49501", 1, 91), scanned(49502, "item:49502", 1, 90) })
    check(shown(49501).disenchant and shown(49502).disenchant, "both expected-DE estimates qualify before fallback")
    window.disenchant:SetChecked(false)
    click(window.disenchant)
    check(not shown(49501) and shown(49502) and not shown(49502).disenchant and shown(49502).profit == 10,
        "disabling DE drops nine-copper vendor fallback and keeps exact configured minimum")
    enter("0")
    addon.Disenchant.SetEnabled(true)
    publish({ fresh(49503, 100) })
    check(shown(49503).disenchant and shown(49503).profit == 53, "DE proceeds may qualify an otherwise break-even vendor offer")
    window.disenchant:SetChecked(false)
    click(window.disenchant)
    check(not window.rows[1].deal, "a zero configured minimum never retains break-even vendor fallback after DE is disabled")
    addon.Disenchant.Estimate = oldEstimate

    for _, frame in ipairs(frames) do
        check(not frame.scripts.OnUpdate and not frame.scripts.OnKeyDown and not frame.scripts.OnKeyUp,
            "minimum editing adds neither polling nor global keyboard capture")
    end
    enter("3")
    print("Profit Master minimum-profit UI: " .. (checks - minimumChecks) .. " assertions passed (Lua 5.1).")
end
CheckMinimumProfitUI()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterMinimumProfitUI"))()
