local _, addon = ...
local disenchant = {}
addon.Disenchant = disenchant

local saved, materialPrices, generation = nil, {}, 0
-- Expected original-era material quantities, independently encoded from published
-- Auctionator Classic probability tables. These are estimates, not verified
-- Forever server loot. Exact client eligibility: ItemDisenchantLoot 1.60.1.70888.
-- Columns: ilvl bounds, dust ID, essence ID, shard ID, armor dust/essence means,
-- weapon dust/essence/shard means, minimum dust/essence quantities per outcome.
-- Known changed weapon levels 21-30 are excluded. Minima use the same baseline.
local uncommon = {
    {5,15,10940,10938,nil,1.2,.3,.3,1.2,0,1,1},
    {16,20,10940,10939,10978,1.875,.3,.5,1.125,.05,2,1},
    {21,25,10940,10998,10978,3.75,.225,0,0,0,4,1},
    {26,30,11083,11082,11084,1.125,.3,0,0,0,1,1},
    {31,35,11083,11134,11138,2.625,.3,.7,1.125,.05,2,1},
    {36,40,11137,11135,11139,1.125,.3,.3,1.125,.05,1,1},
    {41,45,11137,11174,11177,2.625,.3,.7,1.125,.05,2,1},
    {46,50,11176,11175,11178,1.125,.3,.3,1.125,.05,1,1},
    {51,55,11176,16202,14343,2.625,.3,.77,1.125,.03,2,1},
    {56,60,16204,16203,14344,1.125,.3,.33,1.125,.03,1,1},
    {61,65,16204,16203,14344,2.625,.5,.77,1.875,.03,2,2},
}
local rare = {
    {21,25,10978,1}, {26,30,11084,1}, {31,35,11138,1},
    {36,40,11139,1}, {41,45,11177,1}, {46,50,11178,1},
    {51,55,14343,1}, {56,65,14344,.995,20725,.005},
}
local epic = {
    -- ilvl bounds, material, expected quantity, minimum quantity.
    {40,45,11177,3,2}, {46,50,11178,3,2}, {51,55,14343,3,2},
    {56,60,20725,1,1}, {61,65,20725,1.5,1},
}
local excluded = { [11287] = true, [11288] = true, [11289] = true, [11290] = true }
local excludedSlot = {
    [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true,
    INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true,
}

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value, minimum)
    return Public(value) and type(value) == "number" and value == value
        and value < math.huge and value > -math.huge and value >= minimum
end

function disenchant.ResetCache()
    materialPrices, generation = {}, generation + 1
end

local disenchantIcon
function disenchant.Icon()
    if not disenchantIcon and C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(13262)
        if Number(icon, 1) then disenchantIcon = icon end
    end
    return disenchantIcon
end

function disenchant.Initialize(value)
    saved = nil
    if value == nil then value = { version = 1, enabled = false } end
    if type(value) ~= "table" or value.version ~= 1 or type(value.enabled) ~= "boolean" then return nil end
    if value.safe == nil then value.safe = true end
    if type(value.safe) ~= "boolean" then return nil end
    saved = value
    disenchant.ResetCache()
    return saved
end

function disenchant.Enabled()
    return saved and saved.enabled == true or false
end

function disenchant.SetEnabled(enabled)
    if saved then saved.enabled = enabled == true end
    disenchant.ResetCache()
end

function disenchant.Safe()
    return not saved or saved.safe ~= false
end

function disenchant.SetSafe(enabled)
    if saved then saved.safe = enabled == true end
    disenchant.ResetCache()
end

local function Price(id)
    local value = materialPrices[id]
    if value == nil then
        local api = Auctionator and Auctionator.API and Auctionator.API.v1
        value = api and api.GetAuctionPriceByItemID and api.GetAuctionPriceByItemID("ProfitMaster", id)
        value = Number(value, 1) and value or false
        materialPrices[id] = value
    end
    if value ~= false then return value end
end

local function Row(rows, level)
    for _, row in ipairs(rows) do
        if level >= row[1] and level <= row[2] then return row end
    end
end

