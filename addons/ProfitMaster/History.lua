local _, addon = ...
local history = {}
addon.History = history

local db, marketKey, prunedDay
local itemCount, vendorCount = 0, 0
local problem = "Waiting for saved data"
local DAY = 86400

local function Number(value, minimum)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value < math.huge and value > -math.huge and value >= minimum
end

local function Item(id)
    if not db or not Number(id, 1) then return nil end
    if db.items[id] == nil then
        db.items[id] = {}
        itemCount = itemCount + 1
    end
    if type(db.items[id]) == "table" then return db.items[id] end
end

function history.Prune(now)
    if not db then return end
    local today = math.floor(now / DAY)
    if prunedDay == today then return end
    for _, market in pairs(db.markets) do
        if type(market) == "table" and type(market.days) == "table" then
            for day in pairs(market.days) do
                if type(day) == "number" and day < today - 29 then market.days[day] = nil end
            end
        end
    end
    prunedDay = today
end

function history.Initialize(saved)
    db, prunedDay, itemCount, vendorCount = nil, nil, 0, 0
    if saved == nil then saved = { version = 1, items = {}, markets = {} } end
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.items) ~= "table"
        or type(saved.markets) ~= "table" then
        problem = "Unsupported saved database; existing data preserved"
        return nil
    end
    db, problem = saved, nil
    for _, item in pairs(db.items) do
        if type(item) == "table" then
            itemCount = itemCount + 1
            if Number(item.vendorPrice, 0) then vendorCount = vendorCount + 1 end
        end
    end
    history.Prune(time())
    return db
end

function history.SetMarket(key)
    if not (issecretvalue and issecretvalue(key)) and type(key) == "string" and key ~= "" then
        marketKey = key
    end
end

function history.RecordVendor(link, name, price, observedAt)
    if not db or (issecretvalue and (issecretvalue(link) or issecretvalue(name)))
        or type(link) ~= "string" or type(name) ~= "string" or not Number(price, 0) then return end
    local id = tonumber(link:match("item:(%d+)"))
    local at = observedAt or time()
    if not Number(at, 0) then return end
    local item = Item(id)
    if not item then return end
    if item.vendorSeenAt and at < item.vendorSeenAt then return end
    -- Latest verified observation, not a universal value for all variants of this ID.
    if not Number(item.vendorPrice, 0) then vendorCount = vendorCount + 1 end
    item.name, item.vendorLink, item.vendorPrice = name, link, price
    item.vendorSeenAt = at
end

function history.BeginScan(source, observedAt, collectMeans)
    if not db or not marketKey then return nil end
    history.Prune(time())
    local at = observedAt or time()
    if not Number(at, 0) then return nil end
    local day = math.floor(at / DAY)
    if day < math.floor(time() / DAY) - 29 then return nil end
    if db.markets[marketKey] == nil then db.markets[marketKey] = { days = {} } end
    local market = db.markets[marketKey]
    if type(market) ~= "table" or type(market.days) ~= "table" then return nil end
    if market.days[day] == nil then market.days[day] = { records = {}, count = 0 } end
    local bucket = market.days[day]
    if type(bucket) ~= "table" or type(bucket.records) ~= "table" then return nil end
    return { bucket = bucket, source = source, at = at, meanOwner = db,
        meanStatus = source == "replicate" and collectMeans ~= false and "open" or "disabled",
        meanValid = true, meanGroups = source == "replicate" and collectMeans ~= false and {} or nil }
end

local function Observe(scan, key, id, unitPrice)
    if not scan or not Number(unitPrice, 0) or unitPrice == 0 or not Item(id) then return end
    local bucket = scan.bucket
    local row = bucket.records[key]
    if row == nil then
        row = { low = unitPrice, high = unitPrice, last = unitPrice, samples = 0, at = scan.at }
        bucket.records[key] = row
        bucket.count = (bucket.count or 0) + 1
    end
    if type(row) ~= "table" then return end
    row.low, row.high = math.min(row.low, unitPrice), math.max(row.high, unitPrice)
    row.samples = row.samples + 1
    if scan.at >= row.at then row.last, row.at = unitPrice, scan.at end
end

