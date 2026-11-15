-- Offline bag-overlay behavior checks. No game input, item use or frame polling.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local frames, hooked, combat, cacheResets, predicateCalls, containerReads = {}, 0, false, 0, 0, 0
local secret = {}
issecretvalue = function(value) return value == secret end
InCombatLockdown = function() return combat end
local function Region()
    return {
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetPoint = function(self, ...) self.point = { ... } end,
        SetTexture = function(self, value)
            self.texture, self.atlas = value, nil
            self.textureUpdates = (self.textureUpdates or 0) + 1
        end,
        SetAtlas = function(self, value)
            self.atlas, self.texture = value, nil
            self.coordinates = { .1, .9, .1, .9 }
            self.atlasUpdates = (self.atlasUpdates or 0) + 1
        end,
        SetTexCoord = function(self, ...) self.coordinates = { ... } end,
        SetText = function(self, value) self.text = value end,
        SetShown = function(self, value) self.shown = value; self.updates = (self.updates or 0) + 1 end,
        Hide = function(self) self.shown = false end,
    }
end
local function Button(bag, slot)
    local button = { bag = bag, slot = slot, regions = {}, forbidden = false, scripts = { OnClick = function() end } }
    function button:IsForbidden() return self.forbidden end
    function button:GetBagID() check(not self.forbidden, "forbidden button is never inspected"); return self.bag end
    function button:GetID() return self.slot end
    function button:IsShown() return self.shown ~= false end
    function button:CreateTexture()
        check(not self.forbidden and not combat, "regions are created only on permitted buttons outside combat")
        local region = Region(); self.regions[#self.regions + 1] = region; return region
    end
    button.CreateFontString = button.CreateTexture
    return button
end
local function Container(buttons)
    return {
        shown = true, forbidden = false, items = buttons,
        IsForbidden = function(self) return self.forbidden end,
        IsShown = function(self) return self.shown end,
        EnumerateValidItems = function(self) check(not self.forbidden, "forbidden container is never inspected"); return ipairs(self.items) end,
    }
end
function CreateFrame(kind)
    check(kind == "Frame", "module creates only its private event frame")
    local frame = { events = {} }
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:UnregisterEvent(name) self.events[name] = nil end
    function frame:SetScript(name, callback) check(name == "OnEvent", "no polling or input scripts are installed"); self.callback = callback end
    function frame:CreateTexture() return Region() end
    frames[#frames + 1] = frame
    return frame
end
ContainerFrame_GenerateFrame = function() end
function hooksecurefunc(name, callback)
    check(name == "ContainerFrame_GenerateFrame", "only the verified finished bag-layout function is post-hooked")
    hooked = hooked + 1
    local original = _G[name]
    _G[name] = function(...) original(...); callback(...) end
end
NUM_TOTAL_BAG_FRAMES, NUM_CONTAINER_FRAMES = 4, 2
local combined, separate, forbidden, external = Button(0, 1), Button(1, 1), Button(1, 2), Button(2, 1)
forbidden.forbidden = true
ContainerFrameCombinedBags = Container({ combined })
ContainerFrame1 = Container({ separate, forbidden })
ContainerFrame2 = Container({ Button(-1, 1) }) -- Bank is outside the requested held bags.
local inventory = { [0] = { "item:good" }, [1] = { "item:bad" } }
C_Container = { GetContainerItemLink = function(bag, slot)
    containerReads = containerReads + 1
    check(bag >= 0 and bag <= 4, "bank and invalid slots are never passed to container APIs")
    return inventory[bag] and inventory[bag][slot]
end }
local enabled, metadataPending = true, {}
local profitable = { ["item:good"] = true }
local vendorPreferred, recommendationOverride = {}, {}
local addon = { Disenchant = {
    Enabled = function() return enabled end,
    Icon = function() return 990 end,
    ResetCache = function() cacheResets = cacheResets + 1 end,
    ShouldMark = function() error("bag advice must not use the old DE-only boolean contract") end,
    Recommendation = function(link)
        predicateCalls = predicateCalls + 1
        if link == "item:restrictedResult" then return secret end
        if enabled and metadataPending[link] then return nil, true end
        if not enabled then return nil end
        if recommendationOverride[link] ~= nil then return recommendationOverride[link] end
        if vendorPreferred[link] then return "vendor" end
        if profitable[link] then return "disenchant" end
    end,
} }
local priceCallback, priceRegistrations
priceRegistrations = 0
Auctionator = { API = { v1 = { RegisterForDBUpdate = function(caller, callback)
    check(caller == "ProfitMaster", "price updates register through Auctionator's public caller-identified API")
    priceRegistrations = priceRegistrations + 1
    priceCallback = callback
end } } }
assert(loadfile("addons/ProfitMaster/BagMarkers.lua"))("ProfitMaster", addon)
addon.BagMarkers.Initialize()
check(hooked == 0 and #frames == 1 and next(frames[1].events) == nil
    and containerReads == 0 and predicateCalls == 0,
    "initialization alone does no bag work until the login handler activates advice")
addon.BagMarkers.SetActive(true)
check(hooked == 1 and #frames == 1 and #combined.regions == 1 and #separate.regions == 0,
    "only eligible standard bag buttons receive reusable regions")
check(combined.regions[1].shown and combined.regions[1].texture == 990 and combined.regions[1].text == nil
    and combined.regions[1].point[1] == "TOPRIGHT", "a single icon identifies the top-right corner without any text label")
check(#forbidden.regions == 0 and #external.regions == 0,
    "forbidden and unrelated third-party buttons are untouched")
local originalClick = combined.scripts.OnClick
local initialUpdates, beforeReset = combined.regions[1].updates, cacheResets
addon.BagMarkers.Initialize()
addon.BagMarkers.Refresh()
check(hooked == 1 and #frames == 1 and #combined.regions == 1 and combined.regions[1].updates == initialUpdates,
    "repeated refresh/init reuse regions, avoid duplicate hooks and change no identical visibility")
check(cacheResets == beforeReset, "bag refresh preserves the material-price cache owned by scan/config changes")
check(combined.scripts.OnClick == originalClick, "normal item-click behavior is never replaced")

inventory[0][1], inventory[1][1] = "item:bad", "item:good"
frames[1].callback(nil, "BAG_UPDATE_DELAYED")
check(not combined.regions[1].shown and separate.regions[1].shown,
    "moving items removes stale marks and marks the new slot")
enabled = false
addon.BagMarkers.Refresh()
check(not separate.regions[1].shown, "disabling the option hides all markers")
enabled, inventory[0][1] = true, "item:good"
combat = true
local beforeCombatReset, beforeCombatCalls = cacheResets, predicateCalls
ContainerFrame_GenerateFrame()
check(not combined.regions[1].shown and cacheResets == beforeCombatReset and predicateCalls == beforeCombatCalls,
    "combat refresh skips UI changes and valuation entirely")
combat = false
frames[1].callback(nil, "PLAYER_REGEN_ENABLED")
check(combined.regions[1].shown, "leaving combat refreshes deferred indicators")
ContainerFrameCombinedBags.shown = false
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown, "hidden/recycled bag containers cannot leave stale marks")
ContainerFrameCombinedBags.shown = true
ContainerFrame_GenerateFrame()
check(combined.regions[1].shown, "opening a generated bag refreshes current slot assignments")

local beforeSecretCalls = predicateCalls
inventory[0][1], inventory[1][1] = secret, nil
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown and predicateCalls == beforeSecretCalls,
    "restricted links and empty slots never reach valuation")
