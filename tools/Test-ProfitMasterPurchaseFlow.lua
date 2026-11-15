-- Regression coverage for production purchase event ordering; no game interaction.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[

local function CheckPurchaseFlow()
    local flowChecks = checks
    local oldMakeKey, oldSell = C_AuctionHouse.MakeItemKey, C_AuctionHouse.SendSellSearchQuery
    local oldItemMore = C_AuctionHouse.RequestMoreItemSearchResults
    local oldCommodityCount, oldCommodityInfo = C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetCommoditySearchResultInfo
    local oldCommodityMore, oldCommodityRefresh = C_AuctionHouse.RequestMoreCommoditySearchResults, C_AuctionHouse.RefreshCommoditySearchResults
    local oldStart, oldConfirm = C_AuctionHouse.StartCommoditiesPurchase, C_AuctionHouse.ConfirmCommoditiesPurchase
    local function reset()
        event("AUCTION_HOUSE_CLOSED")
        runImmediate()
        commodity, full, throttle, keyInfoAvailable = false, true, true, true
        addon.Disenchant.SetEnabled(false)
        assert(addon.SetMinimumProfit(3))
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
    end
    local function publish(id, cost, exactKey)
        values["item:" .. id] = 100
        if exactKey then
            listener:ReceiveEvent("browse_complete", { { itemKey = exactKey, totalQuantity = 2, minPrice = cost or 50 } })
        else listener:ReceiveEvent("complete", { scanned(id, "item:" .. id, 1, cost or 50) }) end
        runImmediate()
    end
    local function itemQuote(id, auctionID, count)
        reset()
        publish(id)
        results = { listing(auctionID, "item:" .. id, count or 1, 50) }
        click(window.rows[1].action)
        event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(id))
        check(popup.shown, "item fixture opens a verified exact-price confirmation")
    end
    local function itemRecheck(id, auctionID)
        itemQuote(id, auctionID)
        confirmPopup()
        event("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
        runImmediate()
        results, full = {}, false
        event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(id))
    end

    -- Sell-search item keys require wildcard level/suffix, not MakeItemKey's display metadata.
    reset()
    local madeKey, sellKey
    C_AuctionHouse.MakeItemKey = function(id)
        madeKey = { itemID = id, itemLevel = 37, itemSuffix = 23, battlePetSpeciesID = 7 }
        return madeKey
    end
    C_AuctionHouse.SendSellSearchQuery = function(key) queries = queries + 1; sellKey = key end
    publish(53001)
    results = { listing(530101, "item:53001", 1, 50) }
    click(window.rows[1].action)
    check(sellKey and sellKey ~= madeKey and sellKey.itemID == 53001 and sellKey.itemLevel == 0
        and sellKey.itemSuffix == 0 and sellKey.battlePetSpeciesID == 7,
        "replicate candidate sell-search copies the ID/pet and normalizes level and suffix")
    check(madeKey.itemLevel == 37 and madeKey.itemSuffix == 23,
        "normalizing the selected sell-search key never mutates native MakeItemKey metadata")
    event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 53001, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 7 })
    check(popup.shown and popup.data.auctionID == 530101, "normalized result events match the selected sell-search key")
    cancelPopup()
    C_AuctionHouse.MakeItemKey, C_AuctionHouse.SendSellSearchQuery = oldMakeKey, oldSell
    reset()
    local exact = { itemID = 53002, itemLevel = 42, itemSuffix = 17, battlePetSpeciesID = 0 }
    publish(53002, 50, exact)
    results = { listing(530102, "item:53002", 1, 50) }
    click(window.rows[1].action)
    check(queriedKey == exact and exact.itemLevel == 42 and exact.itemSuffix == 17,
        "browse candidates preserve their exact key and continue using SendSearchQuery")
    event("ITEM_SEARCH_RESULTS_UPDATED", exact)
    check(popup.shown, "exact browse-key result still opens its quote")
    cancelPopup()

    -- Search readiness never gates an already verified individual purchase.
    reset()
    publish(53101)
    results = { listing(531101, "item:53101", 1, 50), listing(531102, "item:53101", 1, 50) }
    click(window.rows[1].action)
    local beforeBids, beforeQueries = bidAttempts, queries + exactQueries
    throttle = false
    event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(53101))
    check(popup.shown and popup:GetButton1().enabled and popup:GetEditBox():GetText() == "2",
        "an item result arriving before search readiness opens an actionable verified confirmation")
    check(bidAttempts == beforeBids and queries + exactQueries == beforeQueries,
        "preparing an actionable confirmation never submits its purchase automatically")
    popup:GetEditBox():SetText("0")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(popup.shown and not popup:GetButton1().enabled and bidAttempts == beforeBids,
        "search readiness never enables an invalid item quantity or purchases automatically")
    popup:GetEditBox():SetText("2")
    check(popup:GetButton1().enabled, "a valid verified quantity enables without a new search")
    throttle = false
    event("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    check(popup.shown and popup:GetButton1().enabled, "a sent search message does not disable a verified item confirmation")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(popup:GetButton1().enabled and queries + exactQueries == beforeQueries and bidAttempts == beforeBids,
        "search-ready events preserve item confirmation without a query or bid")
    local firstID = popup.data.auctionID
    confirmPopup()
    throttle = false
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", firstID)
    results = { listing(firstID == 531101 and 531102 or 531101, "item:53101", 1, 50) }
    runImmediate()
    check(popup.shown and popup:GetButton1().enabled and bidAttempts == beforeBids + 1,
        "first success prepares an actionable cached next-copy quote while search is throttled")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(popup.shown and popup:GetEditBox():GetText() == "1" and popup:GetButton1().enabled,
        "the next same-price confirmation preserves the remaining goal")
    throttle = false
    event("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    check(popup.shown and popup:GetButton1().enabled and bidAttempts == beforeBids + 1,
        "a search message neither blocks nor submits the verified second copy")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(bidAttempts == beforeBids + 1 and popup.shown, "second-copy readiness still requires another hardware confirmation")
    local secondID = popup.data.auctionID
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", secondID)
    runImmediate()
    results = {}
    event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(53101))
    check(bidAttempts == beforeBids + 2 and not popup.shown and not window.rows[1].deal,
        "two hardware confirmations complete exactly two copies and remove verified exhausted stock")

    -- Pagination may report already-complete results without sending a result event.
    local pageCalls = 0
    itemRecheck(53201, 532101)
    C_AuctionHouse.RequestMoreItemSearchResults = function()
        pageCalls = pageCalls + 1; full = true; return true
    end
    runImmediate()
    check(pageCalls == 1 and not window.rows[1].deal and not popup.shown,
        "public true from item pagination immediately rechecks complete exhausted stock")
    local callsAfterComplete = pageCalls
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    runImmediate()
    check(pageCalls == callsAfterComplete, "completed pagination cannot dispatch a duplicate page or retain a deadline")

    itemRecheck(53202, 532102)
    full = true -- Becomes complete after queueing but before dispatch.
    runImmediate()
    check(not window.rows[1].deal, "full item coverage before dispatch also finishes the current recheck without another event")

    itemRecheck(53203, 532103)
    C_AuctionHouse.RequestMoreItemSearchResults = function()
        pageCalls = pageCalls + 1
        results, full = { listing(532104, "item:53203", 1, 50) }, true
        event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(53203))
        return true
    end
    local succeeded, failure = pcall(runImmediate)
    check(succeeded and window.rows[1].deal and window.rows[1].quantity.text == 1 and not popup.shown,
        "a synchronous item page event can finish the recheck before RequestMore returns: " .. tostring(failure))

    itemRecheck(53204, 532105)
    C_AuctionHouse.RequestMoreItemSearchResults = function() pageCalls = pageCalls + 1; return "SECRET" end
    runImmediate()
    check(window.rows[1].deal and not window.rows[1].action.enabled,
        "a restricted truthy page return never pretends item coverage is complete")
    full = true
    event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(53204))
    check(not window.rows[1].deal, "a later public item result still resolves the restricted-return wait")

    reset()
    publish(53205)
    results, full = {}, false
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", oldMakeKey(53205))
    C_AuctionHouse.RequestMoreItemSearchResults = function()
        results, full = { listing(532106, "item:53205", 1, 50) }, true
        return true
    end
    click(window.more)
    check(popup.shown and popup.data.auctionID == 532106,
        "manual More listings reads an already-complete item page without waiting for a missing event")
    cancelPopup()
    C_AuctionHouse.RequestMoreItemSearchResults = oldItemMore

    -- Commodity purchases use the same context checks without a search-throttle gate.
    local commodityRows, starts, confirms, commodityPages = {}, 0, 0, 0
    C_AuctionHouse.GetNumCommoditySearchResults = function() return #commodityRows end
    C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index) return commodityRows[index] end
    C_AuctionHouse.RefreshCommoditySearchResults = function() end
    C_AuctionHouse.StartCommoditiesPurchase = function(_, quantity)
        check(hardwareClick and quantity == 2, "commodity start requires the explicit hardware-authorized quantity")
        starts = starts + 1
    end
    C_AuctionHouse.ConfirmCommoditiesPurchase = function(_, quantity)
        check(quantity == 2, "server commodity confirmation retains the authorized quantity")
        confirms = confirms + 1
    end
    local function commoditySetup(empty)
        reset()
        commodity = true
        publish(200001)
        commodityRows = empty and {} or { { auctionID = 533101, itemID = 200001, quantity = 2, unitPrice = 50, numOwnerItems = 0 } }
        click(window.rows[1].action)
    end
    commoditySetup()
    throttle = false
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    check(popup.shown and popup:GetButton1().enabled, "commodity result while search is throttled keeps an actionable quantity confirmation")
    check(popup.shown and starts == 0 and confirms == 0, "preparing commodity confirmation never starts a purchase automatically")
    popup:GetEditBox():SetText("0")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(not popup:GetButton1().enabled, "native readiness cannot enable an invalid commodity quantity")
    popup:GetEditBox():SetText("2")
    throttle = false
    event("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    check(popup:GetButton1().enabled, "search-message-sent leaves a valid commodity quantity confirmation actionable")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(popup:GetButton1().enabled and starts == 0 and confirms == 0, "commodity readiness changes only the button state")
    throttle = false
    confirmPopup()
    event("COMMODITY_PRICE_UPDATED", 50, 100)
    check(starts == 1 and confirms == 1, "one explicit commodity click authorizes its exact quote even while search is throttled")
    throttle = true
    event("COMMODITY_PURCHASE_SUCCEEDED")
    runImmediate()
    commodityRows, full = {}, false
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    C_AuctionHouse.RequestMoreCommoditySearchResults = function()
        commodityPages = commodityPages + 1; full = true; return true
    end
    runImmediate()
    check(commodityPages == 1 and not window.rows[1].deal and starts == 1,
        "complete commodity pagination ends the post-purchase stock check without another purchase or event")

    commoditySetup(true)
    full = false
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    C_AuctionHouse.RequestMoreCommoditySearchResults = function()
        commodityPages = commodityPages + 1
        commodityRows, full = { { auctionID = 533102, itemID = 200001, quantity = 2, unitPrice = 50, numOwnerItems = 0 } }, true
        event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
        return true
    end
    click(window.more)
    check(popup.shown and popup.data.available == 2 and starts == 1,
        "manual commodity More handles synchronous completion without duplicate transactions")
    cancelPopup()

    commoditySetup(true)
    full = false
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    C_AuctionHouse.RequestMoreCommoditySearchResults = function() return "SECRET" end
    click(window.more)
    check(not popup.shown and window.rows[1].deal,
        "restricted commodity page returns wait for public results instead of inventing completion")
    full = true
    event("COMMODITY_SEARCH_RESULTS_UPDATED", 200001)
    check(not window.rows[1].deal, "public commodity completion still resolves a restricted-return page")

    reset()
    C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetCommoditySearchResultInfo = oldCommodityCount, oldCommodityInfo
    C_AuctionHouse.RequestMoreCommoditySearchResults, C_AuctionHouse.RefreshCommoditySearchResults = oldCommodityMore, oldCommodityRefresh
    C_AuctionHouse.StartCommoditiesPurchase, C_AuctionHouse.ConfirmCommoditiesPurchase = oldStart, oldConfirm
    print("Profit Master purchase flow: " .. (checks - flowChecks) .. " assertions passed (Lua 5.1).")
end
CheckPurchaseFlow()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterPurchaseFlow"))()
