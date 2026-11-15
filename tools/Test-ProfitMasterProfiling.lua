-- Exercise production scan profiling with controlled clocks and native-shaped events.
-- Appends to the existing integration harness; never connects to or controls WoW.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[

local function CheckScanProfiling()
    local profileChecks = checks
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    addon.Disenchant.SetEnabled(false)
    addon.Diagnostics.SetEnabled(false)
    assert(addon.SetMinimumProfit(3))
    commodity, full, throttle = false, true, true
    local precise, oldPrecise = now, GetTimePreciseSec
    GetTimePreciseSec = function() return precise end
    local function advance(seconds)
        precise, now = precise + seconds, now + seconds
    end
    local function row(id, price, suffix)
        return scanned(id, "item:" .. id .. (suffix or ""), 1, price or 50)
    end
    local function start(rows)
        listener:ReceiveEvent("start")
        listener:ReceiveEvent("complete", rows)
    end
    local function profile()
        check(type(addon.LastScanProfile) == "table", "a completed or stopped scan retains its runtime profile with debug disabled")
        return addon.LastScanProfile
    end
    local function near(actual, expected, message)
        check(type(actual) == "number" and math.abs(actual - expected) <= 1, message .. ": " .. tostring(actual))
    end
    local function activeTimers()
        local active = 0
        for _, scheduled in ipairs(timers) do if not scheduled.cancelled then active = active + 1 end end
        return active
    end
    local function requests()
        return queries + exactQueries + refreshes + more + scans + browseScans
    end
    local beforeRequests, beforeBids = requests(), bidAttempts
    local previousRequest = #itemRequests

    values["item:51001"] = 100
    start({ row(51001) })
    runImmediate()
    local result = profile()
    check(result.outcome == "complete" and result.source == "replicate" and result.rows == 1 and result.minimum_profit == 3,
        "a warm scan profile identifies its completed source, rows and configured cutoff")
    check(result.vendor_missing_ids == 0 and result.vendor_missing_refs == 0 and result.vendor_requests == 0
        and result.vendor_ready == 0 and result.vendor_failed == 0 and result.vendor_unresolved == 0 and result.vendor_queued == 0,
        "warm metadata records no missing vendor references or artificial requests")
    near(result.vendor_pending_ms, 0, "warm scan has no outstanding-request interval")
    near(result.vendor_pending_after_input_ms, 0, "warm scan has no post-input vendor wait")
    near(result.vendor_ready_avg_ms, 0, "warm scan has no fabricated average completion latency")
    near(result.vendor_ready_max_ms, 0, "warm scan has no fabricated longest completion")
    check(#itemRequests == previousRequest and activeTimers() == 0, "profiling warm data adds no metadata request or idle timer")

    -- Both IDs are dispatched together: seven seconds of union, not 5+7 seconds.
    values["item:51101"], values["item:51102"] = nil, nil
    start({ row(51101), row(51102) })
    check(#itemRequests == previousRequest + 2 and activeTimers() <= 1, "two missing IDs share the existing bounded loader")
    advance(2)
    event("ITEM_DATA_LOAD_RESULT", 51101, true)
    check(not window.scan.enabled and eventFrame.events.GET_ITEM_INFO_RECEIVED,
        "record-loaded success cannot complete a request before vendor information is readable")
    advance(3)
    values["item:51101"] = 100
    event("GET_ITEM_INFO_RECEIVED", 51101, true)
    advance(2)
    values["item:51102"] = 100
    event("ITEM_DATA_LOAD_RESULT", 51102, true)
    runImmediate()
    result = profile()
    check(result.vendor_missing_ids == 2 and result.vendor_missing_refs == 2 and result.vendor_requests == 2
        and result.vendor_ready == 2 and result.vendor_failed == 0 and result.vendor_unresolved == 0,
        "overlapping successful requests retain exact identity and outcome counts")
    near(result.vendor_pending_ms, 7000, "overlapping requests are measured as a union")
    near(result.vendor_pending_after_input_ms, 7000, "non-streamed vendor requests all occur after provider input")
    near(result.vendor_ready_avg_ms, 6000, "average latency ends when each ID's vendor value is usable")
    near(result.vendor_ready_max_ms, 7000, "longest usable-vendor latency is retained")
    near(result.active_ms + result.pause_ms, result.scan_ms, "scan elapsed decomposes into active and purchase-paused time")

    -- Three auction rows, one ID, two distinct exact references.
    values["item:51201:a"], values["item:51201:b"] = nil, nil
    start({ row(51201, 50, ":a"), row(51201, 60, ":a"), row(51201, 50, ":b") })
    advance(1)
    values["item:51201:a"] = 100
    event("ITEM_DATA_LOAD_RESULT", 51201, true)
    check(not window.scan.enabled, "one ready exact reference does not complete an ID with another missing reference")
    advance(1)
    values["item:51201:b"] = 100
    event("GET_ITEM_INFO_RECEIVED", 51201, true)
    runImmediate()
    result = profile()
    check(result.rows == 3 and result.vendor_missing_ids == 1 and result.vendor_missing_refs == 2
        and result.vendor_requests == 1 and result.vendor_ready == 1,
        "duplicate auction rows do not inflate unique missing ID or exact-reference counts")
    near(result.vendor_ready_max_ms, 2000, "readiness covers all exact references known for the requested ID")

    -- Requests overlap discovery; only the final two seconds drain after input.
    values["item:51301"] = nil
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { { itemKey = C_AuctionHouse.MakeItemKey(51301), totalQuantity = 1, minPrice = 50 } }
    listener:ReceiveEvent("browse_progress", 0.2)
    advance(5)
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", pipelineBrowse.rawScan)
    advance(2)
    values["item:51301"] = 100
    event("GET_ITEM_INFO_RECEIVED", 51301, true)
    runImmediate()
    result = profile()
    near(result.provider_ms, 5000, "streamed provider duration ends before final vendor readiness")
    near(result.vendor_pending_ms, 7000, "vendor union includes the overlap with discovery")
    near(result.vendor_pending_after_input_ms, 2000, "post-input vendor union clips at provider completion")
    near(result.post_input_ms, 2000, "post-input elapsed includes the final vendor drain")

    -- Vendor data may finish while Buy pauses the scan; that pause is excluded.
    values["item:51401"] = 100
    values["item:51402"], values["item:51403"] = nil, nil
    start({ row(51401), row(51402), row(51403) })
    advance(2)
    results = { listing(514101, "item:51401", 1, 50) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(51401))
    check(popup.shown and not window.scan.enabled, "a live quote pauses outstanding vendor work")
    advance(10)
    values["item:51402"] = 100
    event("GET_ITEM_INFO_RECEIVED", 51402, true)
    advance(10)
    values["item:51403"] = 100
    event("GET_ITEM_INFO_RECEIVED", 51403, true)
    advance(5)
    cancelPopup()
    runImmediate()
    result = profile()
    near(result.scan_ms, 27000, "scan wall time includes time spent reviewing a purchase")
    near(result.pause_ms, 25000, "precise purchase pause duration is retained")
    near(result.active_ms, 2000, "active scan duration excludes the entire purchase pause")
    near(result.vendor_pending_ms, 2000, "request union stops advancing while Buy owns the scan")
    near(result.vendor_ready_avg_ms, 2000, "responses during a pause exclude paused time from average readiness")
    near(result.vendor_ready_max_ms, 2000, "responses during a pause exclude paused time from longest readiness")
    check(result.vendor_ready == 2 and result.vendor_unresolved == 0, "paused callbacks still resolve their original requests")

    values["item:51501"] = nil
    start({ row(51501) })
    advance(3)
    event("ITEM_DATA_LOAD_RESULT", 51501, false)
    runImmediate()
    result = profile()
    check(result.vendor_failed == 1 and result.vendor_ready == 0 and result.vendor_unresolved == 0,
        "an explicit unsuccessful completion is a failure rather than an unresolved request")
    near(result.vendor_pending_ms, 3000, "failed requests close their pending interval")
    near(result.vendor_ready_avg_ms, 0, "failed callbacks are excluded from successful readiness averages")
    near(result.vendor_ready_max_ms, 0, "failed callbacks are excluded from longest successful readiness")

    values["item:51601"] = nil
    start({ row(51601) })
    advance(61)
    timeout()
    runImmediate()
    result = profile()
    check(result.vendor_unresolved == 1 and result.vendor_ready == 0 and result.vendor_failed == 0,
        "a loading deadline reports an unresolved request separately from terminal failure")
    near(result.vendor_pending_ms, 61000, "deadline sampling closes the outstanding interval once")
    near(result.vendor_ready_max_ms, 0, "an unresolved request is not reported as a successful response")

    local queuedRows = {}
    for id = 51611, 51645 do values["item:" .. id] = nil; queuedRows[#queuedRows + 1] = row(id) end
    start(queuedRows)
    advance(61)
    timeout()
    runImmediate()
    result = profile()
    check(result.vendor_missing_ids == 35 and result.vendor_requests == 32 and result.vendor_unresolved == 32
        and result.vendor_queued == 3, "deadline separates dispatched unfinished requests from queued IDs never sent")
    near(result.vendor_pending_ms, 61000, "unsent queued IDs do not add duplicate pending time")

    values["item:51651"] = nil
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { { itemKey = C_AuctionHouse.MakeItemKey(51651), totalQuantity = 1, minPrice = 50 } }
    listener:ReceiveEvent("browse_progress", 0.2)
    advance(1)
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_failed")
    result = profile()
    check(result.outcome == "failed" and result.vendor_unresolved == 1 and result.post_input_ms == nil,
        "provider failure retains unfinished work without inventing an input-completion phase")
    near(result.vendor_pending_ms, 1000, "provider failure closes the current pending snapshot")

    values["item:51701"] = nil
    start({ row(51701) })
    advance(2)
    event("AUCTION_HOUSE_CLOSED")
    result = profile()
    check(result.outcome == "cancelled" and result.vendor_unresolved == 1,
        "closing the auction house retains a cancelled profile with unfinished requests")
    near(result.vendor_pending_ms, 2000, "cancellation snapshots the unfinished pending interval")
    local cancelled = result
    values["item:51701"] = 100
    advance(2)
    event("GET_ITEM_INFO_RECEIVED", 51701, true)
    drain()
    check(addon.LastScanProfile == cancelled and cancelled.vendor_ready == 0,
        "late item events and cancelled timers cannot rewrite a stopped profile")
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()

    -- Synchronous native callbacks nest inside the measured loading entry point.
    local originalRequest, originalInfo = C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo
    local insideRequest = false
    C_Item.GetItemInfo = function(reference)
        if insideRequest then precise = precise + 0.003 end
        return originalInfo(reference)
    end
    C_Item.RequestLoadItemDataByID = function(id)
        originalRequest(id)
        insideRequest = true
        precise = precise + 0.002
        values["item:" .. id] = 100
        event("ITEM_DATA_LOAD_RESULT", id, true)
        insideRequest = false
    end
    values["item:51801"] = nil
    start({ row(51801) })
    runImmediate()
    result = profile()
    check(result.vendor_requests == 1 and result.vendor_ready == 1 and result.vendor_unresolved == 0,
        "timestamps and active counts exist before a synchronous request completion")
    near(result.vendor_loading_cpu_ms, 5, "nested request callback CPU is counted by its outer loading entry only once")
    near(result.vendor_ready_max_ms, 5, "synchronous readiness measures its real request and metadata work")
    near(result.active_ms, 5, "controlled synchronous work advances the precise scan clock")
    check(result.vendor_loading_cpu_ms <= result.active_ms + 1,
        "loading CPU does not exceed active time through nested double counting")
    C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo = originalRequest, originalInfo

    -- A failed load still retries valuation; each measured stage is separate.
    C_Item.GetItemInfo = function(reference)
        if reference == "item:51811" then precise = precise + 0.002 end
        return originalInfo(reference)
    end
    values["item:51811"] = nil
    start({ row(51811) })
    event("ITEM_DATA_LOAD_RESULT", 51811, false)
    runImmediate()
    result = profile()
    near(result.valuation_cpu_ms, 2, "initial valuation has its own CPU slice total")
    near(result.vendor_loading_cpu_ms, 2, "failed load metadata capture belongs to loading CPU")
    near(result.vendor_retry_cpu_ms, 2, "post-loading retry valuation has a distinct CPU total")
    near(result.active_ms, 6, "exclusive controlled stage work accounts for the six-millisecond active scan")
    C_Item.GetItemInfo = originalInfo

    -- The existing request window remains capped at 32 while instrumentation runs.
    local many, requestBase = {}, #itemRequests
    for id = 51901, 51935 do values["item:" .. id] = nil; many[#many + 1] = row(id) end
    start(many)
    check(#itemRequests - requestBase == 32 and activeTimers() <= 1,
        "profiling does not expand the loader's 32-request dispatch window or shared timer")
    for id = 51901, 51935 do
        advance(0.1)
        values["item:" .. id] = 100
        event("GET_ITEM_INFO_RECEIVED", id, true)
        check(#itemRequests - requestBase <= math.min(35, id - 51900 + 32) and activeTimers() <= 1,
            "instrumented refill keeps at most 32 metadata requests outstanding")
    end
    runImmediate()
    result = profile()
    check(result.vendor_missing_ids == 35 and result.vendor_requests == 35 and result.vendor_ready == 35
        and result.vendor_unresolved == 0, "bounded refill requests and resolves every unique missing ID exactly once")
    near(result.vendor_pending_ms, 3500, "bounded refill preserves the request-union interval across refills")
    check(requests() == beforeRequests + 1 and bidAttempts == beforeBids,
        "profiling adds no auction query or bid beyond the explicit read-only Buy verification")
    check(activeTimers() == 0, "profiling leaves no persistent timer after completion")
    GetTimePreciseSec = oldPrecise
    print("Profit Master profiling: " .. (checks - profileChecks) .. " assertions passed (Lua 5.1).")
end
CheckScanProfiling()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterProfiling"))()