inventory[0][1] = "item:restrictedResult"
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown, "restricted predicate results never display an authoritative marker")
inventory[0][1], combined.bag = "item:good", secret
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown, "restricted bag identifiers never reach container APIs")
combined.bag = 0
ContainerFrameCombinedBags.forbidden = true
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown, "forbidden containers are skipped without inspecting their children")
check(frames[1].events.BAG_UPDATE_DELAYED and frames[1].events.PLAYER_REGEN_ENABLED
    and frames[1].events.ADDON_LOADED, "module listens to native changes and permits an optional bag addon to load later")

local widget, widgetRegistrations, baganatorRefreshes = nil, 0, 0
local lastRefreshReasons
Baganator = { Constants = { RefreshReason = { ItemWidgets = 4, Searches = 16 } }, API = {
    RegisterCornerWidget = function(label, id, update, initialize, position)
        widgetRegistrations = widgetRegistrations + 1
        widget = { label = label, id = id, update = update, initialize = initialize, position = position }
    end,
    RequestItemButtonsRefresh = function(reason)
        -- Native Baganator 851 accepts a reason array (or nil for defaults), not
        -- the caller-name string used by Auctionator's unrelated price API.
        local reasons = {}
        for _, entry in ipairs(reason or { Baganator.Constants.RefreshReason.ItemWidgets,
            Baganator.Constants.RefreshReason.Searches }) do reasons[entry] = true end
        lastRefreshReasons = reasons
        baganatorRefreshes = baganatorRefreshes + 1
    end,
} }
local acceptsCallerString, refreshError = pcall(Baganator.API.RequestItemButtonsRefresh, "ProfitMaster")
check(not acceptsCallerString and tostring(refreshError):find("table expected, got string", 1, true),
    "the native-shaped Baganator mock rejects a caller string instead of hiding the live startup error")
