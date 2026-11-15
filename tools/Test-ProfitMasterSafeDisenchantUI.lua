-- Extend the production purchase harness. No game input or real auctions.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[
local function CheckSafeDisenchantUI()
    local beforeChecks = checks
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    commodity, full, throttle = false, true, true
    local de, control = addon.Disenchant, window.safeDisenchant
    local originalInfo, originalLevel, originalAPI = C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, Auctionator.API
    local dust, essence = 100, 10000
    C_Item.GetItemInfo = function(reference)
        if reference == 49601 or reference == "item:49601" then
            return "Safe DE armor", "item:49601", 2, 10, 1, "", "", 1, "INVTYPE_CHEST", 1, 10, 4, 1, 1, 0
        end
        return originalInfo(reference)
    end
    C_Item.GetDetailedItemLevelInfo = function(reference)
        if reference == 49601 or reference == "item:49601" then return 10, false, 10 end
        if originalLevel then return originalLevel(reference) end
    end
    Auctionator.API = { v1 = { GetAuctionPriceByItemID = function(_, id)
        if id == 10940 then return dust elseif id == 10938 then return essence end
    end } }
    local function toggle(value)
        control:SetChecked(value)
        control.scripts.OnClick(control)
    end
    local function publish(cost)
        listener:ReceiveEvent("complete", { scanned(49601, "item:49601", 1, cost) })
        runImmediate()
    end
    local function requests() return queries + exactQueries + refreshes + more + scans + browseScans end
    de.SetEnabled(true)
    de.SetSafe(false)
    publish(120)
    check(window.rows[1].deal.disenchant and window.rows[1].deal.profit > 0,
        "expensive rare essence qualifies an average-mode deal")
    local beforeRequests, beforeBids = requests(), bidAttempts
    toggle(true)
    check(de.Safe() and ProfitMasterDisenchantDB.safe and control:GetChecked() and not window.rows[1].deal,
        "safe checkbox saves its setting and immediately removes old average-only offers")
    check(window.headers[4].text == "Vendor / DE min." and window.heading.text:find("cheapest baseline", 1, true),
        "safe header explains the minimum valuation")
    check(requests() == beforeRequests and bidAttempts == beforeBids,
        "mode change neither queries nor buys automatically")
    publish(120)
    check(not window.rows[1].deal, "fresh safe scan rejects a losing cheapest outcome")
    publish(82)
    check(window.rows[1].deal.disenchant and window.rows[1].deal.deNet == 85
        and window.rows[1].deal.profit == 3, "safe scan retains the exact minimum-profit boundary")
    results = { listing(496101, "item:49601", 1, 82) }
    click(window.rows[1].action)
    check(not control.enabled, "safe mode locks immediately during live price verification")
    toggle(false)
    check(de.Safe() and control:GetChecked(), "queued unsafe toggle is rejected during verification")
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49601))
    check(popup.shown and popup.text:find("Cheapest baseline outcome: 100", 1, true)
        and popup.text:find("Estimated profit / item: 3", 1, true)
        and popup.text:find("SAFE DE", 1, true) and popup.text:find("unverified", 1, true),
        "purchase preview shows minimum proceeds, matching profit and baseline uncertainty")
    toggle(false)
    check(de.Safe() and popup.shown, "an open safe quote cannot be switched to average")
    dust = 50
    beforeBids = bidAttempts
    confirmPopup()
    check(bidAttempts == beforeBids and not popup.shown and not window.rows[1].deal,
        "Buy-time minimum revaluation rejects a newly losing cheap outcome despite expensive essence")

    dust = 100
    publish(5)
    toggle(false)
    check(window.rows[1].deal and not window.rows[1].deal.disenchant and window.rows[1].deal.profit == 5,
        "mode switch retains truly vendor-profitable offers at vendor value")
    publish(120)
    check(window.rows[1].deal.disenchant, "explicit average mode can find its original offers again")
    toggle(true)

    -- A stale queued toggle must not change semantics between CPU slices or
    -- during a provider scan, even if the visible checkbox is disabled.
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    check(not control.enabled and de.Safe(), "safe setting locks during automatic scans")
    toggle(false)
    check(de.Safe() and control:GetChecked(), "queued mode toggle cannot alter an active scan")
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", { { itemKey = C_AuctionHouse.MakeItemKey(49601), totalQuantity = 1, minPrice = 82 } })
    runImmediate()
    check(window.rows[1].deal.deNet == 85 and control.enabled,
        "automatic scan completion keeps safe values and releases the mode lock")

    -- Unchanged safe quote still uses the normal one-auction hardware purchase.
    results = { listing(496102, "item:49601", 1, 82) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49601))
    beforeBids = bidAttempts
    confirmPopup()
    check(bidAttempts == beforeBids + 1 and not control.enabled,
        "safe mode preserves explicit purchase confirmation and locks pending purchases")
    toggle(false)
    check(de.Safe(), "pending safe purchase rejects a stale unsafe toggle")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 496102)
    toggle(false)
    check(de.Safe(), "stock recheck also rejects mode changes")
    event("AUCTION_HOUSE_CLOSED")
    drain()
    C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, Auctionator.API = originalInfo, originalLevel, originalAPI
    for _, frame in ipairs(frames) do check(not frame.scripts.OnUpdate, "safe mode adds no polling") end
    print("Profit Master safe disenchant UI: " .. (checks - beforeChecks) .. " offline assertions passed (Lua 5.1).")
end
CheckSafeDisenchantUI()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterSafeDisenchantUI"))()
