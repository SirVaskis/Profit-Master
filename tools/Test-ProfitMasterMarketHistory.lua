-- Extend the real integration harness in its existing scope. No game interaction.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[

do
    local historyChecks = checks
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    commodity, full, throttle = false, true, true
    addon.Disenchant.SetEnabled(false)
    local raw, reads = {}, 0
    local countOverride
    C_AuctionHouse.GetNumReplicateItems = function() return countOverride or #raw end
    C_AuctionHouse.GetReplicateItemInfo = function(index)
        assert(index >= 0 and index < #raw, "raw history reads use zero-based native indices")
        reads = reads + 1
        return unpack(raw[index + 1], 1, 18)
    end
    local function rawRow(id, quantity, total)
        return { [3] = quantity, [10] = total, [17] = id }
    end
    local function bucketNow()
        return ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)]
    end
    local function meanCount()
        return bucketNow().trimmedScans or 0
    end
    local function publish(rows)
        listener:ReceiveEvent("start")
        -- Emulate Auctionator's progress before our frame sees the same event.
        listener:ReceiveEvent("progress", 0.2)
        event("REPLICATE_ITEM_LIST_UPDATE")
        listener:ReceiveEvent("complete", rows)
    end

    values["item:49901"] = 100
    raw = { rawRow(49901, 10, 10), rawRow(49901, 80, 800), rawRow(49901, 10, 10000) }
    local countBefore, queriesBefore, bidsBefore = meanCount(), exactQueries + queries, #bids
    -- Auctionator omitted metadata for two rows: the raw price population remains complete.
    publish({ scanned(49901, "item:49901", 80, 800) })
    check(meanCount() == countBefore, "a scan does not persist a mean before its statistics phase")
    runImmediate()
    local mean = bucketNow().trimmedMeans["replicate:49901"]
    check(meanCount() == countBefore + 1 and mean.mean == 10 and mean.samples == 100 and mean.retained == 80,
        "raw snapshot includes omitted metadata rows and trims 10% of units from each tail")
    check(reads == #raw and exactQueries + queries == queriesBefore and #bids == bidsBefore,
        "complete price history reads locally without another query or purchase")
    check(bucketNow().records["replicate:49901"].samples == 1,
        "raw statistical capture does not duplicate legacy provider observations")

    countBefore = meanCount()
    listener:ReceiveEvent("browse_complete", {
        { itemKey = C_AuctionHouse.MakeItemKey(49901), totalQuantity = 100000, minPrice = 1 }
    })
    runImmediate()
    check(meanCount() == countBefore and window.status.text:find("Browse minima", 1, true),
        "browse minima remain visibly distinct and never become full-population means")

    -- A large snapshot must yield, and a buy must pause both reading and finalization.
    raw = {}
    for i = 1, 2200 do raw[i] = rawRow(49901, 1, 10) end
    reads = 0
    publish({ scanned(49901, "item:49901", 1, 10) })
    timeout() -- One bounded read slice, not an entire raw snapshot.
    check(reads > 0 and reads <= 1000 and not window.scan.enabled,
        "history capture yields after a bounded native-read slice")
    results = { listing(899001, "item:49901", 1, 10) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49901))
    local pausedReads = reads
    runImmediate()
    check(popup.shown and reads == pausedReads and meanCount() == countBefore,
        "an early Buy pauses snapshot statistics without saving a partial mean")
    cancelPopup()
    runImmediate()
    check(window.scan.enabled and reads == #raw and meanCount() == countBefore + 1,
        "canceling a quote resumes statistics and commits exactly once")

    countBefore = meanCount()
    publish({ scanned(49901, "item:49901", 1, 10) })
    timeout()
    event("AUCTION_HOUSE_CLOSED")
    runImmediate()
    check(meanCount() == countBefore, "AH close aborts a partially read snapshot without persistence")
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()

    publish({ scanned(49901, "item:49901", 1, 10) })
    timeout()
    event("REPLICATE_ITEM_LIST_UPDATE") -- Even an equal-sized replacement is a different snapshot.
    runImmediate()
    check(meanCount() == countBefore and window.scan.enabled,
        "replacement of the native snapshot prevents mixing price populations")

    publish({ scanned(49901, "item:49901", 1, 10) })
    countOverride = #raw - 1
    runImmediate()
    check(meanCount() == countBefore, "changed native count cannot be accepted as complete coverage")
    countOverride = nil

    raw = { rawRow(49901, 1, 10), rawRow(49902, 0, 100) }
    publish({ scanned(49901, "item:49901", 1, 10) })
    runImmediate()
    check(meanCount() == countBefore, "unreadable financial rows invalidate whole-snapshot means")
    raw = { rawRow(49901, 1, 10), rawRow(49902, 1, "SECRET") }
    publish({ scanned(49901, "item:49901", 1, 10) })
    runImmediate()
    check(meanCount() == countBefore, "restricted prices cannot silently disappear from a complete mean")

    -- Stopping/replacing work between reading and commit is still an abort.
    raw = { rawRow(49901, 1, 10) }
    publish({ scanned(49901, "item:49901", 1, 10) })
    timeout()
    listener:ReceiveEvent("browse_start")
    listener:ReceiveEvent("browse_complete", {})
    runImmediate()
    check(meanCount() == countBefore, "replacement scan cancels a prepared uncommitted mean")
    C_AuctionHouse.GetReplicateItemInfo = nil
    print("Profit Master market-history integration: " .. (checks - historyChecks) .. " assertions passed (Lua 5.1).")
end
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterMarketHistory"))()