function history.RecordBrowse(scan, info)
    if not scan or scan.source ~= "browse" or not info or (issecretvalue and issecretvalue(info)) then return end
    local key = info.itemKey
    if not key or (issecretvalue and issecretvalue(key)) then return end
    if not Number(key.itemID, 1) or not Number(info.totalQuantity, 1) or not Number(info.minPrice, 0) then return end
    local level, suffix, pet = key.itemLevel, key.itemSuffix, key.battlePetSpeciesID
    if issecretvalue and (issecretvalue(level) or issecretvalue(suffix) or issecretvalue(pet)) then return end
    level, suffix, pet = level or 0, suffix or 0, pet or 0
    if not Number(level, 0) or not Number(suffix, -math.huge) or not Number(pet, 0) then return end
    local id = key.itemID
    local variant = "browse:" .. id .. ":" .. level .. ":" .. suffix .. ":" .. pet
    Observe(scan, variant, id, info.minPrice)
end

-- Numeric replicate data is sufficient; item-name/vendor cache residency is not.
-- This path records distributions only and never changes legacy observations.
function history.RecordReplicateDistribution(scan, info)
    if not scan or scan.source ~= "replicate" or scan.meanStatus ~= "open" or not scan.meanValid then return false end
    if (issecretvalue and issecretvalue(info)) or type(info) ~= "table" then
        scan.meanValid = false
        return false
    end
    local id, quantity, buyout = info[17], info[3], info[10]
    if not Number(id, 1) or id ~= math.floor(id) or not Number(quantity, 1)
        or quantity ~= math.floor(quantity) or not Number(buyout, 0) or buyout ~= math.floor(buyout) then
        scan.meanValid = false
        return false
    end
    if buyout == 0 then return true end -- Bid-only auctions have no buyout price.
    local price, key = buyout / quantity, "replicate:" .. id
    local group = scan.meanGroups[key]
    if not group then group = { prices = {}, samples = 0 }; scan.meanGroups[key] = group end
    local count, samples = (group.prices[price] or 0) + quantity, group.samples + quantity
    if not Number(count, 1) or not Number(samples, 1) or samples > 9007199254740991 then
        scan.meanValid = false
        return false
    end
    group.prices[price], group.samples = count, samples
    return true
end

function history.RecordReplicate(scan, entry)
    local info = scan and scan.source == "replicate" and entry
        and not (issecretvalue and issecretvalue(entry)) and type(entry) == "table" and entry.replicateInfo
    if scan and scan.meanStatus == "open" then history.RecordReplicateDistribution(scan, info) end
    if issecretvalue and issecretvalue(info) then return end
    if type(info) ~= "table" or not Number(info[17], 1) or not Number(info[3], 1) or not Number(info[10], 0) then return end
    -- Replicate has no AH variant key: keep this broader history explicitly separate.
    Observe(scan, "replicate:" .. info[17], info[17], info[10] / info[3])
end

function history.Abort(scan)
    if not scan or scan.meanStatus == "done" then return end
    scan.meanStatus, scan.meanGroups = "aborted", nil
end