frames[1].callback(nil, "ADDON_LOADED", "Baganator")
check(widgetRegistrations == 1 and widget.id == "profitmaster_disenchant"
    and widget.position.corner == "top_right" and widget.position.priority == 1,
    "optional Baganator integration registers one public corner widget with a top-right default")
check(lastRefreshReasons[Baganator.Constants.RefreshReason.ItemWidgets]
    and not lastRefreshReasons[Baganator.Constants.RefreshReason.Searches],
    "bag advice requests only the public item-widget refresh reason")
local icon = widget.initialize()
check(icon.texture == 990 and icon.width == 14 and not icon.shown,
    "Baganator receives a small owned icon region without any button manipulation")
check(widget.update(icon, { itemLink = "item:good" }) == true
    and widget.update(icon, { itemLink = "item:bad" }) == false,
    "Baganator uses the same all-inventory disenchant verdict as standard bags")
enabled = false
check(widget.update(icon, { itemLink = "item:good" }) == false, "disabled option hides the Baganator widget too")
enabled, combat = true, true
check(widget.update(icon, { itemLink = "item:good" }) == false, "Baganator callbacks skip valuation in combat")
combat = false
check(widget.update(icon, secret) == false and widget.update(icon, { itemLink = secret }) == false,
    "restricted Baganator payloads never reach valuation")
local refreshesBefore = baganatorRefreshes
addon.BagMarkers.Refresh()
addon.BagMarkers.Initialize()
check(widgetRegistrations == 1 and baganatorRefreshes == refreshesBefore + 1 and not frames[1].events.ADDON_LOADED,
    "price/option refresh requests the public Baganator refresh path without duplicate registration")

-- Inventory-native updates are already handled by Baganator itself. They must
-- not broadcast another full widget refresh, nor invalidate scan-price caches.
ContainerFrameCombinedBags.forbidden = false
inventory[0][1], inventory[1][1] = "item:good", "item:bad"
local beforeNativeRefresh, beforeNativeReset, beforeNativeReads = baganatorRefreshes, cacheResets, containerReads
for i = 1, 20 do frames[1].callback(nil, "BAG_UPDATE_DELAYED") end
check(baganatorRefreshes == beforeNativeRefresh and cacheResets == beforeNativeReset
    and containerReads == beforeNativeReads + 40 and combined.regions[1].shown,
    "twenty enabled native inventory events update Blizzard slots without any redundant Baganator broadcasts or price invalidation")
ContainerFrame_GenerateFrame()
check(baganatorRefreshes == beforeNativeRefresh,
    "generating a Blizzard bag also avoids a redundant Baganator-wide widget refresh")
enabled = false
local beforeDisableRefresh, beforeDisableReads, beforeDisableCalls = baganatorRefreshes, containerReads, predicateCalls
addon.BagMarkers.Refresh()
check(baganatorRefreshes == beforeDisableRefresh + 1 and not combined.regions[1].shown
    and containerReads == beforeDisableReads and predicateCalls == beforeDisableCalls,
    "disabling clears existing indicators with one API refresh and no bag-item valuation")
local beforeDisabledRefresh, beforeDisabledReset, beforeDisabledReads, beforeDisabledCalls =
    baganatorRefreshes, cacheResets, containerReads, predicateCalls
for i = 1, 20 do
    frames[1].callback(nil, "BAG_UPDATE_DELAYED")
    widget.update(icon, { itemLink = "item:good" })
end
check(baganatorRefreshes == beforeDisabledRefresh and cacheResets == beforeDisabledReset
    and containerReads == beforeDisabledReads and predicateCalls == beforeDisabledCalls,
    "disabled inventory events and widget callbacks do no container reads, valuation, API broadcasts or cache invalidation")
enabled = true
addon.BagMarkers.Refresh()
check(baganatorRefreshes == beforeDisabledRefresh + 1 and combined.regions[1].shown,
    "re-enabling still refreshes both bag interfaces immediately")