local function Metadata(reference)
    if not C_Item or not C_Item.GetItemInfo or not C_Item.GetDetailedItemLevelInfo then return nil end
    local name, _, quality, _, _, _, _, _, slot, _, vendor, class, _, _, expansion = C_Item.GetItemInfo(reference)
    if not Public(name) or type(name) ~= "string" or not Number(quality, 0)
        or not Public(slot) or type(slot) ~= "string" or not Number(vendor, 0)
        or not Number(class, 0) or not Number(expansion, 0) then return nil end
    local item = { quality = quality, slot = slot, vendor = vendor, class = class, expansion = expansion }
    if excludedSlot[slot] or (class ~= 2 and class ~= 4) or expansion ~= 0
        or (quality ~= 2 and quality ~= 3 and quality ~= 4) then return item end
    local _, _, level = C_Item.GetDetailedItemLevelInfo(reference)
    if not Number(level, 1) then return nil end
    item.level = level
    return item
end

local function Evaluate(item)
    if not item then return nil end
    local quality, level, vendor, class = item.quality, item.level, item.vendor, item.class
    if excludedSlot[item.slot] or (class ~= 2 and class ~= 4) or item.expansion ~= 0
        or (quality ~= 2 and quality ~= 3 and quality ~= 4) then return false end
    if level > 65 then return false end
    local gross, safe = 0, disenchant.Safe()
    if quality == 2 then
        if class == 2 and level >= 21 and level <= 30 then return false end
        local row = Row(uncommon, level)
        if not row then return false end
        local dust, essence = Price(row[3]), Price(row[4])
        if not dust or not essence then return nil end
        local weapon = class == 2
        if safe then
            gross = math.min(dust * row[11], essence * row[12])
        else
            gross = dust * row[weapon and 8 or 6] + essence * row[weapon and 9 or 7]
        end
        if row[5] then
            local shard = Price(row[5])
            if not shard then return nil end
            local chance = weapon and row[10] or (level >= 21 and level <= 25 and .1 or .05)
            gross = safe and math.min(gross, shard) or gross + shard * chance
        end
    elseif quality == 3 then
        local row = Row(rare, level)
        if not row then return false end
        for i = 3, #row, 2 do
            local price = Price(row[i])
            if not price then return nil end
            -- All supported rare outcomes yield one shard or one crystal.
            if safe then gross = i == 3 and price or math.min(gross, price)
            else gross = gross + price * row[i + 1] end
        end
    elseif quality == 4 then
        local row = Row(epic, level)
        if not row then return false end
        local price = Price(row[3])
        if not price then return nil end
        gross = price * row[safe and 5 or 4]
    else return false end
    if not Number(gross, 0) then return nil end
    -- Conservative sale-fee allowance; saved market prices can be stale and
    -- material sales are not guaranteed. Relisting/deposit losses are excluded.
    return math.floor(gross * .85), math.floor(gross), vendor
end

function disenchant.Estimate(reference, itemCache)
    if not disenchant.Enabled() or not Public(reference) then return nil end
    local kind, id = type(reference)
    if kind == "number" and Number(reference, 1) and reference == math.floor(reference) then id = reference
    elseif kind == "string" then id = tonumber(reference:match("item:(%d+)")) end
    if not Number(id, 1) or id >= 200000 or excluded[id] then return nil end
    local cache
    if itemCache then
        cache = itemCache.profitMasterDisenchant
        if not cache or cache.generation ~= generation then
            cache = { generation = generation, values = {} }
            itemCache.profitMasterDisenchant = cache
        end
        local result = cache.values[reference]
        if result == false then return nil end
        if result then return result[1], result[2], result[3] end
    end
    -- Keep only public, complete metadata for this exact reference in the scan
    -- cache. Material-price refreshes must not depend on native item-cache residency.
    local metadata = itemCache and itemCache.profitMasterDisenchantMetadata
    local item = metadata and metadata[reference]
    if not item then
        item = Metadata(reference)
        if item and itemCache then
            if not metadata then metadata = {}; itemCache.profitMasterDisenchantMetadata = metadata end
            metadata[reference] = item
        end
    end
    local net, gross, vendor = Evaluate(item)
    if net == false then
        if cache then cache.values[reference] = false end
        return nil
    end
    -- Unknown material prices stay fixed until ResetCache advances the generation.
    -- Missing item metadata may still arrive through the existing item loader.
    if cache and item then cache.values[reference] = net ~= nil and { net, gross, vendor } or false end
    return net, gross, vendor, item == nil
end

function disenchant.Recommendation(link)
    local net, _, vendor, pending = disenchant.Estimate(link)
    if net == nil then return nil, pending end
    if net - vendor >= 3 then return "disenchant" end
    if vendor - net >= 3 then return "vendor" end
    return nil
end

function disenchant.ShouldMark(link)
    local recommendation, pending = disenchant.Recommendation(link)
    return recommendation == "disenchant", pending
end
