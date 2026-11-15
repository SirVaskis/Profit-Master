local _, addon = ...
local markers = {}
addon.BagMarkers = markers

local overlays, eventFrame, hooked, baganatorAPI = {}, nil, false, nil
local baganatorRefreshReasons
local lastEnabled, priceUpdatesRegistered, hideHooked
local pendingButtons, pendingIDs, watchingMetadata = {}, {}, false
local active = false
local EVENTS = { "ADDON_LOADED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
    "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

local function Forbidden(frame)
    return frame.IsForbidden and frame:IsForbidden()
end

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function UpdateIcon(icon, advice)
    local texture
    if advice == "vendor" then
        if icon.profitMasterAdvice ~= advice then icon:SetAtlas("bags-junkcoin") end
    else
        texture = addon.Disenchant.Icon()
        if icon.profitMasterAdvice ~= advice or icon.profitMasterTexture ~= texture then
            icon:SetTexture(texture)
            -- A previous atlas can supply cropped coordinates. Spell art uses
            -- the complete texture when the same region switches back to DE.
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    icon.profitMasterAdvice, icon.profitMasterTexture = advice, texture
    return advice == "vendor" or texture ~= nil
end

local function SetMarked(button, advice)
    local marked = advice == "disenchant" or advice == "vendor"
    local overlay = overlays[button]
    if not overlay and marked then
        -- Regions cannot receive clicks; the normal bag button stays untouched.
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
        overlay = { icon = icon }
        overlays[button] = overlay
    end
    if overlay and marked then
        marked = UpdateIcon(overlay.icon, advice)
    end
    if overlay and overlay.marked ~= marked then
        overlay.icon:SetShown(marked)
        overlay.marked = marked
    end
end

local function WatchPending(button, id, link, pending)
    local previous = pendingButtons[button]
    if previous and pending and previous.id == id and previous.link == link then return end
    if previous then
        pendingIDs[previous.id] = pendingIDs[previous.id] - 1
        if pendingIDs[previous.id] == 0 then pendingIDs[previous.id] = nil end
        pendingButtons[button] = nil
    end
    if pending and id then
        pendingButtons[button] = { id = id, link = link }
        pendingIDs[id] = (pendingIDs[id] or 0) + 1
    end
    local wanted = next(pendingIDs) ~= nil
    if eventFrame and watchingMetadata ~= wanted then
        watchingMetadata = wanted
        for _, name in ipairs({ "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
            if wanted then eventFrame:RegisterEvent(name) else eventFrame:UnregisterEvent(name) end
        end
    end
end

local function UpdateButton(button, de)
    local advice, pending, link, id = nil, false
    if de and de.Recommendation and button.GetBagID and button.GetID then
        local bag, slot = button:GetBagID(), button:GetID()
        if Public(bag) and Public(slot) and type(bag) == "number" and type(slot) == "number"
            and type(NUM_TOTAL_BAG_FRAMES) == "number" and bag >= 0 and bag <= NUM_TOTAL_BAG_FRAMES and slot >= 1 then
            link = C_Container.GetContainerItemLink(bag, slot)
            if Public(link) and type(link) == "string" then
                local result
                result, pending = de.Recommendation(link)
                if Public(result) and (result == "disenchant" or result == "vendor") then advice = result end
                pending = Public(pending) and pending == true
                if pending then id = tonumber(link:match("item:(%d+)")) end
            end
        end
    end
    WatchPending(button, id, link, pending)
    SetMarked(button, advice)
end

local function RegisterBaganator()
    if baganatorAPI or not Baganator or not Baganator.API
        or type(Baganator.API.RegisterCornerWidget) ~= "function"
        or type(Baganator.API.RequestItemButtonsRefresh) ~= "function"
        or not Baganator.Constants or not Baganator.Constants.RefreshReason
        or type(Baganator.Constants.RefreshReason.ItemWidgets) ~= "number" then return end
    baganatorAPI = Baganator.API
    baganatorRefreshReasons = { Baganator.Constants.RefreshReason.ItemWidgets }
    baganatorAPI.RegisterCornerWidget("Vendor / disenchant advice", "profitmaster_disenchant", function(icon, details)
        if not active then return false end
        if InCombatLockdown and InCombatLockdown() then return false end
        local de = addon.Disenchant
        if not de or not de.Enabled() then return false end
        if not Public(details) or type(details) ~= "table" or not Public(details.itemLink)
            or type(details.itemLink) ~= "string" then return false end
        if not de.Recommendation then return false end
        local result, pending = de.Recommendation(details.itemLink)
        -- The public widget API treats nil as data not ready and retries through
        -- its own readiness path. Do not broadcast a whole-bag refresh per load.
        if Public(pending) and pending == true then return nil end
        if Public(result) and (result == "disenchant" or result == "vendor") then
            if UpdateIcon(icon, result) then return true end
            return nil -- The recommendation is known; the spell icon is not ready.
        end
        return false
    end, function()
        -- The public API reparents this owned region into the selected corner.
        -- We never inspect Baganator buttons or change their scripts/attributes.
        local icon = eventFrame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        UpdateIcon(icon, "disenchant")
        icon:Hide()
        return icon
    end, { corner = "top_right", priority = 1 })
end

function markers.Refresh(nativeUpdate)
    if not active then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local de = addon.Disenchant
    local enabled = de and de.Enabled() or false
    local wasEnabled = lastEnabled
    lastEnabled = enabled
    -- Price owners invalidate their caches when data changes. Opening or moving
    -- bags must not discard the material prices being used by an active scan.
    if not enabled then
        if wasEnabled then
            for button in pairs(pendingButtons) do WatchPending(button) end
            for button in pairs(overlays) do
                if not Forbidden(button) then SetMarked(button, false) end
            end
            if baganatorAPI then baganatorAPI.RequestItemButtonsRefresh(baganatorRefreshReasons) end
        end
        return
    end
    local visited = {}
    local function RefreshContainer(container)
        if not container or Forbidden(container) or not container:IsShown()
            or type(container.EnumerateValidItems) ~= "function" then return end
        for _, button in container:EnumerateValidItems() do
            if button and not Forbidden(button) then
                visited[button] = true
                UpdateButton(button, de)
            end
        end
    end
    -- These are the Blizzard frames instantiated by Forever's ContainerFrame.xml.
    -- Baganator uses its public widget API; other replacements need their own
    -- verified integration rather than arbitrary searches through button frames.
    RefreshContainer(ContainerFrameCombinedBags)
    if type(NUM_CONTAINER_FRAMES) == "number" then
        for i = 1, NUM_CONTAINER_FRAMES do RefreshContainer(_G["ContainerFrame" .. i]) end
    end
    for button in pairs(overlays) do
        if not visited[button] and not Forbidden(button) then SetMarked(button, false) end
    end
    for button in pairs(pendingButtons) do if not visited[button] then WatchPending(button) end end
    -- Baganator already refreshes its widgets for native inventory changes.
    -- Only our own value/option changes need an additional global refresh.
    if baganatorAPI and (not nativeUpdate or not wasEnabled) then
        baganatorAPI.RequestItemButtonsRefresh(baganatorRefreshReasons)
    end
end

local function ConnectPriceUpdates()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if priceUpdatesRegistered or not api or type(api.RegisterForDBUpdate) ~= "function" then return end
    priceUpdatesRegistered = true
    api.RegisterForDBUpdate("ProfitMaster", function()
        if not active then return end
        local de = addon.Disenchant
        if not de or not de.Enabled() then return end
        de.ResetCache()
        markers.Refresh()
    end)
end

local function MetadataReady(id, success)
    if not active then return end
    if not Public(id) or type(id) ~= "number" or not pendingIDs[id]
        or not Public(success) or success ~= true or (InCombatLockdown and InCombatLockdown()) then return end
    local de = addon.Disenchant
    if not de or not de.Enabled() then return end
    local buttons = {}
    for button, pending in pairs(pendingButtons) do
        if pending.id == id then buttons[#buttons + 1] = button end
    end
    -- Re-read only the affected visible slots. Moving/recycling a button cannot
    -- apply an old item's verdict, and unrelated scan loads do no bag work.
    for _, button in ipairs(buttons) do
        if not Forbidden(button) and button:IsShown() then UpdateButton(button, de)
        else WatchPending(button) end
    end
end

local function InstallHook()
    if not hooked and type(ContainerFrame_GenerateFrame) == "function" then
        -- This post-hook observes finished slot assignment. It replaces no scripts,
        -- clicks, attributes or protected behavior on the Blizzard bag buttons.
        hooksecurefunc("ContainerFrame_GenerateFrame", function() markers.Refresh(true) end)
        hooked = true
    end
    if not hideHooked and type(ContainerFrame_OnHide) == "function" then
        hooksecurefunc("ContainerFrame_OnHide", function() markers.Refresh(true) end)
        hideHooked = true
    end
    RegisterBaganator()
    ConnectPriceUpdates()
    if hooked and baganatorAPI and priceUpdatesRegistered then eventFrame:UnregisterEvent("ADDON_LOADED") end
end

function markers.Initialize()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, id, success)
        if not active then return end
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            MetadataReady(id, success)
            return
        end
        InstallHook()
        if event ~= "ADDON_LOADED" or baganatorAPI then markers.Refresh(event == "BAG_UPDATE_DELAYED") end
    end)
end

function markers.SetActive(enabled)
    enabled = enabled == true
    if active == enabled then return end
    markers.Initialize()
    active = enabled
    if active then
        for i = 1, 3 do eventFrame:RegisterEvent(EVENTS[i]) end
        InstallHook()
        markers.Refresh()
    else
        for button in pairs(pendingButtons) do WatchPending(button) end
        for button in pairs(overlays) do
            if not Forbidden(button) then SetMarked(button, false) end
        end
        for _, name in ipairs(EVENTS) do eventFrame:UnregisterEvent(name) end
        watchingMetadata, lastEnabled = false, false
        if baganatorAPI then baganatorAPI.RequestItemButtonsRefresh(baganatorRefreshReasons) end
    end
end