combat = true
inventory[0][1] = "item:bad"
addon.BagMarkers.Refresh()
combat = false
local beforeRegenRefresh = baganatorRefreshes
frames[1].callback(nil, "PLAYER_REGEN_ENABLED")
check(baganatorRefreshes == beforeRegenRefresh + 1 and not combined.regions[1].shown,
    "leaving combat still refreshes deferred native and Baganator indicators")
-- Readiness events are filtered to pending visible standard-bag items. Baganator
-- gets its documented nil-pending result instead of repeated global refreshes.
metadataPending["item:3001"], profitable["item:3001"] = true, true
inventory[0][1] = "item:3001"
addon.BagMarkers.Refresh(true)
check(frames[1].events.ITEM_DATA_LOAD_RESULT and frames[1].events.GET_ITEM_INFO_RECEIVED
    and not combined.regions[1].shown, "missing bag metadata subscribes only while a visible item needs it")
local beforeUnrelatedReads, beforeUnrelatedCalls, beforeUnrelatedRefresh = containerReads, predicateCalls, baganatorRefreshes
for id = 900001, 901000 do frames[1].callback(nil, "ITEM_DATA_LOAD_RESULT", id, true) end
check(containerReads == beforeUnrelatedReads and predicateCalls == beforeUnrelatedCalls
    and baganatorRefreshes == beforeUnrelatedRefresh,
    "one thousand unrelated scan-item events do no bag reads, valuation or global widget refresh")
frames[1].callback(nil, "ITEM_DATA_LOAD_RESULT", 3001, true)
check(frames[1].events.GET_ITEM_INFO_RECEIVED and containerReads == beforeUnrelatedReads + 1
    and not combined.regions[1].shown,
    "a basic-record event rechecks only its slot and waits when full vendor metadata remains missing")
metadataPending["item:3001"] = nil
frames[1].callback(nil, "GET_ITEM_INFO_RECEIVED", 3001, true)
check(combined.regions[1].shown and containerReads == beforeUnrelatedReads + 2
    and not frames[1].events.ITEM_DATA_LOAD_RESULT and not frames[1].events.GET_ITEM_INFO_RECEIVED
    and baganatorRefreshes == beforeUnrelatedRefresh,
    "late full metadata marks just the affected slot and releases both readiness listeners")
local afterReadyReads = containerReads
frames[1].callback(nil, "ITEM_DATA_LOAD_RESULT", 3001, true)
check(containerReads == afterReadyReads, "duplicate metadata completions cannot repeat completed slot work")
metadataPending["item:3002"] = true
inventory[0][1] = "item:3002"
addon.BagMarkers.Refresh(true)
inventory[0][1] = "item:good"
frames[1].callback(nil, "GET_ITEM_INFO_RECEIVED", 3002, true)
check(combined.regions[1].shown and not frames[1].events.GET_ITEM_INFO_RECEIVED,
    "a recycled slot is re-read rather than receiving the old item's metadata verdict")
metadataPending["item:3003"], profitable["item:3003"] = true, true
check(widget.update(icon, { itemLink = "item:3003" }) == nil
    and not frames[1].events.GET_ITEM_INFO_RECEIVED,
    "Baganator receives its documented pending-data return without starting another metadata watcher")
metadataPending["item:3003"] = nil
check(widget.update(icon, { itemLink = "item:3003" }) == true,
    "Baganator's next readiness callback gets the now-current recommendation")

check(priceRegistrations == 1, "repeated initialization and addon-load events register the price listener only once")
local beforePriceReset, beforePriceRefresh = cacheResets, baganatorRefreshes
profitable["item:good"] = false
priceCallback()
check(cacheResets == beforePriceReset + 1 and baganatorRefreshes == beforePriceRefresh + 1
    and not combined.regions[1].shown,
    "an independent Auctionator DB update refreshes current bag recommendations without a Profit Master scan")
enabled = false
addon.BagMarkers.Refresh()
beforePriceReset, beforePriceRefresh = cacheResets, baganatorRefreshes
priceCallback()
check(cacheResets == beforePriceReset and baganatorRefreshes == beforePriceRefresh,
    "price updates do no bag or cache work while the feature is disabled")

