-- Verify that local post-purchase checks do not consume the native query channel.
-- Uses the existing offline harness; no game interaction or real purchases.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[

local function CheckPurchaseLatency()
    local latencyChecks = checks
    local originalRefresh = C_AuctionHouse.RefreshItemSearchResults
    local refreshCalls = 0
    C_AuctionHouse.RefreshItemSearchResults = function(key)
        refreshCalls = refreshCalls + 1
        originalRefresh(key)
        throttle = false -- Model the shared channel consumed by a native refresh.
    end
    local function reset()
        event("AUCTION_HOUSE_CLOSED")
        runImmediate()
        commodity, full, throttle = false, true, true
        addon.Disenchant.SetEnabled(false)
        assert(addon.SetMinimumProfit(3))
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
        values["item:55001"], values["item:55002"] = 100, 100
        listener:ReceiveEvent("complete", { scanned(55001, "item:55001", 1, 50), scanned(55002, "item:55002", 1, 60) })
        runImmediate()
    end
    local function open(rows, goal)
        reset()
        results = rows
        click(window.rows[1].action)
        event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55001))
        check(popup.shown, "latency fixture opens an exact-price item quote")
        popup:GetEditBox():SetText(tostring(goal))
    end
    local function queryCount() return queries + exactQueries end

    -- A finished one-item goal can observe another returned ID without a refresh.
    open({ listing(550101, "item:55001", 1, 50), listing(550102, "item:55001", 1, 50) }, 1)
    local bought = popup.data.auctionID
    local beforeRefresh, beforeQueries, beforeBids = refreshCalls, queryCount(), bidAttempts
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", bought)
    runImmediate()
    check(not popup.shown and refreshCalls == beforeRefresh and queryCount() == beforeQueries
        and bidAttempts == beforeBids + 1 and throttle,
        "completed single-item goal sends no background refresh when another exact auction ID is cached")
    check(window.rows[1].quantity.text == 1 and window.rows[1].action.enabled and window.rows[2].action.enabled,
        "local completion excludes the purchased ID, updates known stock and releases both item buttons")
    click(window.rows[2].action)
    check(queryCount() == beforeQueries + 1 and refreshCalls == beforeRefresh,
        "the next item's fresh verification query sends immediately without waiting behind an old stock refresh")
    results = { listing(550201, "item:55002", 1, 60) }
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55002))
    check(popup.shown and popup.data.auctionID == 550201 and bidAttempts == beforeBids + 1,
        "switching items still verifies a fresh listing and requires another hardware confirmation")
    cancelPopup()

    -- Cached known IDs can be bought immediately despite search throttling.
    open({ listing(550301, "item:55001", 1, 50), listing(550302, "item:55001", 1, 50) }, 2)
    bought = popup.data.auctionID
    beforeRefresh, beforeQueries, beforeBids = refreshCalls, queryCount(), bidAttempts
    confirmPopup()
    throttle = false
    local beforeReads = resultReads
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", bought)
    runImmediate()
    check(resultReads > beforeReads and popup.shown and popup:GetButton1().enabled
        and popup:GetEditBox():GetText() == "1", "cached getters prepare an actionable remaining-copy quote while search is throttled")
    check(refreshCalls == beforeRefresh and queryCount() == beforeQueries and bidAttempts == beforeBids + 1,
        "preparing a cached quote while busy sends neither a native request nor another bid")
    local secondID = popup.data.auctionID
    confirmPopup()
    check(bidAttempts == beforeBids + 2 and bids[#bids][1] == secondID and not throttle,
        "a hardware click buys the verified second ID without waiting for search SYSTEM_READY")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", secondID)
    runImmediate()
    check(not popup.shown and refreshCalls == beforeRefresh and bidAttempts == beforeBids + 2,
        "after the last known ID, only the missing-stock refresh waits for search readiness")
    event("AUCTION_HOUSE_CLOSED")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    runImmediate()
    check(refreshCalls == beforeRefresh and bidAttempts == beforeBids + 2,
        "closing before fallback readiness cancels the request without a later automatic bid")

    -- Grouped availability alone supplies no new auction ID; fallback remains necessary.
    open({ listing(550401, "item:55001", 10, 50) }, 1)
    beforeRefresh, beforeQueries, beforeBids = refreshCalls, queryCount(), bidAttempts
    confirmPopup()
    throttle = false
    beforeReads = resultReads
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 550401)
    runImmediate()
    check(resultReads > beforeReads and not popup.shown and refreshCalls == beforeRefresh,
        "a completed one-copy goal checks its cached group locally but waits before sending the fallback request")
    check(not window.rows[1].action.enabled and window.rows[2].action.enabled,
        "unresolved same-item stock does not block choosing another candidate")
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(refreshCalls == beforeRefresh + 1 and not throttle and queryCount() == beforeQueries,
        "missing next auction ID triggers exactly one readiness-gated native refresh")
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    runImmediate()
    check(refreshCalls == beforeRefresh + 1 and bidAttempts == beforeBids + 1,
        "repeated readiness events cannot duplicate the fallback refresh or purchase")
    results, throttle = { listing(550402, "item:55001", 8, 50) }, true
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55001))
    check(not popup.shown and window.rows[1].quantity.text == 8 and window.rows[1].action.enabled,
        "fresh grouped stock updates availability without restarting a completed goal")

    -- Choosing another item before the deferred cache pass cancels old local work.
    open({ listing(550501, "item:55001", 1, 50), listing(550502, "item:55001", 1, 50) }, 1)
    bought = popup.data.auctionID
    beforeRefresh, beforeQueries = refreshCalls, queryCount()
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", bought)
    click(window.rows[2].action)
    runImmediate()
    check(queryCount() == beforeQueries + 1 and refreshCalls == beforeRefresh,
        "an immediate next-item selection cancels the previous deferred cache pass and deadline")
    results = { listing(550601, "item:55002", 1, 60) }
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55002))
    check(popup.shown and popup.data.auctionID == 550601, "cancelled previous-item work cannot replace the new item's quote")
    cancelPopup()

    -- Diagnose the pre-confirmation wait without another query, timer or purchase.
    reset()
    addon.Diagnostics.SetEnabled(false)
    results = { listing(550701, "item:55001", 1, 50) }
    throttle = false
    beforeRefresh, beforeQueries, beforeBids = refreshCalls, queryCount(), bidAttempts
    click(window.rows[1].action)
    check(addon.LastPriceCheck and addon.LastPriceCheck.state == "queued" and addon.LastPriceCheck.item == 55001
        and queryCount() == beforeQueries and not popup.shown,
        "the latest price check is retained while queued even when debug logging is disabled")
    now = now + 1
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55001))
    check(addon.LastPriceCheck.state == "queued" and not popup.shown,
        "a stale same-key result before dispatch cannot finish the queued check or its timing")
    now = now + 1
    throttle = true
    event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(addon.LastPriceCheck.state == "sent" and addon.LastPriceCheck.queue_ms == 2000
        and queryCount() == beforeQueries + 1, "price-check timing records the two-second native queue separately")
    now = now + 1
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55002))
    check(addon.LastPriceCheck.state == "sent" and not popup.shown,
        "another item's result does not start the selected query's reply timer")
    now = now + 2
    throttle = false
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(55001))
    local timing = addon.LastPriceCheck
    check(popup.shown and timing.state == "preview" and timing.queue_ms == 2000 and timing.reply_ms == 3000
        and timing.results_to_preview_ms == 0 and timing.total_ms == 5000,
        "the five-second pre-confirmation wait splits into two-second queue, three-second reply and zero local processing")
    check(refreshCalls == beforeRefresh and queryCount() == beforeQueries + 1 and bidAttempts == beforeBids,
        "price-check telemetry adds no refresh, duplicate search or automatic transaction")
    local report = addon.Diagnostics.Report()
    check(report:find("Latest price check:", 1, true) and report:find("queue_ms=2000", 1, true)
        and report:find("reply_ms=3000", 1, true) and report:find("results_to_preview_ms=0", 1, true)
        and report:find("total_ms=5000", 1, true), "the copyable report includes the measured pre-confirmation phases")
    check(refreshCalls == beforeRefresh and queryCount() == beforeQueries + 1 and bidAttempts == beforeBids,
        "reading price-check diagnostics never repeats a query or transaction")
    cancelPopup()
    check(addon.LastPriceCheck.state == "preview" and addon.LastPriceCheck.queue_ms == 2000
        and addon.LastPriceCheck.reply_ms == 3000 and addon.LastPriceCheck.total_ms == 5000,
        "closing a shown confirmation preserves its completed pre-confirmation timing")

    reset()
    throttle = false
    beforeQueries, beforeBids = queryCount(), bidAttempts
    click(window.rows[1].action)
    now = now + 1
    event("AUCTION_HOUSE_CLOSED")
    check(addon.LastPriceCheck.state == "ended" and addon.LastPriceCheck.queue_ms == 1000
        and addon.LastPriceCheck.total_ms == 1000 and addon.LastPriceCheck.reply_ms == nil
        and addon.LastPriceCheck.results_to_preview_ms == nil,
        "cancelling before dispatch records an ended queue without inventing reply or processing time")
    check(queryCount() == beforeQueries and bidAttempts == beforeBids,
        "retaining an unfinished check does not send its cancelled query or a purchase")
    C_AuctionHouse.RefreshItemSearchResults = originalRefresh
    print("Profit Master purchase latency: " .. (checks - latencyChecks) .. " assertions passed (Lua 5.1).")
end
CheckPurchaseLatency()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterPurchaseLatency"))()
