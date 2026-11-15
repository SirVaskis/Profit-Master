-- Run actual UI/purchase handlers under the existing offline native-AH harness.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[
local function CheckFastFlows()
    local beforeChecks = checks
    function methods:SetClampedToScreen(value) self.clamped = value end
    local isolated, preferences = {}, { version = 1 }
    assert(loadfile("addons/ProfitMaster/Listings.lua"))("ProfitMaster", isolated)
    isolated.Listings.Initialize(preferences)
    check(isolated.Listings.Enabled() and isolated.Listings.OneClick(), "new preparation preferences initialize enabled")
    isolated.Listings.SetEnabled(false)
    isolated.Listings.SetOneClick(false)
    isolated.Listings.Initialize(preferences)
    check(not isolated.Listings.Enabled() and not isolated.Listings.OneClick(), "explicit false preferences survive initialization")
    local future = { version = 99, marker = "preserved" }
    isolated.Listings.Initialize(future)
    check(not isolated.Listings.Enabled() and future.prepareListings == nil and future.marker == "preserved",
        "unsupported saved schemas are preserved and disable preparation")
    local function emit(name, arg)
        local listeners = {}
        for _, frame in ipairs(frames) do
            if frame.events[name] then listeners[#listeners + 1] = frame end
        end
        for _, frame in ipairs(listeners) do frame.scripts.OnEvent(frame, name, arg) end
    end
    local function queryCount() return queries + exactQueries end
    local function reset(second)
        event("AUCTION_HOUSE_CLOSED")
        runImmediate()
        now = now + 120
        commodity, full, throttle, keyInfoAvailable = false, true, true, true
        addon.Listings.SetEnabled(false)
        addon.Listings.SetOneClick(true)
        addon.Disenchant.SetEnabled(false)
        assert(addon.SetMinimumProfit(3))
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
        values["item:56001"], values["item:56002"] = 100, 100
        local data = { scanned(56001, "item:56001", 2, 100) }
        if second then data[2] = scanned(56002, "item:56002", 1, 60) end
        listener:ReceiveEvent("complete", data)
        runImmediate()
        results = { listing(56011, "item:56001", 1, 50), listing(56012, "item:56001", 1, 50) }
    end
    local function prepare()
        local before = queryCount()
        addon.ChangePrepareListings(true)
        check(queryCount() == before + 1, "idle listing preparation dispatches exactly one item search")
        emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56001))
        runImmediate()
        check(window.rows[1].action.text == "Buy 1", "prepared rows clearly identify a spending click")
    end
    local function rowClick(row)
        hardwareClick = true
        click(row.action)
        hardwareClick = false
    end
    reset()
    local beforeBids = bidAttempts
    prepare()
    check(bidAttempts == beforeBids and not popup.shown, "background search callbacks never buy or open a purchase dialog")
    local before = queryCount()
    local beforeReads = resultReads
    rowClick(window.rows[1])
    check(bidAttempts == beforeBids + 1 and bids[#bids][1] == 56011 and bids[#bids][2] == 50
        and queryCount() == before, "prepared row click buys exactly one verified auction with zero additional queries")
    check(resultReads == beforeReads + 2, "stable result positions need only two native reads for the click-time checks")
    check(not popup.shown, "pending one-click purchase does not leave its confirmation open")
    addon.Settings.Toggle()
    local panel
    for _, frame in ipairs(frames) do if frame.minimumProfit and frame ~= window then panel = frame end end
    check(panel.prepareListings.checked and panel.oneClickPrepared.checked
        and not panel.prepareListings.enabled and not panel.oneClickPrepared.enabled,
        "purchase in progress locks both settings while reflecting their saved values")
    addon.Settings.Toggle()
    runImmediate()
    check(bidAttempts == beforeBids + 1, "timers cannot buy another copy")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 56011)
    runImmediate()
    check(popup.shown and popup.data.auctionID == 56012 and popup:GetEditBox():GetText() == "1"
        and queryCount() == before, "acknowledged purchase prepares a different known ID without a query or automatic bid")
    confirmPopup()
    check(bidAttempts == beforeBids + 2 and bids[#bids][1] == 56012, "the next copy requires another player click")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 56012)
    runImmediate()

    reset()
    prepare()
    addon.ChangeOneClickPrepared(false)
    beforeBids, before = bidAttempts, queryCount()
    rowClick(window.rows[1])
    check(popup.shown and bidAttempts == beforeBids and queryCount() == before,
        "confirmation preference opens a prepared quote immediately without spending")
    popup:GetEditBox():SetText("1")
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 56011)
    runImmediate()
    check(not popup.shown and window.rows[1].action.enabled, "finishing a one-copy goal releases the row")
    addon.ChangeOneClickPrepared(true)
    before = queryCount()
    rowClick(window.rows[1])
    check(queryCount() == before and bids[#bids][1] == 56012, "remaining known auction is reusable after a completed goal without another query")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 56012)
    runImmediate()
    cancelPopup()

    reset()
    prepare()
    results[1].buyoutAmount, results[2].buyoutAmount = 55, 55
    beforeBids, before = bidAttempts, queryCount()
    rowClick(window.rows[1])
    check(bidAttempts == beforeBids and queryCount() == before + 1 and not popup.shown,
        "changed native price falls back to a fresh check instead of buying at a new price")
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56001))
    check(popup.shown and popup.data.cost == 55 and bidAttempts == beforeBids,
        "a changed price needs explicit confirmation even with one-click enabled")
    cancelPopup()

    reset()
    prepare()
    results = {}
    beforeBids, before = bidAttempts, queryCount()
    rowClick(window.rows[1])
    check(queryCount() == before + 1 and bidAttempts == beforeBids,
        "evicted native results cannot authorize buying from our retained copy")
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56001))
    check(not popup.shown and bidAttempts == beforeBids, "an empty fresh book cannot authorize a purchase")

    reset()
    prepare()
    now = now + 61
    beforeBids, before = bidAttempts, queryCount()
    rowClick(window.rows[1])
    check(queryCount() == before + 1 and bidAttempts == beforeBids, "prepared listings expire after sixty seconds")
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56001))
    cancelPopup()

    reset()
    prepare()
    local originalRead, clickReads = C_AuctionHouse.GetItemSearchResultInfo, 0
    C_AuctionHouse.GetItemSearchResultInfo = function(key, index)
        clickReads = clickReads + 1
        if clickReads == 2 then results[1].buyoutAmount = 80 end
        return originalRead(key, index)
    end
    beforeBids = bidAttempts
    rowClick(window.rows[1])
    C_AuctionHouse.GetItemSearchResultInfo = originalRead
    check(bidAttempts == beforeBids and not popup.shown, "a price changed between cache validation and bid validation still cannot spend gold")

    reset()
    prepare()
    results[1], results[2] = results[2], results[1]
    beforeBids = bidAttempts
    rowClick(window.rows[1])
    check(bidAttempts == beforeBids + 1 and bids[#bids][1] == 56011,
        "a moved result position finds the same auction ID instead of buying the new occupant")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 56011)
    runImmediate()
    cancelPopup()

    reset()
    addon.ChangePrepareListings(true)
    beforeBids, before = bidAttempts, queryCount()
    rowClick(window.rows[1])
    check(queryCount() == before and bidAttempts == beforeBids, "clicking an in-flight preparation joins that query")
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56001))
    check(popup.shown and bidAttempts == beforeBids, "a listing that was unprepared at click time still needs confirmation")
    cancelPopup()

    reset(true)
    addon.ChangePrepareListings(true)
    throttle = false
    before = queryCount()
    rowClick(window.rows[2])
    check(queryCount() == before, "foreground selection waits for the native channel without duplicating preparation")
    throttle = true
    emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(queryCount() == before + 1, "the foreground item dispatches first when the channel is released")
    results = { listing(56021, "item:56002", 1, 60) }
    emit("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(56002))
    check(popup.shown and popup.data.link == "item:56002", "a background result cannot replace the selected item")
    cancelPopup()

    reset()
    throttle = false
    rowClick(window.rows[1])
    before = queryCount()
    keyInfoAvailable, throttle = false, true
    emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(queryCount() == before and not popup.shown and window.status.text:find("became unavailable", 1, true),
        "metadata is rechecked at dispatch instead of silently losing a queued search")
    keyInfoAvailable = true

    reset()
    local preparationKeys, originalSend = {}, C_AuctionHouse.SendSellSearchQuery
    C_AuctionHouse.SendSellSearchQuery = function(key)
        preparationKeys[#preparationKeys + 1] = key
        originalSend(key)
    end
    local many = {}
    for id = 57001, 57025 do
        values["item:" .. id] = 100
        many[#many + 1] = scanned(id, "item:" .. id, 1, 50)
    end
    listener:ReceiveEvent("complete", many)
    runImmediate()
    beforeBids = bidAttempts
    addon.ChangePrepareListings(true)
    for index = 1, 20 do
        local key = preparationKeys[index]
        check(key ~= nil, "each of the bounded top twenty targets is prepared")
        results = { listing(90000 + key.itemID, "item:" .. key.itemID, 1, 50) }
        now = now + 1
        emit("ITEM_SEARCH_RESULTS_UPDATED", key)
        runImmediate()
        emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        now = now + 1
        addon.Listings.Wake()
        runImmediate()
    end
    check(#preparationKeys == 20 and bidAttempts == beforeBids, "twenty prepared rows stop without polling, extra targets, or purchases")
    C_AuctionHouse.SendSellSearchQuery = originalSend

    reset(true)
    ProfitMasterDB.quickItems = {}
    addon.History.RememberOpportunity(window.rows[1].deal)
    local quickQueries, quickKeys, browseRows = 0, nil, {}
    C_AuctionHouse.SearchForItemKeys = function(keys)
        quickQueries, quickKeys, throttle = quickQueries + 1, keys, false
    end
    C_AuctionHouse.GetBrowseResults = function() return browseRows end
    C_AuctionHouse.HasFullBrowseResults = function() return true end
    click(window.quick)
    check(quickQueries == 1 and #quickKeys == 1 and quickKeys[1].itemID == 56001,
        "Quick scan queries learned keys only")
    browseRows = { { itemKey = C_AuctionHouse.MakeItemKey(56001), totalQuantity = 2, minPrice = 60 } }
    emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    runImmediate()
    local watched, other
    for _, row in ipairs(window.rows) do
        if row.deal and row.deal.itemID == 56001 then watched = row.deal end
        if row.deal and row.deal.itemID == 56002 then other = row.deal end
    end
    check(watched and watched.cost == 60 and other and other.cost == 60,
        "Quick scan refreshes a watched price and preserves candidates outside its coverage")
    check(addon.LastScanProfile.source == "quick" and window.status.text:find("known keys only", 1, true),
        "watchlist coverage is distinguished from full scans in UI and diagnostics")
    throttle = true
    click(window.quick)
    browseRows = {}
    emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    throttle = true
    emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    -- The pacing gap is satisfied by this deterministic mock clock.
    now = now + 1
    addon.BrowseScanner.Wake()
    emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    runImmediate()
    check(window.rows[1].deal and window.rows[2].deal and window.status.text:find("no rows", 1, true),
        "uncertain empty watchlist replies preserve existing watched and unwatched candidates")
    event("AUCTION_HOUSE_CLOSED")
    drain()
    for _, frame in ipairs(frames) do
        check(not frame.scripts.OnUpdate, "new features introduce no per-frame work")
    end
    for _, timer in ipairs(timers) do check(timer.cancelled, "closing cancels preparation and pacing timers") end
    print("Profit Master fast flows: " .. (checks - beforeChecks) .. " assertions passed (Lua 5.1).")
end
CheckFastFlows()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterFastFlows"))()