-- Each call handles at most 256 collection/trim operations. Sorting is per price
-- group, never one unbounded all-market sort. No histogram expands into units.
-- The returned callback is shared by repeated Finish calls and commits once.
function history.Finish(scan, complete)
    if not scan then return function() return true, 0 end end
    if scan.meanStep then return scan.meanStep end
    local groups, values, count = scan.meanGroups, {}, 0
    local key, group, prices, cursor, index, seen, sum, cut, retained
    local base, rollup, copyKey, overlayKey
    local phase = "group"
    local function Done(saved)
        groups, values, prices, group = nil, nil, nil, nil
        base, rollup = nil, nil
        scan.meanGroups, scan.meanSaved = nil, saved
        if scan.meanStatus ~= "aborted" then scan.meanStatus = "done" end
        return true, saved
    end
    local function BeginRollup()
        local bucket = scan.bucket
        base = bucket.trimmedMeans
        if (base ~= nil and type(base) ~= "table")
            or (bucket.trimmedMethod ~= nil and bucket.trimmedMethod ~= "unit-weighted-trimmed")
            or (bucket.trimmedTail ~= nil and bucket.trimmedTail ~= 0.1)
            or (bucket.trimmedScans ~= nil and (not Number(bucket.trimmedScans, 0)
                or bucket.trimmedScans ~= math.floor(bucket.trimmedScans) or bucket.trimmedScans >= 9007199254740991)) then return false end
        rollup, copyKey, overlayKey, phase = {}, nil, nil, "copy"
        return true
    end
    local validComplete = not (issecretvalue and issecretvalue(complete)) and complete == true
    if not validComplete or scan.meanStatus ~= "open" or not scan.meanValid then history.Abort(scan)
    else scan.meanStatus = "finalizing" end
    scan.meanStep = function()
        if scan.meanStatus == "done" then return true, scan.meanSaved or 0 end
        if scan.meanStatus == "aborted" then return Done(0) end
        for _ = 1, 256 do
            if phase == "group" then
                key, group = next(groups, key)
                if not key then
                    if count == 0 or scan.meanOwner ~= db or math.floor(scan.at / DAY) < math.floor(time() / DAY) - 29
                        or not BeginRollup() then return Done(0) end
                else
                    prices, cursor, phase = {}, nil, "collect"
                end
            elseif phase == "collect" then
                cursor = next(group.prices, cursor)
                if cursor then prices[#prices + 1] = cursor
                else
                    table.sort(prices)
                    index, seen, sum, cut = 1, 0, 0, group.samples * 0.1
                    retained, phase = group.samples - 2 * cut, "trim"
                end
            elseif phase == "trim" then
                local price = prices[index]
                if price then
                    local finish = seen + group.prices[price]
                    local keep = math.max(0, math.min(finish, group.samples - cut) - math.max(seen, cut))
                    sum, seen, index = sum + price * keep, finish, index + 1
                    if not Number(sum, 0) then history.Abort(scan); return Done(0) end
                else
                    values[key] = { mean = sum / retained, samples = group.samples, retained = retained }
                    count, phase = count + 1, "group"
                end
            elseif phase == "copy" then
                if base then copyKey = next(base, copyKey) end
                if copyKey then rollup[copyKey] = base[copyKey]
                else phase = "overlay" end
            else
                overlayKey = next(values, overlayKey)
                if overlayKey then
                    local value, previous = values[overlayKey], base and base[overlayKey]
                    if previous and (type(previous) ~= "table" or not Number(previous.sum, 0)
                        or not Number(previous.count, 1) or previous.count ~= math.floor(previous.count)
                        or not Number(previous.mean, 0) or not Number(previous.samples, 1)
                        or not Number(previous.retained, 0) or not Number(previous.at, 0)) then return Done(0) end
                    local total, samples = (previous and previous.sum or 0) + value.mean, (previous and previous.count or 0) + 1
                    if not Number(total, 0) or samples > 9007199254740991 then return Done(0) end
                    local latest = previous and previous.at > scan.at and previous or value
                    rollup[overlayKey] = { sum = total, count = samples, mean = latest.mean,
                        samples = latest.samples, retained = latest.retained, at = latest == previous and previous.at or scan.at }
                elseif scan.bucket.trimmedMeans ~= base then
                    -- Another completed finalizer won the swap; rebase this one
                    -- without mutating either snapshot or losing a contribution.
                    if not BeginRollup() then return Done(0) end
                else
                    if scan.meanOwner ~= db or math.floor(scan.at / DAY) < math.floor(time() / DAY) - 29 then return Done(0) end
                    scan.bucket.trimmedMeans = rollup
                    scan.bucket.trimmedScans = (scan.bucket.trimmedScans or 0) + 1
                    scan.bucket.trimmedMethod, scan.bucket.trimmedTail = "unit-weighted-trimmed", 0.1
                    return Done(count)
                end
            end
        end
        return false, 0
    end
    return scan.meanStep
end

function history.Summary()
    if not db then return "Database: " .. problem end
    local days, snapshots = 0, 0
    local market = marketKey and db.markets[marketKey]
    if type(market) == "table" and type(market.days) == "table" then
        for _, bucket in pairs(market.days) do
            if type(bucket) == "table" then
                local count = Number(bucket.trimmedScans, 1) and bucket.trimmedScans or 0
                snapshots = snapshots + count
                if Number(bucket.count, 1) or count > 0 then days = days + 1 end
            end
        end
    end
    return "Database: " .. itemCount .. " items; " .. vendorCount .. " verified vendor prices; "
        .. days .. "/30 days of AH observations; " .. snapshots .. " trimmed snapshots"
        .. (marketKey and "" or " (waiting for market)")
end
