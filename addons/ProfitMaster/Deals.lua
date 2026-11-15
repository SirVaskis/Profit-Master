local _, addon = ...
local profitSettings, minimumProfit = nil, 3

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ValidMinimum(value)
    return Public(value) and type(value) == "number" and value >= 0
        and value <= 999999999 and value == math.floor(value)
end

local function ValidSettings(value)
    return Public(value) and type(value) == "table" and Public(value.version) and value.version == 1
        and Public(value.items) and type(value.items) == "table"
        and Public(value.markets) and type(value.markets) == "table"
end

function addon.InitializeProfitSettings(value)
    profitSettings, minimumProfit = nil, 3
    if not ValidSettings(value) then return false end
    profitSettings = value
    local preference = value.minimumProfit
    if Public(preference) and preference == nil then value.minimumProfit = 3 end
    if ValidMinimum(preference) then minimumProfit = preference end
    return true
end

function addon.GetMinimumProfit()
    return minimumProfit
end

function addon.SetMinimumProfit(value)
    if not ValidSettings(profitSettings) or not ValidMinimum(value) then return false end
    profitSettings.minimumProfit, minimumProfit = value, value
    return true
end

local function VendorInfo(reference, itemCache)
    local item = itemCache and itemCache[reference]
    if item == nil then
        local name, returnedLink, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(reference)
        if issecretvalue and (issecretvalue(name) or issecretvalue(returnedLink) or issecretvalue(sellPrice)) then
            return nil
        end
        local link = type(reference) == "number" and ("item:" .. reference) or reference
        if type(name) == "string" and type(sellPrice) == "number" and addon.History then
            addon.History.RecordVendor(link, name, sellPrice)
        end
        item = type(name) == "string" and type(sellPrice) == "number"
            and { name = name, sellPrice = sellPrice, link = returnedLink or link,
                display = returnedLink or name } or false
        if itemCache then itemCache[reference] = item end
    end
    if item == false then return nil, true, "unavailable" end
    return item
end

-- Retain the actual fields while available. A later GetItemInfo call can miss
-- again after the client evicts data while loading thousands of other items.
function addon.CaptureVendorInfo(reference, itemCache)
    local item = VendorInfo(reference)
    if not item then return false end
    itemCache[reference] = item
    return true
end

local function Calculate(item, link, quantity, buyout, itemCache)
    local vendor = item.sellPrice * quantity
    local value, disenchant, gross = vendor, false, nil
    if addon.Disenchant and addon.Disenchant.Enabled() then
        local net, expected = addon.Disenchant.Estimate(link, itemCache)
        if net and net - item.sellPrice >= 3 then
            value, gross, disenchant = net * quantity, expected * quantity, true
        end
    end
    if value <= 0 then return nil, false, "noVendor" end
    if value <= buyout then return nil, false, "notCheap" end
    if value - buyout < addon.GetMinimumProfit() then return nil, false, "belowMinimum" end
    return {
        link = link, name = item.name, quantity = quantity,
        cost = buyout, vendor = vendor, profit = value - buyout,
        disenchant = disenchant, deNet = disenchant and value or nil, deGross = gross,
    }
end

-- Buyout is for the entire stack. Live valuation always uses its exact item link.
function addon.Deal(link, quantity, buyout, itemCache)
    if issecretvalue and (issecretvalue(link) or issecretvalue(quantity) or issecretvalue(buyout)) then return nil end
    if type(link) ~= "string" or not link:find("item:", 1, true) then return nil end
    if type(quantity) ~= "number" or quantity <= 0 or type(buyout) ~= "number" or buyout <= 0 then return nil end
    local item, missing, reason = VendorInfo(link, itemCache)
    if not item then return nil, missing, reason end
    return Calculate(item, link, quantity, buyout, itemCache)
end

-- Replicate supplies a total price/count; display the normalized per-item estimate.
function addon.ReplicateDeal(entry, itemCache)
    local info = entry and entry.replicateInfo
    if not info or (issecretvalue and issecretvalue(info)) then return nil end
    local quantity, buyout, id = info[3], info[10], info[17]
    if issecretvalue and (issecretvalue(quantity) or issecretvalue(buyout) or issecretvalue(id)) then return nil end
    if type(quantity) ~= "number" or quantity < 1 or type(buyout) ~= "number" or buyout <= 0 then return nil end
    if type(id) ~= "number" or id <= 0 then return nil end
    local deal, missing, reason = addon.Deal(entry.itemLink, 1, buyout / quantity, itemCache)
    if deal then
        deal.itemID, deal.available, deal.perUnit = id, quantity, true
    end
    return deal, missing, reason
end