-- One existing icon switches advice without creating text, intercepting input,
-- retaining atlas crops, or treating unknown DE values as a sell recommendation.
enabled, vendorPreferred["item:good"], profitable["item:good"] = true, true, false
inventory[0][1] = "item:good"
addon.BagMarkers.Refresh()
check(widget.update(icon, { itemLink = "item:good" }) == true
    and combined.regions[1].atlas == "bags-junkcoin" and icon.atlas == "bags-junkcoin"
    and #combined.regions == 1 and combined.regions[1].text == nil,
    "supported vendor advice uses the native sell coin in both bag UIs with no label")
vendorPreferred["item:good"], profitable["item:good"] = nil, true
addon.BagMarkers.Refresh()
check(widget.update(icon, { itemLink = "item:good" }) == true
    and combined.regions[1].texture == 990 and icon.texture == 990
    and combined.regions[1].atlas == nil and icon.atlas == nil
    and combined.regions[1].coordinates[1] == 0 and combined.regions[1].coordinates[2] == 1
    and combined.regions[1].coordinates[3] == 0 and combined.regions[1].coordinates[4] == 1
    and icon.coordinates[1] == 0 and icon.coordinates[2] == 1
    and icon.coordinates[3] == 0 and icon.coordinates[4] == 1,
    "SELL-to-DE reuse restores full spell texture coordinates in both bag UIs")
local nativeTextureUpdates, widgetTextureUpdates = combined.regions[1].textureUpdates, icon.textureUpdates
addon.BagMarkers.Refresh()
widget.update(icon, { itemLink = "item:good" })
check(combined.regions[1].textureUpdates == nativeTextureUpdates and icon.textureUpdates == widgetTextureUpdates,
    "unchanged advice does not repeat native texture updates")
vendorPreferred["item:good"], profitable["item:good"] = true, false
addon.BagMarkers.Refresh()
widget.update(icon, { itemLink = "item:good" })
local nativeAtlasUpdates, widgetAtlasUpdates = combined.regions[1].atlasUpdates, icon.atlasUpdates
addon.BagMarkers.Refresh()
widget.update(icon, { itemLink = "item:good" })
check(combined.regions[1].atlasUpdates == nativeAtlasUpdates and icon.atlasUpdates == widgetAtlasUpdates,
    "unchanged vendor advice does not repeat atlas updates")
vendorPreferred["item:good"] = nil
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown and widget.update(icon, { itemLink = "item:good" }) == false,
    "ties or unsupported/unknown recommendations remove an old SELL icon instead of implying a vendor sale")
recommendationOverride["item:good"] = false
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown and widget.update(icon, { itemLink = "item:good" }) == false,
    "a false or unexpected verdict cannot be misinterpreted as vendor advice")
recommendationOverride["item:good"], profitable["item:good"] = nil, true
addon.Disenchant.Icon = function() return nil end
addon.BagMarkers.Refresh()
check(not combined.regions[1].shown and widget.update(icon, { itemLink = "item:good" }) == nil,
    "an unavailable spell texture stays visually unmarked and Baganator waits through its readiness path")
addon.Disenchant.Icon = function() return 990 end
addon.BagMarkers.Refresh()
check(combined.regions[1].shown and combined.regions[1].texture == 990
    and widget.update(icon, { itemLink = "item:good" }) == true and icon.texture == 990,
    "existing native and Baganator icon regions recover when the actual spell texture becomes ready")
addon.BagMarkers.SetActive(false)
check(next(frames[1].events) == nil and not combined.regions[1].shown,
    "explicitly suspending the bag module hides native markers and unsubscribes bag/metadata events")
local idleReads, idleCalls, idleResets, idleRefreshes = containerReads, predicateCalls, cacheResets, baganatorRefreshes
for i = 1, 1000 do
    ContainerFrame_GenerateFrame()
    frames[1].callback(nil, "BAG_UPDATE_DELAYED")
    frames[1].callback(nil, "GET_ITEM_INFO_RECEIVED", 3001, true)
    priceCallback()
    check(widget.update(icon, { itemLink = "item:good" }) == false,
        "inactive Baganator advice returns before valuation")
end
check(containerReads == idleReads and predicateCalls == idleCalls and cacheResets == idleResets
    and baganatorRefreshes == idleRefreshes,
    "one thousand closed-house hook/event/price cycles do no reads, valuation, cache resets or broadcasts")
addon.BagMarkers.SetActive(true)
check(combined.regions[1].shown and hooked == 1 and priceRegistrations == 1 and widgetRegistrations == 1,
    "resuming advice does not duplicate hooks, price listeners or corner widgets")
print("Profit Master bag markers: " .. checks .. " offline assertions passed (Lua 5.1).")