-- Browse prices are per-item summaries, not an executable stack quote.
function addon.BrowseDeal(info, itemCache)
    if issecretvalue and issecretvalue(info) then return nil end
    local key = info and info.itemKey
    if issecretvalue and issecretvalue(key) then return nil end
    if issecretvalue and key and (issecretvalue(key.itemID) or issecretvalue(key.battlePetSpeciesID)
        or issecretvalue(info.totalQuantity) or issecretvalue(info.minPrice)) then
        return nil
    end
    if not key or not info.totalQuantity or info.totalQuantity <= 0 then return nil end
    if (key.battlePetSpeciesID or 0) ~= 0 then
        return nil, false, "pet"
    end
    local keyInfo = C_AuctionHouse.GetItemKeyInfo(key)
    if issecretvalue and keyInfo and (issecretvalue(keyInfo) or issecretvalue(keyInfo.isCommodity)
        or issecretvalue(keyInfo.isPet)) then return nil end
    -- This optional AH metadata is not a prerequisite for reading a vendor price.
    if keyInfo and keyInfo.isPet then return nil, false, "pet" end
    if type(info.minPrice) ~= "number" or info.minPrice <= 0 then return nil end
    -- Browse is a base-item estimate. Use the ID lookup's price directly; an
    -- appearance/display link and a second item-link lookup are not prerequisites.
    local item, missing, reason = VendorInfo(key.itemID, itemCache)
    if not item then return nil, missing, reason end
    local deal
    deal, missing, reason = Calculate(item, item.link, 1, info.minPrice, itemCache)
    if deal then
        deal.itemID, deal.itemKey, deal.perUnit = key.itemID, key, true
        deal.available = info.totalQuantity
        deal.display = item.display
        deal.isCommodity = keyInfo and keyInfo.isCommodity or false
    end
    return deal, missing, reason
end

function addon.CommodityDeal(info, itemCache)
    if not info or (issecretvalue and (issecretvalue(info) or issecretvalue(info.itemID)
        or issecretvalue(info.quantity) or issecretvalue(info.unitPrice) or issecretvalue(info.numOwnerItems)
        or issecretvalue(info.containsOwnerItem) or issecretvalue(info.containsAccountItem))) then return nil end
    if type(info.itemID) ~= "number" or info.itemID < 1 or type(info.quantity) ~= "number"
        or info.quantity < 1 or type(info.unitPrice) ~= "number" or info.unitPrice <= 0 then return nil end
    if info.itemID ~= math.floor(info.itemID) or info.quantity ~= math.floor(info.quantity)
        or info.unitPrice ~= math.floor(info.unitPrice) then return nil end
    -- Account-owned counts are not exposed. Skip that row rather than count them
    -- as stock we can buy. Ordinary owner quantities can be subtracted exactly.
    if info.containsAccountItem then return nil end
    local owned = info.numOwnerItems
    if owned == nil and info.containsOwnerItem then return nil end
    owned = owned or 0
    if type(owned) ~= "number" or owned < 0 or owned > info.quantity or owned ~= math.floor(owned) then return nil end
    local available = info.quantity - owned
    if available < 1 then return nil end
    local item, missing, reason = VendorInfo(info.itemID, itemCache)
    if not item then return nil, missing, reason end
    local deal
    deal, missing, reason = Calculate(item, item.link, 1, info.unitPrice, itemCache)
    if deal then
        deal.itemID, deal.available, deal.isCommodity = info.itemID, available, true
    end
    return deal, missing, reason
end

function addon.SortDeals(deals)
    table.sort(deals, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.link < b.link
    end)
end

function addon.LiveDeal(info, itemCache)
    if issecretvalue and (issecretvalue(info) or (info and
        (issecretvalue(info.containsOwnerItem) or issecretvalue(info.containsAccountItem)
        or issecretvalue(info.auctionID)))) then
        return nil
    end
    if not info or info.containsOwnerItem or info.containsAccountItem
        or not info.auctionID then
        return nil
    end
    if issecretvalue and issecretvalue(info.quantity) then return nil end
    if type(info.quantity) ~= "number" or info.quantity < 1 then return nil end
    -- Non-commodity search rows group available copies at a price. PlaceBid buys
    -- one auction ID (one item), not every copy in the row's quantity field.
    local deal, missing = addon.Deal(info.itemLink, 1, info.buyoutAmount, itemCache)
    if deal then
        deal.auctionID = info.auctionID
        deal.available = info.quantity
        return deal
    end
    return nil, missing
end

function addon.SameListing(deal, current)
    return current and deal.auctionID == current.auctionID
        and deal.link == current.link and deal.quantity == current.quantity
        and deal.cost == current.cost and deal.vendor == current.vendor
        and deal.disenchant == current.disenchant and deal.deNet == current.deNet
end
