-- Run from the workspace root. No WoW process or real purchases are involved.
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error(debug.traceback(message, 2), 0) end
end

local frames, timers, buttons = {}, {}, {}
local hardwareClick, purchaseWindow, dispatch, blockNext, throwNext, completeNext
local bidAttempts = 0
local textWrites, moneyFormats = 0, 0
local popup
StaticPopupDialogs = {}
CANCEL = "Cancel"
ERR_AUCTION_DATABASE_ERROR = "Internal auction error."
function StaticPopup_Show(which, text, _, data)
    popup = { which = which, text = text, data = data, shown = true }
    popup.button1 = { SetEnabled = function(self, enabled) self.enabled = enabled end,
        SetText = function(self, value) self.text = value end }
    function popup:GetButton1() return self.button1 end
    function popup:SetText(value) self.text = value end
    function popup:Resize() end
    function popup:IsShown() return self.shown end
    popup.editBox = {
        SetText = function(self, value)
            self.text = value
            local callback = StaticPopupDialogs[popup.which].EditBoxOnTextChanged
            if callback then callback(self, popup.data) end
        end,
        GetText = function(self) return self.text end,
        HighlightText = function() end,
        GetParent = function() return popup end,
    }
    function popup:GetEditBox() return self.editBox end
    function popup:Hide() StaticPopup_Hide(self.which) end
    local onShow = StaticPopupDialogs[which].OnShow
    if onShow then onShow(popup, data) end
    return popup
end
function StaticPopup_Hide(which)
    if popup and popup.shown and popup.which == which then
        local hidden = popup
        hidden.shown = false
        local callback = StaticPopupDialogs[which].OnHide
        if callback then callback(hidden, hidden.data) end
    end
end
local function cancelPopup()
    if popup and popup.shown then StaticPopup_Hide(popup.which) end
end
local function confirmPopup()
    check(popup and popup.shown, "exact-price purchase confirmation must be visible")
    local current = popup
    hardwareClick = true
    local keepOpen = StaticPopupDialogs[current.which].OnAccept(current, current.data)
    hardwareClick = false
    if current.shown and not keepOpen then StaticPopup_Hide(current.which) end
end
local methods = {}
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:RegisterEvent(name) self.events[name] = true end
function methods:UnregisterEvent(name) self.events[name] = nil end
function methods:SetText(text) self.text = text; textWrites = textWrites + 1 end
function methods:GetText() return self.text or "" end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:GetNumLines() local _, lines = (self.text or ""):gsub("\n", "\n"); return lines + 1 end
function methods:HasFocus() return self.focused == true end
function methods:SetFocus()
    if self.focused then return end
    self.focused = true
    if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
end
function methods:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function methods:SetNumeric(value) self.numeric = value end
function methods:SetAutoFocus(value) self.autoFocus = value end
function methods:SetMaxLetters(value) self.maxLetters = value end
function methods:HighlightText() self.highlighted = true end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return 10000 end
function methods:SetEnabled(value) self.enabled = not not value end
function methods:IsShown()
    return self.shown ~= false and (not self.parent or self.parent:IsShown())
end
function methods:Show()
    local wasShown = self:IsShown()
    self.shown = true
    if not wasShown and self:IsShown() and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    if self.shown == false then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) self.shown = value end
function methods:IsObjectType(kind) return self.kind == kind end
function methods:SetTitle(text) self.title = text end
function methods:CreateFontString() return CreateFrame("FontString", nil, self) end
function methods:CreateTexture() return CreateFrame("Texture", nil, self) end
function methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function methods:SetValue(value)
    self.value = value
    self.valueUpdates = (self.valueUpdates or 0) + 1
end
for _, name in ipairs({ "SetSize", "SetPoint", "SetWidth", "SetHeight", "SetJustifyH",
    "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag", "SetBackdrop",
    "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "SetHitRectInsets",
    "SetStatusBarTexture", "SetStatusBarColor", "SetAllPoints", "SetColorTexture" }) do
    methods[name] = function() end
end
for _, name in ipairs({ "SetMultiLine", "SetFontObject", "EnableMouseWheel", "SetCursorPosition" }) do
    methods[name] = function() end
end
ChatFontNormal = "ChatFontNormal"
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ kind = kind, template = template, scripts = {}, events = {}, parent = parent, shown = true }, { __index = methods })
    frames[#frames + 1] = frame
    if kind == "Button" then buttons[#buttons + 1] = frame end
    return frame
end
local function click(button)
    check(button and button.enabled ~= false, "button must be enabled")
    button.scripts.OnClick(button)
end
local function findButton(text)
    for _, button in ipairs(buttons) do
        if button.text == text and button:IsShown() and button.enabled ~= false then
            return button
        end
    end
end
local function timeout()
    local queue = timers
    timers = {}
    for _, timer in ipairs(queue) do
        if not timer.cancelled then timer.callback() end
    end
end
local function drain()
    for _ = 1, 50 do
        if #timers == 0 then return end
        timeout()
    end
    error("timer did not terminate")
end
local function runImmediate()
    for _ = 1, 100 do
        local queue, ran = timers, false
        timers = {}
        for _, timer in ipairs(queue) do
            if not timer.cancelled then
                if timer.delay == 0 then timer.callback(); ran = true
                else timers[#timers + 1] = timer end
            end
        end
        if not ran then return end
    end
    error("immediate processing did not terminate")
end
C_Timer = { NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
    timers[#timers + 1] = timer
    return timer
end }
UIParent = CreateFrame("Frame")
AuctionHouseFrame = CreateFrame("Frame")
AuctionHouseFrame.Tabs = { CreateFrame("Button", nil, AuctionHouseFrame) }
local builtinContent = CreateFrame("Frame", nil, AuctionHouseFrame)
function AuctionHouseFrame:SetDisplayMode(mode)
    self.displayMode = mode
    builtinContent:SetShown(#mode > 0)
end
function hooksecurefunc(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
PanelTemplates_TabResize = function() end
PanelTemplates_SelectTab = function(tab) tab.selected = true end
PanelTemplates_DeselectTab = function(tab) tab.selected = false end
local ahLibrary = {}
LibStub = setmetatable({ NewLibrary = function(_, name)
    assert(name == "LibAHTab-1-0")
    return ahLibrary
end }, { __call = function(_, name)
    assert(name == "LibAHTab-1-0")
    return ahLibrary
end })
local libraryFile = assert(os.getenv("PROFITMASTER_AHTAB_SOURCE"), "Set PROFITMASTER_AHTAB_SOURCE to Auctionator's LibAHTab.lua")
assert(loadfile(libraryFile))()
SlashCmdList = {}
Enum = { AuctionHouseSortOrder = { Buyout = 4 }, PlayerInteractionType = { Auctioneer = 21 },
    AuctionHouseError = { DatabaseError = 10 } }
GetMoneyString = function(value) moneyFormats = moneyFormats + 1; return tostring(value) end
local now = 1000
time = function() return now end
GetTime = function() return now end
GetTimePreciseSec = function() return GetTime() end
C_Spell = { GetSpellTexture = function(id)
    check(id == 13262, "recommendation icons request the Disenchant spell")
    return 880
end }
local money, throttle, commodity, full = 100000, true, false, true
local keyInfoAvailable = true
GetMoney = function() return money end
local itemLookups = 0
local values = { ["item:1"] = 100, ["item:1:variant"] = 60, ["item:2"] = 200, ["item:3"] = 0 }
C_Item = { GetItemInfo = function(link)
    itemLookups = itemLookups + 1
    if type(link) == "number" then link = "item:" .. link end
    local price = values[link]
    if price ~= nil then return link, link, 1, 1, 1, "", "", 20, "", 1, price end
end }
local itemRequests = {}
C_Item.RequestLoadItemDataByID = function(id) itemRequests[#itemRequests + 1] = id end
local results, bids, queries, more = {}, {}, 0, 0
local exactQueries, queriedKey = 0, nil
local refreshes, refreshedKey = 0, nil
local resultReads = 0
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
    GetItemKeyInfo = function() if keyInfoAvailable then return { isCommodity = commodity } end end,
    IsThrottledMessageSystemReady = function() return throttle end,
    SendSellSearchQuery = function() queries = queries + 1 end,
    SendSearchQuery = function(key) exactQueries, queriedKey = exactQueries + 1, key end,
    RefreshItemSearchResults = function(key) refreshes, refreshedKey = refreshes + 1, key end,
    GetNumItemSearchResults = function() return #results end,
    GetItemSearchResultInfo = function(_, i) resultReads = resultReads + 1; return results[i] end,
    HasFullItemSearchResults = function() return full end,
    RequestMoreItemSearchResults = function() more = more + 1 end,
    PlaceBid = function(id, amount)
        check(hardwareClick, "restricted purchase only runs in confirmation click, never query event or timer")
        for _, row in ipairs(purchaseWindow.rows) do
            if row.deal then check(row:IsShown(), "deal rows are still visible when purchase is submitted") end
        end
        check(popup and popup.shown, "confirmation frame is not hidden before the purchase call")
        bidAttempts = bidAttempts + 1
        if throwNext then
            throwNext = false
            error("simulated purchase handler interruption")
        end
        if blockNext then
            local event = blockNext
            blockNext = nil
            if type(event) == "table" then dispatch(unpack(event))
            else dispatch(event, "ProfitMaster", "C_AuctionHouse.PlaceBid()") end
            return
        end
        bids[#bids + 1] = { id, amount }
        if completeNext then
            completeNext = false
            dispatch("AUCTION_HOUSE_PURCHASE_COMPLETED", id)
        end
    end,
}
local listener, subscribed
local scanEvents = { ScanStart = "start", ScanProgress = "progress", ScanComplete = "complete", ScanFailed = "failed" }
local browseEvents = { ScanStart = "browse_start", ScanProgress = "browse_progress", ScanComplete = "browse_complete", ScanFailed = "browse_failed" }
local scans, browseScans, preferFull, canFullScan = 0, 0, true, true
Auctionator = {
    Variables = { GetConnectedRealmRoot = function() return "TestPvE" end },
    FullScan = { Events = scanEvents },
    IncrementalScan = { Events = browseEvents },
    Config = { Options = { REPLICATE_SCAN = "replicate" }, Get = function() return preferFull end },
    EventBus = { Register = function(_, receiver, eventNames)
        listener, subscribed = receiver, {}
        for _, name in ipairs(eventNames) do subscribed[name] = true end
    end, Unregister = function(_, receiver, eventNames)
        check(receiver == listener, "only Profit Master's own Auctionator listener is removed")
        for _, name in ipairs(eventNames) do subscribed[name] = nil end
    end },
    State = { IncrementalScanFrameRef = {
        doingFullScan = false,
        InitiateScan = function()
            browseScans = browseScans + 1
            listener:ReceiveEvent("browse_start")
        end,
    }, FullScanFrameRef = {
        CanInitiate = function() return canFullScan end,
        InitiateScan = function()
            scans = scans + 1
            listener:ReceiveEvent("start")
        end,
    } },
}
local addon = {}
C_AddOns = { GetAddOnMetadata = function(name, field)
    if field == "Version" then return name == "ProfitMaster" and "0.1.17" or "346" end
end }
local manifestFile = assert(io.open("addons/ProfitMaster/ProfitMaster.toc"))
local manifest = manifestFile:read("*a")
manifestFile:close()
check(manifest:find("\n## Dependencies: Auctionator[\r\n]"), "Auctionator is a required TOC dependency")
check(manifest:find("\n## SavedVariables: ProfitMasterDB[,\r\n]"), "database has a uniquely prefixed SavedVariables declaration")
check(manifest:find("ProfitMasterDebugDB", 1, true), "debug preference and events are declared for native saved-variable persistence")
check(manifest:find("\nOwnedAuctions.lua[\r\n]"), "owned-auction footer is loaded by the shipped manifest")
assert(loadfile("addons/ProfitMaster/History.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/Disenchant.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/Deals.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/Diagnostics.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/BagMarkers.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/OwnedAuctions.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/Settings.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/QueryPace.lua"))("ProfitMaster", addon)
assert(loadfile("addons/ProfitMaster/Listings.lua"))("ProfitMaster", addon)
local deal = addon.Deal("item:1", 20, 1500)
check(deal.profit == 500 and deal.vendor == 2000, "whole-stack copper arithmetic")
check(not addon.Deal("item:1", 1, 100), "equal price excluded")
check(not addon.Deal("item:1", 1, 101), "loss excluded")
check(not addon.Deal("item:1", 1, 99) and not addon.Deal("item:1", 1, 98), "one- and two-copper profits are hidden")
check(addon.Deal("item:1", 1, 97).profit == 3, "exactly three copper remains eligible")
check(not addon.Deal("item:3", 1, 1), "unsellable excluded")
check(not addon.Deal("item:999", 1, 1), "uncached excluded")
check(not addon.Deal("battlepet:1", 1, 1), "pets excluded")
check(not addon.Deal("item:1", 0, 1), "zero quantity excluded")
check(not addon.Deal("item:1", 1, 0), "bid-only auctions excluded")
check(addon.Deal("item:1:variant", 1, 50).profit == 10, "variant-specific vendor value")
check(not addon.Deal("item:1:variant", 1, 70), "base-ID price cannot make variant look profitable")
issecretvalue = function(value) return value == "SECRET" end
check(not addon.Deal("item:1", 1, "SECRET"), "secret prices skipped")
check(not addon.LiveDeal({ containsOwnerItem = "SECRET" }), "secret ownership skipped")
local sorted = { addon.Deal("item:1", 1, 50), addon.Deal("item:2", 1, 50) }
addon.SortDeals(sorted)
check(sorted[1].profit == 150, "descending profit")
check(not addon.LiveDeal({ auctionID = 997, itemLink = "item:1", quantity = 139, buyoutAmount = 98 }),
    "grouped availability cannot lift a two-copper auction above the minimum")
check(addon.LiveDeal({ auctionID = 998, itemLink = "item:1", quantity = 139, buyoutAmount = 97 }).profit == 3,
    "live quote accepts exactly three copper for one auction")
-- Screenshot regression: 139 pouches available does not mean a 3s auction buys
-- 139 pouches. One pouch vendors for 2s50c, so this auction is a loss.
values["item:856"] = 250
local grouped = { auctionID = 856, itemLink = "item:856", quantity = 139, buyoutAmount = 300 }
check(not addon.LiveDeal(grouped), "grouped pouch availability cannot turn a losing auction into profit")
grouped.buyoutAmount = 240
local single = addon.LiveDeal(grouped)
check(single and single.auctionID == 856 and single.quantity == 1 and single.cost == 240
    and single.vendor == 250 and single.profit == 10, "one auction uses one item vendor value regardless of available copies")
grouped.quantity = 138
check(addon.SameListing(single, addon.LiveDeal(grouped)), "other copies selling cannot change this auction's purchase quantity")
grouped.quantity = 0
check(not addon.LiveDeal(grouped), "empty search group cannot produce an auction quote")
grouped.quantity = "SECRET"
check(not addon.LiveDeal(grouped), "restricted grouped availability cannot authorize a purchase")

assert(loadfile("addons/ProfitMaster/ProfitMaster.lua"))("ProfitMaster", addon)
local eventFrame = frames[#frames]
local function event(name, arg, extra) eventFrame.scripts.OnEvent(eventFrame, name, arg, extra) end
dispatch = event
event("ADDON_LOADED", "OtherAddon")
check(ProfitMasterDB == nil, "unrelated load event cannot create saved data")
event("ADDON_LOADED", "ProfitMaster")
-- Legacy purchase fixtures drive each search explicitly. Preparation has its
-- own scenarios, so it must not consume extra native searches in these cases.
addon.Listings.SetEnabled(false)
addon.Listings.SetOneClick(false)
check(ProfitMasterDebugDB and not addon.Diagnostics.Enabled() and ProfitMasterDebugDB.count == 0,
    "debug settings initialize disabled without changing auction history")
check(ProfitMasterDB and ProfitMasterDB.version == 1, "database initializes after its own SavedVariables load event")
do
    local initializeBags = addon.BagMarkers.Initialize
    addon.BagMarkers.Initialize = function() error("simulated unrelated bag startup failure") end
    local succeeded, failure = pcall(event, "PLAYER_LOGIN")
    check(not succeeded and failure:find("simulated unrelated bag startup failure", 1, true),
        "test reproduces an unrelated bag integration interrupting the login handler")
    local ownedListeners, ownedListener = 0, nil
    for _, frame in ipairs(frames) do
        if frame.events.OWNED_AUCTIONS_UPDATED then ownedListeners, ownedListener = ownedListeners + 1, frame end
    end
    check(ownedListeners == 1, "owned-auction listener initializes before an unrelated bag startup can interrupt login")
    check(pcall(function()
        ownedListener.scripts.OnEvent(ownedListener, "AUCTION_HOUSE_SHOW")
        ownedListener.scripts.OnEvent(ownedListener, "OWNED_AUCTIONS_UPDATED")
        ownedListener.scripts.OnEvent(ownedListener, "AUCTION_HOUSE_CLOSED")
    end), "the registered owned-auction listener still receives native events after another integration fails")
    addon.BagMarkers.Initialize = initializeBags
    event("PLAYER_LOGIN")
    ownedListeners = 0
    for _, frame in ipairs(frames) do
        if frame.events.OWNED_AUCTIONS_UPDATED then ownedListeners = ownedListeners + 1 end
    end
    check(ownedListeners == 1, "repeating login after bag startup recovers reuses the owned-auction listener")
end
SlashCmdList.PROFITMASTER()
check(not ahLibrary:DoesIDExist("ProfitMaster"), "slash command cannot create/show a tab before AH opens")
event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 999)
check(not ahLibrary:DoesIDExist("ProfitMaster"), "unrelated interaction does not create AH tab")
event("AUCTION_HOUSE_SHOW")
local window = ahLibrary:GetButton("ProfitMaster").frameRef
purchaseWindow = window
check(window.progress.value == 0 and window.progress.text.text == "Ready to scan", "progress bar has an explicit idle state")
check(window.parent == AuctionHouseFrame and not window:IsShown(), "tab content belongs to AH and starts hidden")
check(#AuctionHouseFrame.Tabs == 1, "Blizzard Tabs array is not modified")
event("AUCTION_HOUSE_SHOW")
event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Auctioneer)
check(#ahLibrary.internalState.Tabs == 1, "repeated open events do not duplicate tab")
click(ahLibrary:GetButton("ProfitMaster"))
check(window:IsShown() and not builtinContent:IsShown(), "actual LibAHTab selects Profit Master and hides native content")
check(window.database.text:find("Database:", 1, true), "database collection status is visible in the AH tab")
AuctionHouseFrame:SetDisplayMode({ "Buy" })
check(not window:IsShown() and builtinContent:IsShown(), "native AH tab hides Profit Master content")
local otherPanel = CreateFrame("Frame", nil, AuctionHouseFrame)
ahLibrary:CreateTab("OtherAddon", otherPanel, "Other addon")
ahLibrary:SetSelected("OtherAddon")
check(otherPanel:IsShown() and not window:IsShown(), "another addon tab can be selected")
SlashCmdList.PROFITMASTER()
check(window:IsShown() and not otherPanel:IsShown(), "slash command selects the AH tab through the shared library")
click(findButton("Scan Auction House"))
check(scans == 1 and #bids == 0, "scan reuses Auctionator and cannot purchase")
check(subscribed.progress, "subscribed to Auctionator's real scan-progress event")
check(window.progress.value == 0 and window.progress.text.text:find("waiting for server", 1, true), "scan gives immediate waiting feedback")
check(window.scan.text == "Scanning..." and not window.scan.enabled, "scan button shows active state and prevents duplicate scans")
listener:ReceiveEvent("progress", 0.1)
check(window.progress.value == 0.1, "server-wait progress reflects Auctionator")
local valueUpdates = window.progress.valueUpdates
listener:ReceiveEvent("progress", 0.1)
check(window.progress.valueUpdates == valueUpdates, "unchanged progress does not rewrite bar value")
listener:ReceiveEvent("progress", 0.5)
check(window.progress.value == 0.5 and window.progress.text.text:find("50%", 1, true), "progress reports actual percentage")
listener:ReceiveEvent("progress", 0.4)
check(window.progress.value == 0.5, "upstream stage regression does not move bar backwards")
listener:ReceiveEvent("progress", 1)
check(window.progress.value == 0.99 and window.progress.text.text:find("finishing scan", 1, true), "upstream 100% is not presented as completed before results arrive")
listener:ReceiveEvent("progress", "SECRET")
check(window.progress.value == 0.99, "unavailable progress is ignored")
local function scanned(id, link, quantity, cost)
    return { itemLink = link, replicateInfo = { [3] = quantity, [10] = cost, [17] = id } }
end
check(not addon.ReplicateDeal(scanned(1, "item:1", 20, 1960)),
    "replicate minimum applies per item even if total stack profit exceeds three copper")
local unitEstimate = addon.ReplicateDeal(scanned(1, "item:1", 20, 1940))
check(unitEstimate.profit == 3 and unitEstimate.quantity == 1 and unitEstimate.available == 20,
    "replicate estimates keep availability separate from an eligible per-item profit")
local data = { scanned(1, "item:1", 20, 1500), scanned(1, "item:1", 1, 50),
    scanned(2, "item:2", 2, 390), scanned(3, "item:3", 1, 1) }
listener:ReceiveEvent("complete", data)
check(window.progress.value == 1 and window.progress.text.text:find("Scan complete", 1, true), "bar completes only when deals are ready")
check(window.scan.enabled and window.scan.text == "Scan Auction House", "completion restores scan control")
check(window.rows[1].deal.profit == 50 and window.rows[2].deal.profit == 5,
    "scan aggregates each item and sorts by normalized per-item profit")
check(window.rows[2].quantity.text == 2 and window.rows[2].vendor.text == "200",
    "replicate availability populates without multiplying the per-item vendor column")
check(not window.rows[3].deal, "duplicate candidates and unsellable items excluded")
local function listing(id, link, quantity, cost)
    return { auctionID = id, itemLink = link, quantity = quantity, buyoutAmount = cost,
        containsOwnerItem = false, containsAccountItem = false }
end
local own = listing(90, "item:1", 1, 1); own.containsOwnerItem = true
local account = listing(91, "item:1", 1, 1); account.containsAccountItem = true
check(not addon.LiveDeal(own) and not addon.LiveDeal(account), "own and account auctions excluded")
local function prepare(id)
    cancelPopup()
    results = { listing(id or 42, "item:1", 20, 75), own, account,
        listing(43, "item:1:variant", 1, 70), listing(44, "item:1", 1, nil) }
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
    -- These existing failure/stock checks explicitly request a single copy.
    if popup.shown then popup:GetEditBox():SetText("1") end
end
local firstCandidate, secondCandidate = window.rows[1].deal, window.rows[2].deal
local function restoreCandidates()
    listener:ReceiveEvent("complete", data)
    firstCandidate, secondCandidate = window.rows[1].deal, window.rows[2].deal
end
check(not findButton("Check"), "candidate rows have Buy without a separate Check step")
prepare()
check(queries == 1 and #bids == 0, "Buy fetches a live quote without an asynchronous purchase")
check(popup.shown and popup.data.auctionID == 42 and popup.data.cost == 75 and popup.data.quantity == 1
    and popup.data.vendor == 100 and popup.data.profit == 25,
    "Buy opens one exact-price auction confirmation without multiplying grouped availability")
check(popup.text:find("Auction ID: 42", 1, true) and popup.text:find("x1", 1, true),
    "confirmation identifies one auction and one item")
check(window.rows[1].deal == firstCandidate and window.rows[2].deal == secondCandidate,
    "query and confirmation preserve the whole original result list")
results[1].buyoutAmount = 80
confirmPopup()
check(#bids == 0 and window.rows[1].deal == secondCandidate, "price change removes the stale offer and advances the next row")
restoreCandidates()
prepare()
results[1].quantity = 0
confirmPopup()
check(#bids == 0, "exhausted search results reject old purchase")
restoreCandidates()
prepare()
results[1].itemLink = "item:1:variant"
confirmPopup()
check(#bids == 0, "variant change rejects purchase")
restoreCandidates()
prepare()
money = 10
confirmPopup()
check(#bids == 0, "insufficient funds cannot submit a purchase")
money = 100000
prepare()
throttle = false
check(popup:GetButton1().enabled and #bids == 0,
    "search throttling leaves a verified purchase enabled without buying automatically")
cancelPopup()
throttle = true
prepare()
results = {}
confirmPopup()
check(#bids == 0, "disappeared listing cannot be purchased")
restoreCandidates()
prepare()
confirmPopup()
check(#bids == 1 and bids[1][1] == 42 and bids[1][2] == 75, "one click submits one auction's exact-price buyout")
check(not findButton("Buy"), "pending purchase prevents double-click purchases")
check(window.rows[1]:IsShown() and window.rows[2]:IsShown(), "pending purchase does not clear or hide results")
ahLibrary:SetSelected("OtherAddon")
SlashCmdList.PROFITMASTER()
check(not findButton("Buy"), "switching tabs cannot clear pending purchase lock")
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 999)
check(not findButton("Buy"), "unrelated purchase event cannot clear lock")
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 42)
check(not window.rows[1].action.enabled and window.rows[2].action.enabled and window.rows[1].deal == firstCandidate,
    "matching completion waits only on the purchased row and keeps other rows usable")
local refreshesBefore = refreshes
runImmediate()
check(refreshes == refreshesBefore + 1 and refreshedKey.itemID == 1, "successful buy refreshes only the selected item")
results = { listing(42, "item:1", 20, 75), listing(45, "item:1", 19, 75) }
event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
check(findButton("Buy") and window.rows[1].deal == firstCandidate and window.rows[1].quantity.text == 19,
    "same-price stock keeps the item and updates quantity while excluding the purchased auction")
check(window.rows[1].cost.text == "75" and window.rows[1].vendor.text == "100" and #bids == 1 and not popup.shown,
    "recheck updates unit prices without opening or submitting another purchase")
prepare(42)
check(not popup.shown and #bids == 1, "confirmed auction is excluded when a stale result cache still contains it")
restoreCandidates()
prepare(52)
confirmPopup()
drain()
check(#bids == 2 and findButton("Buy") and window.rows[1].deal == secondCandidate and not window.rows[2].deal,
    "unconfirmed purchase removes only the attempted item and never retries")
check(window.status.text:find("mail/gold", 1, true), "uncertain purchase outcome is reported")
check(window.progress.text.text:find("1 candidates remain", 1, true), "failed-buy removal updates the displayed candidate count")
event("AUCTION_HOUSE_SHOW_ERROR", 1)
check(window.rows[1].deal == secondCandidate, "late failure cannot remove another item")
restoreCandidates()
check(window.rows[1].deal.itemID == 1, "a new scan can rediscover an item removed after a failed buy")
prepare(62)
event("UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR)
check(popup.shown and window.rows[1].deal == firstCandidate, "internal errors without a submitted buy cannot erase a candidate")
event("AUCTION_HOUSE_SHOW_ERROR", 1)
check(not popup.shown and window.rows[1].deal == firstCandidate and findButton("Buy"), "AH error cancels quote without clearing results")
prepare(72)
cancelPopup()
check(window.rows[1].deal == firstCandidate and #bids == 2, "canceling confirmation keeps results and sends no purchase")
results = { listing(74, "item:1", 139, 150), listing(75, "item:1", 1, 50) }
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
check(popup.shown and popup.data.auctionID == 75 and popup.data.quantity == 1 and popup.data.profit == 50,
    "auction-by-auction comparison ignores a large losing group and selects the actual profitable listing")
cancelPopup()
full = false
results = {}
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
click(findButton("More listings"))
check(more == 1, "additional result pages are manually requested")
event("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
full = true
for _, blocked in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "AUCTION_HOUSE_SHOW_ERROR",
    { "UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR } }) do
    prepare(82)
    blockNext = blocked
    confirmPopup()
    check(#bids == 2 and window.rows[1].deal == secondCandidate and not window.rows[2].deal,
        "rejected or blocked purchase removes only its attempted item")
    check(window.status.text:find("Item removed", 1, true)
        and (type(blocked) == "table" and not findButton("Buy") or type(blocked) == "string" and findButton("Buy")),
        "failed item is removed; ambiguous internal errors retain the pending purchase lock")
    if type(blocked) == "string" and blocked ~= "AUCTION_HOUSE_SHOW_ERROR" then
        check(window.status.text:find("C_AuctionHouse.PlaceBid()", 1, true), "blocked function is reported without suppressing the native error")
    end
    local attempts = bidAttempts
    drain()
    check(bidAttempts == attempts, "blocked purchase never retries automatically")
    check(not eventFrame.events.UI_ERROR_MESSAGE, "purchase failure stops listening to general UI errors")
    restoreCandidates()
end
prepare(83)
throwNext = true
local accepted, interrupted = pcall(confirmPopup)
hardwareClick = false -- the test harness models the end of the user's click
check(not accepted and tostring(interrupted):find("simulated purchase handler interruption", 1, true),
    "purchase handler errors are not suppressed or retried")
drain()
check(findButton("Buy") and window.rows[1].deal == secondCandidate and not window.rows[2].deal and not popup.shown,
    "pre-armed timeout removes the attempted item after an interrupted purchase call")
restoreCandidates()
prepare(84)
local oldQuote, oldDialog = popup.data, popup.which
cancelPopup()
local attemptsBeforeStale = bidAttempts
hardwareClick = true
StaticPopupDialogs[oldDialog].OnAccept({}, oldQuote)
hardwareClick = false
check(bidAttempts == attemptsBeforeStale, "stale or canceled confirmation cannot submit a purchase")
click(findButton("Buy"))
drain()
check(window.rows[1].deal == firstCandidate and findButton("Buy"), "verification timeout also keeps results")
event("AUCTION_HOUSE_CLOSED")
check(window.shown == false and #bids == 2, "closing AH stops work and hides window")
drain()
event("AUCTION_HOUSE_SHOW")
SlashCmdList.PROFITMASTER()
check(not window.rows[1].deal, "reopening requires fresh candidates after close released temporary listings")
restoreCandidates()
commodity = true
local queryCount = exactQueries
click(findButton("Buy"))
check(exactQueries == queryCount + 1 and not popup.shown, "commodity candidates start their live commodity search")
drain()
commodity = false
-- A large snapshot is processed in bounded batches and finishes while minimized.
local large = {}
for i = 1, 1250 do large[i] = scanned(1, "item:1", 20, 1500) end
local beforeLookups = itemLookups
listener:ReceiveEvent("complete", large)
check(window.rows[1].deal and window.rows[1].deal.profit == 25 and window.rows[1].action.enabled,
    "first valuation batch publishes buyable candidates before later batches complete")
check(window.progress.value == 0.8 and window.progress.text.text:find("1000 / 1250", 1, true), "vendor-price stage reports exact processed count")
check(not window.scan.enabled, "scan stays disabled until vendor checking completes")
window:Hide()
drain()
SlashCmdList.PROFITMASTER()
check(window.rows[1].deal.profit == 25 and window.rows[1].quantity.text == 20 and not window.rows[2].deal,
    "large scan batches normalize prices, populate availability and deduplicate")
check(window.progress.value == 1 and window.scan.enabled, "tab switching preserves completion feedback")
check(itemLookups - beforeLookups == 1, "1250 duplicate listings use one exact-link vendor lookup")
listener:ReceiveEvent("start")
listener:ReceiveEvent("progress", 0.5)
listener:ReceiveEvent("failed")
check(window.progress.value == 0 and window.progress.text.text:find("failed", 1, true) and window.scan.enabled,
    "scan failure clears success state and restores controls")
listener:ReceiveEvent("complete", large)
event("AUCTION_HOUSE_CLOSED")
check(window.progress.value == 0 and window.progress.text.text:find("stopped", 1, true), "closing AH marks in-progress work as stopped")
listener:ReceiveEvent("progress", 1)
check(window.progress.value == 0, "late progress after AH close cannot show completion")
drain()
check(#timers == 0, "closing AH cancels bounded processing")

event("AUCTION_HOUSE_SHOW")
SlashCmdList.PROFITMASTER()
canFullScan = false
local scansBefore, bidsBefore = scans, #bids
click(findButton("Scan Auction House"))
check(browseScans == 1 and scans == scansBefore, "replicate cooldown falls back to Auctionator browse scan")
check(subscribed.browse_start and subscribed.browse_progress and subscribed.browse_complete and subscribed.browse_failed,
    "both Auctionator scan modes supply progress and results")
local exactKey = { itemID = 1, itemLevel = 20, itemSuffix = 7, battlePetSpeciesID = 0 }
local browseData = {
    { itemKey = exactKey, appearanceLink = "item:1:variant", totalQuantity = 200, minPrice = 50 },
    { itemKey = C_AuctionHouse.MakeItemKey(2), totalQuantity = 10, minPrice = 195 },
    { itemKey = C_AuctionHouse.MakeItemKey(3), appearanceLink = "item:3", totalQuantity = 10, minPrice = 1 },
}
listener:ReceiveEvent("browse_progress", 0.5)
check(window.progress.value == 0.5 and window.progress.text.text:find("browse scan", 1, true), "browse progress uses the correct scan label")
listener:ReceiveEvent("browse_complete", browseData)
check(window.rows[1].deal.profit == 50 and window.rows[1].quantity.text == 200,
    "browse availability populates while prices remain per item")
check(window.headers[3].text == "Buyout / item" and window.headers[5].text == "Profit / item", "browse candidate prices are explicitly per item")
check(window.rows[1].deal.itemKey == exactKey and window.rows[2].deal.itemID == 2, "browse candidates retain variant keys and cached ID fallback")
check(#bids == bidsBefore, "neither scan mode can submit a purchase")
local exactBefore = exactQueries
click(findButton("Buy"))
check(exactQueries == exactBefore + 1 and queriedKey == exactKey, "browse candidate requests its exact variant, not every variant")
results = { listing(142, "item:1:variant", 20, 55) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(1))
check(not (popup and popup.shown), "another variant's result cannot create a purchase quote")
event("ITEM_SEARCH_RESULTS_UPDATED", exactKey)
check(popup.data.cost == 55 and popup.data.vendor == 60 and popup.data.quantity == 1
    and window.headers[3].text == "Buyout / item", "confirmation shows one auction's price and vendor value while source estimates stay unchanged")
values["item:1:variant"] = 40
confirmPopup()
check(#bids == bidsBefore and findButton("Buy"), "cached scan values never override a fresh vendor check on Buy")
values["item:1:variant"] = 60
listener:ReceiveEvent("browse_complete", browseData)
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", exactKey)
popup:GetEditBox():SetText("1")
for i = 1, 100 do table.insert(results, 1, listing(1000 + i, "item:1", 1, 99)) end
local beforeBuyLookups = itemLookups
confirmPopup()
check(#bids == bidsBefore + 1 and itemLookups == beforeBuyLookups + 1,
    "purchase revalidates only the chosen auction, not every preceding auction")
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 142)
runImmediate()
check(refreshedKey == exactKey, "post-purchase refresh preserves the exact browse variant key")
results = { listing(143, "item:1:variant", 20, 55) }
event("ITEM_SEARCH_RESULTS_UPDATED", exactKey)
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", exactKey)
completeNext = true
popup:GetEditBox():SetText("1")
confirmPopup()
check(#bids == bidsBefore + 2 and not window.rows[1].action.enabled and window.rows[2].action.enabled and window.rows[1].deal.itemKey == exactKey,
    "synchronous completion starts a stock recheck instead of reinstating the purchase lock")
check(window.status.text:find("Purchase confirmed", 1, true) and not popup.shown,
    "synchronous completion keeps its confirmed status after the click returns")
runImmediate()
event("ITEM_SEARCH_RESULTS_UPDATED", exactKey)
check(window.rows[1].deal.itemID == 2 and not window.rows[2].deal and findButton("Buy"),
    "only the exhausted item's row is removed after its purchased auction disappears")
preferFull, canFullScan = false, true
click(findButton("Scan Auction House"))
check(browseScans == 1 and scans == scansBefore + 1,
    "Profit Master prefers a complete history snapshot without changing Auctionator's browse preference")
listener:ReceiveEvent("failed")
canFullScan = false
click(findButton("Scan Auction House"))
check(browseScans == 2 and scans == scansBefore + 1, "full-scan cooldown retains fast browse fallback")
listener:ReceiveEvent("browse_failed")
check(window.scan.enabled and window.progress.text.text:find("failed", 1, true), "browse failure clears busy state")
-- A scan started directly in Auctionator supplies results without another request.
listener:ReceiveEvent("browse_start")
listener:ReceiveEvent("browse_complete", browseData)
check(browseScans == 2 and window.rows[1].deal.profit == 50, "Auctionator-initiated browse results are reused without another scan")
Auctionator.State.IncrementalScanFrameRef.doingFullScan = true
local beforeBusyScan = scans
window.scan.scripts.OnClick(window.scan)
check(scans == beforeBusyScan and browseScans == 2, "doingFullScan state prevents competing scans")
Auctionator.State.IncrementalScanFrameRef.doingFullScan = false
local browseController = Auctionator.State.IncrementalScanFrameRef
Auctionator.State.IncrementalScanFrameRef = nil
preferFull, canFullScan, now = true, false, now + 45
click(findButton("Scan Auction House"))
check(window.status.text:find("45s old", 1, true) and window.rows[1].deal.profit == 50,
    "cooldown with no browse controller reuses previous candidates with explicit age")
Auctionator.State.IncrementalScanFrameRef = browseController
local itemCache = {}
beforeLookups = itemLookups
for i = 1, 1000 do addon.Deal("item:999", 1, 1, itemCache) end
check(itemLookups == beforeLookups + 1, "uncached duplicates are skipped without repeating expensive lookups")

-- Missing AH metadata must not hide a cached vendor value.
keyInfoAvailable = false
local metadataCandidate = addon.BrowseDeal({ itemKey = C_AuctionHouse.MakeItemKey(1), totalQuantity = 1, minPrice = 50 }, {})
check(metadataCandidate and metadataCandidate.profit == 50, "optional key metadata does not block vendor evaluation")
local appearanceCandidate = addon.BrowseDeal({ itemKey = C_AuctionHouse.MakeItemKey(1), totalQuantity = 1,
    minPrice = 50, appearanceLink = "|Htransmogappearance:123|hAppearance|h" }, {})
check(appearanceCandidate and appearanceCandidate.link == "item:1", "non-item appearance link falls back to a real cached item link")
local normalGetItemInfo = C_Item.GetItemInfo
local numericLookups, displayLookups = 0, 0
C_Item.GetItemInfo = function(reference)
    if reference == 70001 then
        numericLookups = numericLookups + 1
        return "Numeric vendor", "item:70001:display", 1, 1, 1, "", "", 20, "", 1, 100
    elseif reference == 70002 then
        return "Vendor without link", nil, 1, 1, 1, "", "", 20, "", 1, 80
    elseif reference == "item:70001:display" then
        displayLookups = displayLookups + 1
        return nil
    end
    return normalGetItemInfo(reference)
end
local numericCandidate = addon.BrowseDeal({ itemKey = C_AuctionHouse.MakeItemKey(70001), totalQuantity = 1, minPrice = 50 }, {})
check(numericCandidate and numericCandidate.profit == 50 and numericLookups == 1 and displayLookups == 0,
    "valid numeric-ID vendor price is used without a second failing display-link lookup")
local noLinkCandidate = addon.BrowseDeal({ itemKey = C_AuctionHouse.MakeItemKey(70002), totalQuantity = 1, minPrice = 50 }, {})
check(noLinkCandidate and noLinkCandidate.profit == 30 and noLinkCandidate.display == "Vendor without link",
    "missing display link does not hide a valid vendor price or item name")
check(ProfitMasterDB.items[70001].vendorLink == "item:70001" and ProfitMasterDB.items[70002].vendorPrice == 80,
    "numeric vendor observations retain their base-item provenance")
local exactUnavailable, exactMissing = addon.Deal("item:70001:display", 1, 50)
check(not exactUnavailable and exactMissing, "live exact-link valuation cannot borrow a base-ID estimate")
C_Item.GetItemInfo = normalGetItemInfo

-- Reproduce the live symptom: native record succeeds before vendor metadata is ready.
local delayedPrice
C_Item.GetItemInfo = function(reference)
    if reference == 70003 then
        return "Delayed vendor", nil, 1, 1, 1, "", "", 20, "", 1, delayedPrice
    end
    return normalGetItemInfo(reference)
end
itemRequests = {}
local delayedRow = { { itemKey = C_AuctionHouse.MakeItemKey(70003), totalQuantity = 1, minPrice = 50 } }
listener:ReceiveEvent("browse_complete", delayedRow)
check(#itemRequests == 1 and eventFrame.events.GET_ITEM_INFO_RECEIVED, "loader listens for full item-info readiness")
event("ITEM_DATA_LOAD_RESULT", 70003, true)
runImmediate()
check(not window.scan.enabled and window.progress.text.text:find("Loading item data", 1, true),
    "successful basic record event cannot finish a vendor load with no readable price")
event("GET_ITEM_INFO_RECEIVED", 999998, true)
check(not window.scan.enabled, "unrelated metadata event cannot finish the pending vendor load")
delayedPrice = 100
event("GET_ITEM_INFO_RECEIVED", 70003, true)
runImmediate()
check(window.scan.enabled and window.rows[1].deal.profit == 50 and window.status.text:find("unavailable 0", 1, true),
    "full metadata event releases the slot and retries the row using its now-readable price")
check(window.status.text:find("Item records: 1 OK; vendor data: 1 ready", 1, true),
    "report separates basic-record success from usable vendor-data success")
check(not eventFrame.events.GET_ITEM_INFO_RECEIVED and not eventFrame.events.ITEM_DATA_LOAD_RESULT,
    "both data listeners stop after completion")
local sampleAfterRetry = ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)].records["browse:70003:0:0:0"]
check(sampleAfterRetry.samples == 1, "waiting for the second metadata phase does not duplicate auction history")
C_Item.GetItemInfo = normalGetItemInfo
local coldData = {}
local coldCount = 12948
for i = 1, coldCount do
    coldData[i] = { itemKey = C_AuctionHouse.MakeItemKey(20000 + i), totalQuantity = 1, minPrice = 50 }
end
itemRequests = {}
listener:ReceiveEvent("browse_start")
listener:ReceiveEvent("browse_complete", coldData)
runImmediate()
check(#itemRequests == 32 and window.progress.text.text:find("Loading item data", 1, true),
    "12948 cold rows start a bounded 32-item loading queue, not a false completed zero")
check(not window.scan.enabled and eventFrame.events.ITEM_DATA_LOAD_RESULT, "item-loading phase stays active and subscribes only while needed")
local delivered, maxInFlight, seen = 0, 0, {}
while delivered < coldCount do
    local inFlight = #itemRequests - delivered
    maxInFlight = math.max(maxInFlight, inFlight)
    local id = itemRequests[delivered + 1]
    assert(id and not seen[id], "missing or duplicate item request")
    seen[id] = true
    values["item:" .. id] = 100
    delivered = delivered + 1
    event("ITEM_DATA_LOAD_RESULT", id)
    -- The engine may evict this data while thousands of later IDs are loaded.
    -- The successful callback must have retained the real name/price already.
    values["item:" .. id] = nil
end
runImmediate()
check(maxInFlight <= 32 and #itemRequests == coldCount, "queue loads each unique ID once with at most 32 pending")
check(window.rows[1].deal and window.progress.text.text:find("12948 candidates", 1, true),
    "all 12948 loaded prices remain usable after simulated native-cache eviction")
check(window.status.text:find("priced 12948", 1, true) and window.status.text:find("unavailable 0", 1, true), "coverage reports successful valuation rather than skipped rows")
check(ProfitMasterDB.items[20001].vendorPrice == 100, "fresh loaded vendor values are persisted")
local firstHistory = ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)].records["browse:20001:0:0:0"]
check(firstHistory.samples == 1 and firstHistory.last == 50, "vendor retry never duplicates a market-price observation")
check(window.scan.enabled and not eventFrame.events.ITEM_DATA_LOAD_RESULT, "loading callback and deadline stop when work finishes")

-- Exact links for replicate rows must be captured separately from base-ID data.
local normalForVariants = C_Item.GetItemInfo
local variantA, variantB
C_Item.GetItemInfo = function(reference)
    if reference == "item:71000:variantA" then
        if variantA then return "Variant A", reference, 1, 1, 1, "", "", 20, "", 1, variantA end
        return nil
    elseif reference == "item:71000:variantB" then
        if variantB then return "Variant B", reference, 1, 1, 1, "", "", 20, "", 1, variantB end
        return nil
    end
    return normalForVariants(reference)
end
itemRequests = {}
local exactRows = { scanned(71000, "item:71000:variantA", 1, 50), scanned(71000, "item:71000:variantB", 1, 50) }
listener:ReceiveEvent("complete", exactRows)
check(#itemRequests == 1, "variants share a single ID request while keeping separate price references")
variantA = 100
event("ITEM_DATA_LOAD_RESULT", 71000, true)
check(not window.scan.enabled, "one ready variant cannot stand in for a second variant's vendor data")
variantB = 40
event("GET_ITEM_INFO_RECEIVED", 71000, true)
variantA, variantB = nil, nil
runImmediate()
check(window.rows[1].deal and window.rows[1].deal.link == "item:71000:variantA"
    and not window.rows[2].deal and window.status.text:find("priced 2", 1, true),
    "captured exact variants survive eviction without borrowing another variant's price")
C_Item.GetItemInfo = normalForVariants

local syncRows = {}
for i = 1, 100 do syncRows[i] = { itemKey = C_AuctionHouse.MakeItemKey(200000 + i), totalQuantity = 1, minPrice = 50 } end
local requestItemData = C_Item.RequestLoadItemDataByID
C_Item.RequestLoadItemDataByID = function(id)
    requestItemData(id)
    values["item:" .. id] = 100
    event("ITEM_DATA_LOAD_RESULT", id)
end
itemRequests = {}
listener:ReceiveEvent("browse_complete", syncRows)
check(#itemRequests == 32 and not window.scan.enabled, "synchronous cached completions yield after 32 requests instead of recursing through the queue")
runImmediate()
check(#itemRequests == 100 and window.status.text:find("priced 100;", 1, true) and window.scan.enabled,
    "synchronous completion queue terminates with full coverage")
C_Item.RequestLoadItemDataByID = requestItemData

-- Duplicate rows share one native load request.
local duplicateCold = {}
for i = 1, 500 do
    duplicateCold[i] = { itemKey = C_AuctionHouse.MakeItemKey(80000), totalQuantity = 1, minPrice = 50 }
end
itemRequests = {}
listener:ReceiveEvent("browse_complete", duplicateCold)
check(#itemRequests == 1, "duplicate cold rows share one item-ID request")
values["item:80000"] = 100
event("ITEM_DATA_LOAD_RESULT", 80000)
runImmediate()
check(window.status.text:find("priced 500", 1, true) and not window.rows[2].deal, "loaded duplicate rows are valued and deduplicated")

local missingRow = { { itemKey = C_AuctionHouse.MakeItemKey(999999), totalQuantity = 1, minPrice = 1 } }
itemRequests = {}
listener:ReceiveEvent("browse_complete", missingRow)
check(#itemRequests == 1 and not window.scan.enabled, "missing item waits for native data before judging profit")
drain()
check(window.progress.text.text:find("Incomplete data", 1, true) and window.status.text:find("unavailable 1", 1, true),
    "item-load timeout reports incomplete coverage, not proof that no bargains exist")
check(window.scan.enabled and not eventFrame.events.ITEM_DATA_LOAD_RESULT, "timeout releases the load listener and scan lock")
local requestCount = #itemRequests
event("ITEM_DATA_LOAD_RESULT", 999999)
check(#itemRequests == requestCount, "late data does not restart a timed-out scan")
listener:ReceiveEvent("browse_complete", missingRow)
event("ITEM_DATA_LOAD_RESULT", 999999, false)
runImmediate()
check(window.progress.text.text:find("Incomplete data", 1, true), "failed native load remains explicitly unavailable")
check(window.status.text:find("1 failed", 1, true), "native load failure is reported separately from missing vendor data")
check(ProfitMasterDB.items[999999].vendorPrice == nil, "missing vendor data is never persisted as a fabricated zero")
check(ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)].records["browse:999999:0:0:0"].last == 1,
    "valid auction observations persist even while vendor data is unavailable")

keyInfoAvailable = true
commodity = true
listener:ReceiveEvent("browse_complete", browseData)
check(window.status.text:find("unsupported 0", 1, true) and window.status.text:find("unavailable 0", 1, true)
    and window.rows[1].deal.isCommodity and window.rows[2].deal.isCommodity,
    "commodity browse candidates are valued and labeled separately from individual auctions")
commodity = false
local pricedData = {
    { itemKey = C_AuctionHouse.MakeItemKey(3), totalQuantity = 1, minPrice = 1 },
    { itemKey = C_AuctionHouse.MakeItemKey(1), totalQuantity = 1, minPrice = 100 },
}
listener:ReceiveEvent("browse_complete", pricedData)
check(window.status.text:find("priced 2", 1, true) and window.status.text:find("no vendor 1", 1, true)
    and window.status.text:find("not below vendor 1", 1, true), "genuine non-deals report vendor coverage and exclusion reasons")
local minimumData = {
    { itemKey = C_AuctionHouse.MakeItemKey(1), totalQuantity = 100, minPrice = 99 },
    { itemKey = C_AuctionHouse.MakeItemKey(2), totalQuantity = 100, minPrice = 198 },
    { itemKey = C_AuctionHouse.MakeItemKey(1), totalQuantity = 1, minPrice = 97 },
}
listener:ReceiveEvent("browse_complete", minimumData)
check(window.rows[1].deal.profit == 3 and not window.rows[2].deal,
    "browse list hides one- and two-copper results while keeping exactly three")
check(window.status.text:find("priced 3", 1, true) and window.status.text:find("below profit minimum when checked 2", 1, true)
    and window.status.text:find("unavailable 0", 1, true), "minimum-profit exclusions retain accurate vendor coverage")
listener:ReceiveEvent("complete", { scanned(1, "item:1", 1, 99), scanned(2, "item:2", 1, 197) })
check(window.rows[1].deal.profit == 3 and not window.rows[2].deal,
    "replicate list uses the same three-copper minimum")

listener:ReceiveEvent("browse_complete", missingRow)
event("AUCTION_HOUSE_CLOSED")
check(not eventFrame.events.ITEM_DATA_LOAD_RESULT, "closing AH unsubscribes item loading")
check(not eventFrame.events.GET_ITEM_INFO_RECEIVED, "closing AH also unsubscribes vendor metadata")
local requestsAtClose = #itemRequests
event("ITEM_DATA_LOAD_RESULT", 999999)
drain()
check(#itemRequests == requestsAtClose, "closing AH stops queued native load requests and timer work")

-- Remove the sole item on the last page without affecting the other eight.
event("AUCTION_HOUSE_SHOW")
SlashCmdList.PROFITMASTER()
local pagedData = {}
for id = 8001, 8009 do
    values["item:" .. id] = 100
    pagedData[#pagedData + 1] = scanned(id, "item:" .. id, 1, 50)
end
listener:ReceiveEvent("complete", pagedData)
click(findButton("Next"))
local lastCandidate = window.rows[1].deal
check(window.page.text == "2 / 2" and not window.rows[2].deal, "last page starts with one item")
results = { listing(9001, lastCandidate.link, 1, 50) }
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(lastCandidate.itemID))
blockNext = "AUCTION_HOUSE_SHOW_ERROR"
confirmPopup()
check(window.page.text == "1 / 1" and window.rows[8].deal and not window.next.enabled,
    "failure on the last page clamps pagination and preserves the other eight items")
for _, row in ipairs(window.rows) do
    check(row.deal ~= lastCandidate, "only the selected failed item is removed from the scan")
end

listener:ReceiveEvent("complete", { pagedData[1] })
results = { listing(9002, "item:8001", 1, 50) }
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
blockNext = "AUCTION_HOUSE_SHOW_ERROR"
confirmPopup()
check(not window.rows[1].deal and not window.rows[1]:IsShown() and window.page.text == "1 / 1" and window.scan.enabled,
    "failure on the final item leaves an empty usable list")

local function beginRecheck(id, cost)
    full, throttle, values["item:8001"] = true, true, 100
    listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
    results = { listing(id, "item:8001", 1, cost or 50) }
    local target = window.rows[1].deal
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", id)
    return target
end
local checkedItem = beginRecheck(9101)
event("UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR)
check(window.rows[1].deal == checkedItem and not eventFrame.events.UI_ERROR_MESSAGE,
    "an internal error after purchase success cannot remove an item during the stock recheck")
local beforeRefresh, afterBuy = refreshes, #bids
throttle = false
runImmediate()
check(refreshes == beforeRefresh and eventFrame.events.AUCTION_HOUSE_THROTTLED_SYSTEM_READY,
    "successful purchase waits for throttle readiness without polling")
results = { listing(9102, "item:8001", 7, 50) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(not window.rows[1].action.enabled and window.rows[2].action.enabled and window.rows[1].deal == checkedItem,
    "cached item events before the refresh is sent cannot finish the stock check")
throttle = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(refreshes == beforeRefresh + 1, "repeated readiness events send only one refresh")
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8002))
check(not window.rows[1].action.enabled, "unrelated item updates cannot finish a stock check")
ahLibrary:SetSelected("OtherAddon")
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
SlashCmdList.PROFITMASTER()
check(window.rows[1].deal == checkedItem and window.rows[1].quantity.text == 7 and findButton("Buy"),
    "same-price check completes across tab switches and populates availability")
check(#bids == afterBuy and not popup.shown and not eventFrame.events.AUCTION_HOUSE_THROTTLED_SYSTEM_READY,
    "stock checking never opens a purchase confirmation or buys, and releases its listener")

checkedItem = beginRecheck(9111)
runImmediate()
results = { listing(9112, "item:8001", 10, 51) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal.itemID == 8002 and not window.rows[2].deal,
    "a different price removes only the purchased item's old listing even if still profitable")

checkedItem = beginRecheck(9121)
runImmediate()
full = false
results = { listing(9122, "item:8001", 1, 51) }
local beforeMore = more
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal == checkedItem and not window.rows[1].action.enabled, "partial results cannot establish that a price is gone")
now = now + 5
runImmediate()
check(more == beforeMore + 1, "stock recheck requests the next page for this item")
results = { listing(9123, "item:8001", 2, 50), listing(9123, "item:8001", 2, 50), listing(9124, "item:8001", 3, 50) }
full = true
event("ITEM_SEARCH_RESULTS_ADDED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal == checkedItem and window.rows[1].quantity.text == 5,
    "later same-price results keep the item and count availability without duplicate auction IDs")

checkedItem = beginRecheck(9131)
runImmediate()
values["item:8001:variant"] = 100
results = { listing(9132, "item:8001:variant", 100, 50) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal.itemID == 8002, "another variant at the same price cannot keep the purchased variant listed")

checkedItem = beginRecheck(9141)
runImmediate()
results = { listing(9142, "item:8001", 100, 50) }
values["item:8001"] = 52
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal.itemID == 8002, "rechecked stock below the three-copper minimum cannot keep a listing")

checkedItem = beginRecheck(9145, 75)
runImmediate()
results = { listing(9146, "item:8001", 2, 75) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal.itemID == 8002 and window.rows[2].deal == checkedItem and window.rows[2].quantity.text == 2
    and window.rows[2].cost.text == "75" and window.rows[2].deal.profit == 25,
    "updated same-price availability retains per-item prices and re-sorts changed profits")

checkedItem = beginRecheck(9151)
throttle = false
runImmediate()
afterBuy = #bids
drain()
check(window.rows[1].deal == checkedItem and findButton("Buy") and #bids == afterBuy
    and window.status.text:find("unable to verify", 1, true), "stock-check timeout keeps an unverified item without a second purchase")
check(not eventFrame.events.AUCTION_HOUSE_THROTTLED_SYSTEM_READY, "timed-out stock check stops listening for readiness")

checkedItem = beginRecheck(9161)
runImmediate()
event("AUCTION_HOUSE_SHOW_ERROR", 1)
check(window.rows[1].deal == checkedItem and window.status.text:find("Purchase confirmed", 1, true),
    "stock-refresh error cannot turn a confirmed purchase into a failed buy or erase the item")

checkedItem = beginRecheck(9171)
runImmediate()
values["item:8001"] = nil
results = { listing(9172, "item:8001", 1, 50) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].deal == checkedItem and window.status.text:find("unable to verify", 1, true),
    "missing vendor data is reported as an incomplete stock check rather than no stock")

checkedItem = beginRecheck(9181)
beforeRefresh = refreshes
now = now + 16
runImmediate()
check(refreshes == beforeRefresh and window.rows[1].deal == checkedItem and findButton("Buy"),
    "expired deferred work cannot issue a stock request after its deadline")

checkedItem = beginRecheck(9185)
throttle = false
runImmediate()
beforeRefresh = refreshes
now = now + 16
throttle = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(refreshes == beforeRefresh and window.rows[1].deal == checkedItem,
    "late readiness cannot send an expired stock request")
results = { listing(9186, "item:8001", 1, 50) }
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
drain()
check(popup.shown, "an expired recheck deadline cannot cancel a subsequent purchase confirmation")
cancelPopup()

local function openQuantityQuote(id, available)
    full, throttle, values["item:8001"] = true, true, 100
    listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
    results = { listing(id, "item:8001", available, 50) }
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
end
local function confirmAndRecheck(nextID, available, cost)
    confirmPopup()
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", bids[#bids][1])
    results = { listing(nextID, "item:8001", available, cost or 50) }
    runImmediate()
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
end

-- Vendor goals start at all verified stock affordable at the exact quote price.
for i, example in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 5, 5 }, { 139, 139 } }) do
    openQuantityQuote(9800 + i, example[1])
    check(popup:GetEditBox():GetText() == tostring(example[2]),
        "vendor quantity defaults to all verified same-price stock")
    check(popup:GetButton1().text == (example[2] > 1 and ("Buy 1 of " .. example[2]) or "Buy 1"),
        "individual-auction caption identifies one purchase within the selected goal")
    cancelPopup()
end
money = 120
openQuantityQuote(9811, 139)
check(popup:GetEditBox():GetText() == "2", "maximum-stock default is capped by affordable gold")
check(popup:GetButton1().text == "Buy 1 of 2" and popup.text:find("Total purchase cost: 100", 1, true),
    "affordability cap is reflected in the initial caption and total")
popup:GetEditBox():SetText("3")
check(not popup:GetButton1().enabled, "editing above affordable stock immediately disables the item buy")
cancelPopup()
money = 100000

-- Distinct returned auction IDs can be prepared without another server round trip.
openQuantityQuote(9821, 1)
results = { listing(9821, "item:8001", 1, 50), listing(9822, "item:8001", 1, 50),
    listing(9823, "item:8001", 1, 50), listing(9824, "item:8001", 1, 50),
    listing(9825, "item:8001", 100, 51), listing(9826, "item:8001:variant", 100, 50) }
-- Reopen to include the returned IDs in the initial same-price stock count.
cancelPopup()
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(popup:GetEditBox():GetText() == "4", "other prices and variants cannot inflate the verified-stock goal")
local beforeQuantityEditBids = bidAttempts
popup:GetEditBox():SetText("2") -- Choose a smaller goal before exercising known-ID continuation.
check(popup:GetButton1().text == "Buy 1 of 2" and popup.text:find("Total purchase cost: 100", 1, true)
    and popup.text:find("Total vendor value: 200", 1, true)
    and popup.text:find("Potential total profit: 100", 1, true)
    and popup.text:find("This click buys 1 for 50", 1, true) and bidAttempts == beforeQuantityEditBids,
    "editing an item goal updates totals and the per-click caption immediately without submitting a bid")
local beforeFastBuy, beforeFastRefresh = #bids, refreshes
local firstFastID = popup.data.auctionID
completeNext = true
confirmPopup()
check(not popup.shown, "synchronous completion defers the next quote until the click has returned")
runImmediate()
check(popup.shown and popup.data.auctionID ~= firstFastID and popup.data.cost == 50
    and popup:GetEditBox():GetText() == "1" and refreshes == beforeFastRefresh,
    "remaining goal uses another returned same-price ID without refreshing or resetting to maximum stock")
check(#bids == beforeFastBuy + 1, "preparing the next known ID never submits a bid")
-- Buy-time validation still handles another buyer taking a prepared copy.
for _, info in ipairs(results) do
    if info.auctionID == popup.data.auctionID then info.buyoutAmount = 51 end
end
confirmPopup()
check(#bids == beforeFastBuy + 1 and not popup.shown and findButton("Buy"),
    "a cached next-copy quote cannot submit a bid when its current price changed")

-- A group quantity alone never supplies a second auction ID or proves exhaustion.
openQuantityQuote(9831, 10)
local beforeGroupRefresh = refreshes
confirmPopup()
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9831)
timeout() -- One deferred pass must also send the fallback, without another frame.
check(not popup.shown and refreshes == beforeGroupRefresh + 1 and window.rows[1].deal.itemID == 8001,
    "a purchased group ID with no other known ID falls back to one refresh without removing or rebuying it")
results = { listing(9832, "item:8001", 8, 50) }
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(popup.shown and popup.data.auctionID == 9832 and popup:GetEditBox():GetText() == "8",
    "server-returned replacement ID continues the remaining goal after a grouped-row refresh")
cancelPopup()

openQuantityQuote(9841, 4)
popup:GetEditBox():SetText("2") -- Explicit smaller goal must stop with other stock still present.
results = { listing(9841, "item:8001", 1, 50), listing(9842, "item:8001", 1, 50),
    listing(9843, "item:8001", 1, 50), listing(9844, "item:8001", 1, 50) }
local beforeFastGoal, beforeFinalRefresh = #bids, refreshes
confirmPopup()
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9841)
runImmediate()
check(popup.shown and refreshes == beforeFinalRefresh and #bids == beforeFastGoal + 1,
    "first half-goal purchase needs no network refresh while another returned ID remains")
local secondFastID = popup.data.auctionID
confirmPopup()
event("AUCTION_HOUSE_PURCHASE_COMPLETED", secondFastID)
runImmediate()
check(not popup.shown and refreshes == beforeFinalRefresh and #bids == beforeFastGoal + 2
    and window.rows[1].quantity.text == 2,
    "a completed smaller goal counts remaining returned IDs locally without another stock request")
local remainingFast = {}
for _, info in ipairs(results) do
    if info.auctionID ~= 9841 and info.auctionID ~= secondFastID then remainingFast[#remainingFast + 1] = info end
end
results = remainingFast
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(not popup.shown and window.rows[1].quantity.text == 2 and findButton("Buy"),
    "later result events preserve observed remaining stock without restarting the completed goal")

openQuantityQuote(9851, 4)
results = { listing(9851, "item:8001", 1, 50), listing(9852, "item:8001", 3, 50) }
confirmPopup()
throttle = false
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9851)
local beforeReadyRefresh, beforeReadyBids = refreshes, #bids
runImmediate()
check(popup.shown and popup:GetButton1().enabled and eventFrame.events.AUCTION_HOUSE_THROTTLED_SYSTEM_READY
    and refreshes == beforeReadyRefresh and #bids == beforeReadyBids,
    "a cached next-copy check prepares an actionable quote immediately while the search system is busy")
throttle = true
event("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(popup.shown and popup:GetButton1().enabled and refreshes == beforeReadyRefresh and #bids == beforeReadyBids,
    "native search readiness preserves the prepared next-copy quote without another request or purchase")
cancelPopup()

openQuantityQuote(9301, 4)
local beforeQuantity = #bids
for _, invalid in ipairs({ "", "0", "-1", "1.5", "5", "abc" }) do
    popup:GetEditBox():SetText(invalid)
    check(not popup:GetButton1().enabled and popup:GetButton1().text == "Buy 1"
        and not popup.text:find("Total purchase cost:", 1, true),
        "invalid item-goal edits immediately clear stale totals and disable the confirmation")
    confirmPopup()
    check(popup.shown and #bids == beforeQuantity, "invalid quantity goal keeps confirmation open without buying")
end
popup:GetEditBox():SetText("3")
check(popup:GetButton1().text == "Buy 1 of 3" and popup:GetButton1().enabled
    and popup.text:find("Total purchase cost: 150", 1, true),
    "a corrected goal immediately restores its caption, total and enabled state")
confirmAndRecheck(9302, 3)
check(#bids == beforeQuantity + 1 and popup.shown and popup.data.auctionID == 9302
    and popup:GetEditBox():GetText() == "2", "one quantity-goal click buys one auction and prepares the next copy")
check(popup:GetButton1().text == "Buy 1 of 2" and popup.text:find("Total purchase cost: 100", 1, true)
    and popup.text:find("Already bought in this goal: 1", 1, true),
    "next individual quote preserves the edited remaining goal instead of resetting to maximum stock")
local afterFirstCopy = #bids
drain()
check(#bids == afterFirstCopy and popup.shown, "waiting at the next confirmation never automatically buys")
confirmAndRecheck(9303, 2)
check(#bids == beforeQuantity + 2 and popup.shown and popup:GetEditBox():GetText() == "1",
    "second manual click advances the remaining quantity goal")
check(popup:GetButton1().text == "Buy 1" and popup.text:find("Total purchase cost: 50", 1, true),
    "the final remaining copy has an accurate one-item caption and total")
confirmAndRecheck(9304, 1)
check(#bids == beforeQuantity + 3 and not popup.shown and window.rows[1].quantity.text == 1,
    "quantity goal stops after exactly the requested number and still rechecks remaining stock")

openQuantityQuote(9311, 2)
popup:GetEditBox():SetText("2")
confirmAndRecheck(9312, 1)
local canceledQuote, canceledDialog = popup.data, popup.which
local afterCanceledGoal = #bids
cancelPopup()
StaticPopupDialogs[canceledDialog].OnAccept({}, canceledQuote)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
drain()
check(#bids == afterCanceledGoal and not popup.shown and window.rows[1].deal.itemID == 8001,
    "canceling a remaining-copy confirmation ends the goal and stale callbacks cannot buy")

openQuantityQuote(9321, 2)
popup:GetEditBox():SetText("2")
local beforePriceChange = #bids
confirmAndRecheck(9322, 1, 51)
check(#bids == beforePriceChange + 1 and not popup.shown and window.rows[1].deal.itemID == 8002,
    "a quantity goal stops and removes the old offer when its exact price disappears")

openQuantityQuote(9331, 2)
popup:GetEditBox():SetText("2")
confirmAndRecheck(9332, 1)
blockNext = { "UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR }
local beforeGoalError = #bids
confirmPopup()
drain()
check(#bids == beforeGoalError and not popup.shown and window.rows[1].deal.itemID == 8002,
    "an internal auction error on a later copy removes that item and ends the quantity goal")

openQuantityQuote(9341, 2)
popup:GetEditBox():SetText("2")
confirmPopup()
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9341)
results = { listing(9342, "item:8001", 1, 50) }
money = 10
local beforeGoldStop = #bids
runImmediate()
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(not popup.shown and #bids == beforeGoldStop and window.rows[1].deal.itemID == 8001
    and window.status.text:find("not enough gold", 1, true), "insufficient funds stop a quantity goal while retaining remaining stock")
money = 100000

openQuantityQuote(9351, 2)
money = 10
local beforeLateGold = #bids
confirmPopup()
check(not popup.shown and #bids == beforeLateGold and window.status.text:find("Not enough gold", 1, true),
    "money lost before a click cancels the quote without an invalid quantity range or bid")
money = 100000

checkedItem = beginRecheck(9401)
runImmediate()
results = {}
for i = 1, 2000 do results[i] = listing(940000 + i, "item:" .. (95000 + i), 1, 51) end
results[2001] = listing(9402, "item:8001", 6, 50)
local readsBefore, lookupsBefore = resultReads, itemLookups
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(resultReads - readsBefore == 200 and not window.rows[1].action.enabled and window.rows[2].action.enabled,
    "a large stock recheck yields after 200 rows and leaves other Buy buttons usable")
check(itemLookups == lookupsBefore, "unrelated prices/items are not valued during a stock recheck")
runImmediate()
check(window.rows[1].deal == checkedItem and window.rows[1].quantity.text == 6 and itemLookups == lookupsBefore + 1,
    "batched stock checking values only the matching item and completes with its count")

checkedItem = beginRecheck(9441)
runImmediate()
results = {}
for i = 1, 2000 do results[i] = listing(944000 + i, "item:" .. (95000 + i), 1, 51) end
results[2001] = listing(9442, "item:8001", 6, 50)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
results[2001].quantity = 8
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
runImmediate()
check(window.rows[1].deal == checkedItem and window.rows[1].quantity.text == 8,
    "a server update during batched processing is re-read before reporting stock")

checkedItem = beginRecheck(9411)
runImmediate()
full = false
results = { listing(9412, "item:8001", 2, 50) }
local moreBeforeMatch = more
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(window.rows[1].quantity.text == ">=2" and more == moreBeforeMatch and window.rows[1].action.enabled,
    "known same-price stock completes immediately without fetching every page and marks a lower-bound count")
full = true

checkedItem = beginRecheck(9421)
local beforeOtherBuyRefresh = refreshes
results = { listing(9422, "item:8002", 1, 50) }
click(window.rows[2].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
check(not popup.shown, "a canceled background check cannot open a quote for the old item")
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8002))
check(popup.shown and popup.data.auctionID == 9422 and window.rows[1].deal == checkedItem,
    "buying another row can cancel a background recheck while retaining its unverified item")
cancelPopup()
drain()
check(refreshes == beforeOtherBuyRefresh, "canceled background checks cannot issue deferred requests later")

listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
results = { listing(9187, "item:8001", 1, 50) }
local unrelatedCandidate = window.rows[2].deal
click(findButton("Buy"))
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
confirmPopup()
local beforeInternalError = #bids
check(eventFrame.events.UI_ERROR_MESSAGE, "submitted purchase listens for internal auction UI errors")
event("UI_ERROR_MESSAGE", 998, "Inventory is full")
event("UI_ERROR_MESSAGE", 999, "SECRET")
check(not findButton("Buy") and window.rows[2].deal == unrelatedCandidate,
    "unrelated or restricted UI messages cannot abort a pending purchase")
local errorText = ERR_AUCTION_DATABASE_ERROR
ERR_AUCTION_DATABASE_ERROR = "Interner Auktionsfehler."
event("UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR)
check(window.rows[1].deal == unrelatedCandidate and not window.rows[2].deal and not findButton("Buy"),
    "localized asynchronous internal auction error removes only the attempted item")
check(window.status.text:find("outcome uncertain", 1, true) and eventFrame.events.UI_ERROR_MESSAGE,
    "internal error retains confirmation handling until the original purchase deadline")
event("UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR)
drain()
check(window.rows[1].deal == unrelatedCandidate and #bids == beforeInternalError,
    "duplicate internal errors and old timers cannot remove other rows or retry a buy")
ERR_AUCTION_DATABASE_ERROR = errorText

-- Database errors can precede a real confirmation. Never infer success from gold.
do
    listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
    results = { listing(9188, "item:8001", 2, 50) }
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
    popup:GetEditBox():SetText("2")
    confirmPopup()
    local attemptsBeforeError, refreshBeforeError, goldBeforeError = bidAttempts, refreshes, money
    local originalDeadline
    for _, scheduled in ipairs(timers) do
        if not scheduled.cancelled and scheduled.delay == 15 then originalDeadline = scheduled end
    end
    check(originalDeadline, "submitted buy has an original bounded confirmation deadline")
    event("AUCTION_HOUSE_SHOW_ERROR", 10)
    check(not findButton("Buy") and not window.scan.enabled and window.rows[1].deal.itemID == 8002,
        "database error removes its item but blocks another purchase until resolved")
    money = money - 50
    event("PLAYER_MONEY")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 999999)
    event("UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR)
    event("AUCTION_HOUSE_SHOW_ERROR", 10)
    event("AUCTION_HOUSE_SHOW_ERROR", 7)
    check(not originalDeadline.cancelled and not findButton("Buy") and not popup.shown,
        "gold changes, unrelated confirmations and duplicate errors neither confirm nor extend the wait")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9188)
    check(window.status.text:find("confirmed after an internal auction error", 1, true)
        and findButton("Buy") and not eventFrame.events.UI_ERROR_MESSAGE,
        "matching delayed completion resolves the uncertain purchase and releases its lock")
    drain()
    check(bidAttempts == attemptsBeforeError and refreshes == refreshBeforeError and not popup.shown,
        "late success does not refresh the excluded offer, resume its quantity goal or submit another bid")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9188)
    check(window.rows[1].deal.itemID == 8002, "duplicate late confirmation cannot restore the removed item")
    money = goldBeforeError

    listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
    results = { listing(9189, "item:8001", 1, 50) }
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
    blockNext = { "AUCTION_HOUSE_SHOW_ERROR", 10 }
    confirmPopup()
    check(window.status.text:find("outcome uncertain", 1, true) and not findButton("Buy"),
        "a synchronous database error keeps its uncertainty message after PlaceBid returns")
    local attemptsAtTimeout = bidAttempts
    drain()
    check(findButton("Buy") and window.status.text:find("outcome remains uncertain", 1, true)
        and not eventFrame.events.UI_ERROR_MESSAGE and bidAttempts == attemptsAtTimeout,
        "missing confirmation expires without inventing success or retrying")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9189)
    check(window.status.text:find("outcome remains uncertain", 1, true),
        "a completion outside the observation window cannot confirm a different later purchase")

    listener:ReceiveEvent("complete", { pagedData[1], pagedData[2] })
    results = { listing(9190, "item:8001", 1, 50) }
    click(findButton("Buy"))
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
    local placeBid = C_AuctionHouse.PlaceBid
    C_AuctionHouse.PlaceBid = function(id, cost)
        placeBid(id, cost)
        event("AUCTION_HOUSE_SHOW_ERROR", 10)
        event("AUCTION_HOUSE_PURCHASE_COMPLETED", id)
    end
    confirmPopup()
    C_AuctionHouse.PlaceBid = placeBid
    check(window.status.text:find("confirmed after an internal auction error", 1, true)
        and findButton("Buy") and not popup.shown,
        "synchronous error then success resolves once without the returning bid handler overwriting success")
end

-- Candidates are usable before the local valuation pass has finished.
full, throttle = true, true
local streamed = {}
for i = 1, 3000 do
    local id = i <= 1000 and 8001 or i <= 2000 and 8002 or 8003
    values["item:" .. id] = 100
    streamed[i] = scanned(id, "item:" .. id, 1, id == 8002 and 30 or id == 8003 and 40 or 50)
end
local bucket = ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)]
local oldSamples = bucket.records["replicate:8001"].samples
listener:ReceiveEvent("complete", streamed)
check(window.rows[1].deal.itemID == 8001 and window.rows[1].action.enabled and not window.scan.enabled,
    "an early candidate is buyable while later local valuation batches are pending")
results = { listing(9601, "item:8001", 3, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
popup:GetEditBox():SetText("1") -- This regression exercises one purchase interrupting valuation.
confirmPopup()
runImmediate()
check(window.rows[1].deal.itemID == 8001 and not window.rows[2].deal,
    "purchase activity pauses remaining valuation instead of clearing candidates or competing for its timer")
event("AUCTION_HOUSE_PURCHASE_COMPLETED", 9601)
results = { listing(9602, "item:8001", 2, 50) }
runImmediate()
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
runImmediate()
check(window.scan.enabled and window.rows[1].deal.itemID == 8002 and window.rows[3].deal.itemID == 8001
    and window.rows[3].quantity.text == 2, "valuation resumes after a buy and retains the fresher live stock count")
check(bucket.records["replicate:8001"].samples == oldSamples + 1000,
    "pausing and resuming never records processed auction observations twice")

listener:ReceiveEvent("complete", streamed)
results = { listing(9611, "item:8001", 1, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
blockNext = { "UI_ERROR_MESSAGE", 999, ERR_AUCTION_DATABASE_ERROR }
confirmPopup()
drain() -- An ambiguous internal error waits only for the original purchase deadline.
runImmediate()
check(window.scan.enabled and window.rows[1].deal.itemID == 8002 and not window.rows[3].deal,
    "resumed valuation cannot re-add an item removed by a failed early purchase")

local loadingStream = {
    { itemKey = C_AuctionHouse.MakeItemKey(97001), totalQuantity = 1, minPrice = 50 },
    { itemKey = C_AuctionHouse.MakeItemKey(97002), totalQuantity = 1, minPrice = 50 },
}
values["item:97001"], values["item:97002"] = nil, nil
listener:ReceiveEvent("browse_complete", loadingStream)
values["item:97001"] = 100
event("ITEM_DATA_LOAD_RESULT", 97001, true)
check(window.rows[1].deal.itemID == 97001 and window.rows[1].action.enabled and not window.scan.enabled,
    "a loaded vendor price publishes its candidate without waiting for other pending items")
results = { listing(97011, "item:97001", 1, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(97001))
confirmPopup()
values["item:97002"] = 200
event("ITEM_DATA_LOAD_RESULT", 97002, true)
values["item:97002"] = nil
check(not window.rows[1].action.enabled and not window.rows[2].deal and eventFrame.events.UI_ERROR_MESSAGE,
    "metadata arriving during a purchase is captured without replacing its deadline or moving its controls")
timeout()
runImmediate()
check(window.scan.enabled and window.rows[1].deal.itemID == 97002 and not window.rows[2].deal
    and window.status.text:find("unavailable 0", 1, true),
    "purchase timeout still removes its item and loading resumes using values captured before eviction")
check(bucket.records["browse:97002:0:0:0"].samples == 1,
    "streaming a vendor-ready candidate does not duplicate its auction-history observation")

local coalesced = {}
for id = 97021, 97023 do
    values["item:" .. id] = nil
    coalesced[#coalesced + 1] = { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 1, minPrice = 50 }
end
listener:ReceiveEvent("browse_complete", coalesced)
values["item:97021"] = 100
event("ITEM_DATA_LOAD_RESULT", 97021, true)
values["item:97022"] = 200
event("ITEM_DATA_LOAD_RESULT", 97022, true)
timeout()
check(window.rows[1].deal.itemID == 97022 and window.rows[2].deal.itemID == 97021 and not window.scan.enabled,
    "a coalesced candidate update renders before an unrelated slow item reaches its loading deadline")
event("ITEM_DATA_LOAD_RESULT", 97023, false)
runImmediate()
check(window.scan.enabled and window.status.text:find("unavailable 1", 1, true),
    "streamed results retain honest incomplete coverage when another item fails to load")

values["item:97001"], values["item:97002"] = nil, nil
listener:ReceiveEvent("browse_complete", loadingStream)
now = now + 40
values["item:97001"] = 100
event("ITEM_DATA_LOAD_RESULT", 97001, true)
results = { listing(97012, "item:97001", 1, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(97001))
now = now + 25
cancelPopup()
runImmediate()
check(not window.scan.enabled and eventFrame.events.ITEM_DATA_LOAD_RESULT,
    "time spent reviewing a purchase does not consume the paused vendor-loading budget")
values["item:97002"] = 200
event("ITEM_DATA_LOAD_RESULT", 97002, true)
runImmediate()
check(window.scan.enabled and window.status.text:find("unavailable 0", 1, true),
    "loading continues with its remaining active-time budget after a long purchase pause")

listener:ReceiveEvent("complete", streamed)
results = { listing(9621, "item:8001", 1, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(8001))
cancelPopup()
event("AUCTION_HOUSE_CLOSED")
drain()
check(not eventFrame.events.ITEM_DATA_LOAD_RESULT and not eventFrame.events.GET_ITEM_INFO_RECEIVED,
    "closing AH cancels valuation that was resumed after an early quote cancellation")
event("AUCTION_HOUSE_SHOW")
SlashCmdList.PROFITMASTER()

local budgetRows, simulatedClock = {}, now
for id = 98001, 98020 do
    values["item:" .. id] = 100
    budgetRows[#budgetRows + 1] = scanned(id, "item:" .. id, 1, 50)
end
local normalBudgetInfo, normalBudgetTime = C_Item.GetItemInfo, GetTimePreciseSec
C_Item.GetItemInfo = function(reference)
    simulatedClock = simulatedClock + 0.001
    return normalBudgetInfo(reference)
end
GetTimePreciseSec = function() return simulatedClock end
local beforeBudget = itemLookups
listener:ReceiveEvent("complete", budgetRows)
check(itemLookups - beforeBudget <= 5 and window.rows[1].deal and not window.scan.enabled,
    "valuation yields within its precise time budget even while frame GetTime is unchanged")
runImmediate()
check(window.scan.enabled and window.page.text == "1 / 3", "time-budgeted valuation resumes until every candidate is processed")
C_Item.GetItemInfo, GetTimePreciseSec = normalBudgetInfo, normalBudgetTime

-- Receive/compare/publish provider batches before its ScanComplete event.
local pipelineBrowse = Auctionator.State.IncrementalScanFrameRef
local incoming = {}
for id = 99001, 99004 do
    values["item:" .. id] = 100
    incoming[#incoming + 1] = { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 5, minPrice = 50 }
end
pipelineBrowse.rawScan = { incoming[4] } -- A buffer left by a canceled prior scan.
pipelineBrowse.doingFullScan = true
local beforeIncomingLookups = itemLookups
listener:ReceiveEvent("browse_start")
listener:ReceiveEvent("browse_progress", 0.1)
check(itemLookups == beforeIncomingLookups and not window.rows[1].deal,
    "scan start ignores the old browse buffer until the first fresh result batch")
pipelineBrowse.rawScan = { incoming[1] }
listener:ReceiveEvent("browse_progress", 0.2)
check(window.rows[1].deal.itemID == 99001 and window.rows[1].action.enabled and not window.scan.enabled,
    "fresh browse results are compared and displayed before completion without interrupting provider scanning")
local afterIncomingLookups = itemLookups
listener:ReceiveEvent("browse_progress", 0.2)
check(itemLookups == afterIncomingLookups, "repeated scan progress does not repeat valuation of received rows")
pipelineBrowse.rawScan[2] = incoming[2]
listener:ReceiveEvent("browse_progress", 0.3)
timeout() -- Coalesced publication flushes even if the server sends nothing else.
check(window.rows[2].deal.itemID == 99002 and not window.scan.enabled,
    "new candidates publish while waiting for the next server batch rather than waiting for ScanComplete")
local activeIncomingTimers = 0
for _, scheduled in ipairs(timers) do if not scheduled.cancelled then activeIncomingTimers = activeIncomingTimers + 1 end end
check(activeIncomingTimers == 0, "a drained incoming queue uses no idle polling or timer")
pipelineBrowse.rawScan, pipelineBrowse.doingFullScan = {}, false
listener:ReceiveEvent("browse_progress", 0.99)
check(window.rows[1].action.enabled, "early candidates become buyable when the provider releases its scan busy state")
results = { listing(99011, "item:99001", 1, 50) }
click(window.rows[1].action)
event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(99001))
check(popup.shown, "a candidate can be quoted while the provider finishes its database stage")
listener:ReceiveEvent("browse_complete", { incoming[1], incoming[2], incoming[3] })
check(popup.shown and popup.data.auctionID == 99011 and not window.rows[3].deal,
    "provider completion queues final rows without canceling an early purchase or stealing its timer")
cancelPopup()
runImmediate()
check(window.scan.enabled and window.rows[3].deal.itemID == 99003,
    "valuation resumes after the quote and merges final rows with early results")
local incomingBucket = ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)]
check(incomingBucket.records["browse:99001:0:0:0"].samples == 1
    and incomingBucket.records["browse:99002:0:0:0"].samples == 1
    and incomingBucket.records["browse:99003:0:0:0"].samples == 1
    and not incomingBucket.records["browse:99004:0:0:0"],
    "final payload merging records each observed source row once and never records the stale buffer")

local pipelineFull = Auctionator.State.FullScanFrameRef
C_AuctionHouse.GetNumReplicateItems = function() return 1000 end
local sparseRows = {}
for id = 99101, 99104 do
    values["item:" .. id] = 100
    sparseRows[#sparseRows + 1] = scanned(id, "item:" .. id, 1, 50)
end
listener:ReceiveEvent("start")
pipelineFull.inProgress = true
pipelineFull.scanData = { [1] = sparseRows[1], [3] = sparseRows[3] }
listener:ReceiveEvent("progress", 0.4)
check(window.rows[1].deal.itemID == 99101 and window.rows[2].deal.itemID == 99103
    and window.rows[1].action.enabled, "prepared replicate rows are clickable while arriving around sparse holes")
local sparseLookups = itemLookups
listener:ReceiveEvent("progress", 0.3)
check(itemLookups == sparseLookups, "regressed progress cannot repeat already-valued replicate rows")
pipelineFull.scanData[2] = sparseRows[2]
pipelineFull.scanData[1000] = sparseRows[4]
values["item:99102"] = nil
pipelineFull.inProgress, pipelineFull.scanData = false, {}
listener:ReceiveEvent("progress", 0.99)
listener:ReceiveEvent("complete", sparseRows)
check(not window.scan.enabled and eventFrame.events.ITEM_DATA_LOAD_RESULT,
    "completion reconciles delayed sparse rows and loads missing vendor data")
values["item:99102"] = 100
event("ITEM_DATA_LOAD_RESULT", 99102, true)
runImmediate()
check(window.scan.enabled and window.rows[4].deal.itemID == 99104,
    "replicate pipeline finishes with all final and vendor-ready rows")
for id = 99101, 99104 do
    check(incomingBucket.records["replicate:" .. id].samples == 1,
        "replicate final payload reconciles sparse rows without duplicating price-history observations")
end

pipelineBrowse.doingFullScan = true
listener:ReceiveEvent("browse_start")
pipelineBrowse.rawScan = { incoming[1], incoming[2] }
listener:ReceiveEvent("browse_progress", 0.4)
pipelineBrowse.doingFullScan = false
listener:ReceiveEvent("browse_failed")
local failedLookups = itemLookups
drain()
listener:ReceiveEvent("browse_progress", 0.8)
check(window.scan.enabled and itemLookups == failedLookups and window.progress.text.text:find("failed", 1, true),
    "a failed provider scan stops pending valuation/publication and ignores later progress")

pipelineBrowse.doingFullScan = true
listener:ReceiveEvent("browse_start")
pipelineBrowse.rawScan = {}
-- Use distinct row objects, as produced by the provider, for a multi-slice batch.
for i = 1, 3000 do
    pipelineBrowse.rawScan[i] = { itemKey = incoming[1].itemKey, totalQuantity = 5, minPrice = 50 }
end
local beforeQueuedSamples = incomingBucket.records["browse:99001:0:0:0"].samples
listener:ReceiveEvent("browse_progress", 0.4)
check(incomingBucket.records["browse:99001:0:0:0"].samples == beforeQueuedSamples + 1000,
    "a large provider batch stays bounded instead of valuing every received row at once")
event("AUCTION_HOUSE_CLOSED")
pipelineBrowse.doingFullScan = false
drain()
check(incomingBucket.records["browse:99001:0:0:0"].samples == beforeQueuedSamples + 1000,
    "closing the Auction House cancels the remaining streamed valuation")
event("AUCTION_HOUSE_SHOW")
SlashCmdList.PROFITMASTER()

-- Cold vendor data loads alongside incoming pages, using the same bounded queue.
do
    local coldPages = {}
    for id = 99201, 99240 do
        values["item:" .. id] = nil
        coldPages[#coldPages + 1] = { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 2, minPrice = 50 }
    end
    itemRequests = {}
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = {}
    for i = 1, 35 do pipelineBrowse.rawScan[i] = coldPages[i] end
    listener:ReceiveEvent("browse_progress", 0.3)
    check(#itemRequests == 32 and eventFrame.events.ITEM_DATA_LOAD_RESULT,
        "first cold provider page starts at most 32 vendor requests before provider completion")
    values["item:99201"] = 100
    event("ITEM_DATA_LOAD_RESULT", 99201, true)
    check(#itemRequests == 33 and window.rows[1].deal.itemID == 99201 and window.rows[1].action.enabled,
        "vendor completion publishes before the next provider page and refills only its free slot")
    values["item:99201"] = nil -- The scan retains the actual price despite native eviction.
    for i = 36, 40 do pipelineBrowse.rawScan[i] = coldPages[i] end
    listener:ReceiveEvent("browse_progress", 0.5)
    check(#itemRequests == 33, "a second provider page cannot exceed the shared in-flight limit")
    for id = 99202, 99240 do
        values["item:" .. id] = 100
        event("GET_ITEM_INFO_RECEIVED", id, true)
        values["item:" .. id] = nil
    end
    runImmediate()
    local activeTimers = 0
    for _, scheduled in ipairs(timers) do if not scheduled.cancelled then activeTimers = activeTimers + 1 end end
    check(#itemRequests == 40 and activeTimers <= 1,
        "streamed loading requests each ID once and shares at most one publication timer")
    if activeTimers > 0 then timeout() end
    activeTimers = 0
    for _, scheduled in ipairs(timers) do if not scheduled.cancelled then activeTimers = activeTimers + 1 end end
    check(activeTimers == 0 and not window.scan.enabled,
        "fully loaded incoming pages wait for the provider without idle polling or premature completion")
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", coldPages)
    runImmediate()
    check(window.scan.enabled and #itemRequests == 40 and window.status.text:find("priced 40; unavailable 0", 1, true)
        and not eventFrame.events.ITEM_DATA_LOAD_RESULT,
        "completion reuses early prices after eviction without repeat requests or missing rows")
    for id = 99201, 99240 do
        check(incomingBucket.records["browse:" .. id .. ":0:0:0"].samples == 1,
            "overlapped vendor loading never repeats auction-history observations")
    end

    -- An incoming load is allowed to remain pending; the final budget starts at input close.
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { coldPages[1] }
    listener:ReceiveEvent("browse_progress", 0.3)
    now = now + 90
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", { coldPages[1] })
    now = now + 30
    values["item:99201"] = 100
    event("ITEM_DATA_LOAD_RESULT", 99201, true)
    runImmediate()
    check(window.scan.enabled and window.status.text:find("unavailable 0", 1, true),
        "a slow provider does not consume the final vendor-loading budget")

    itemRequests = {}
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { coldPages[1], coldPages[2] }
    listener:ReceiveEvent("browse_progress", 0.3)
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_progress", 0.99)
    results = { listing(99299, "item:99201", 1, 50) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(99201))
    values["item:99202"] = 100
    event("ITEM_DATA_LOAD_RESULT", 99202, true)
    values["item:99202"] = nil
    listener:ReceiveEvent("browse_complete", { coldPages[1], coldPages[2], coldPages[3] })
    check(popup.shown and #itemRequests == 1,
        "early vendor completion and final rows arriving during a quote cannot take over its timer or send more loads")
    confirmPopup()
    event("AUCTION_HOUSE_SHOW_ERROR", 10)
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 99299)
    runImmediate()
    check(#itemRequests == 2 and itemRequests[2] == 99203 and not window.scan.enabled,
        "resolved uncertain purchase resumes early loading at its original cursor and includes final rows")
    values["item:99203"] = 200
    event("GET_ITEM_INFO_RECEIVED", 99203, true)
    runImmediate()
    check(window.scan.enabled and window.rows[1].deal.itemID == 99203 and window.rows[2].deal.itemID == 99202
        and not window.rows[3].deal and window.status.text:find("unavailable 0", 1, true),
        "resumed loading retains prices captured during the pause and never restores the excluded uncertain offer")

    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { coldPages[2] }
    listener:ReceiveEvent("browse_progress", 0.3)
    local requestsBeforeFailure = #itemRequests
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_failed")
    event("ITEM_DATA_LOAD_RESULT", 99202, true)
    drain()
    check(window.scan.enabled and #itemRequests == requestsBeforeFailure
        and not eventFrame.events.ITEM_DATA_LOAD_RESULT and not eventFrame.events.GET_ITEM_INFO_RECEIVED,
        "provider failure cancels early loading and late events cannot restart it")
end

-- One player action buys a selected commodity quantity through the quote API.
local function CheckCommodityPurchases()
    check(not window.debug:GetChecked(), "Enable debug checkbox reflects the default-off preference")
    window.debug:SetChecked(true)
    click(window.debug)
    check(addon.Diagnostics.Enabled(), "explicit Enable debug checkbox starts detailed logging")
    local rows, starts, confirms, cancels, commodityRefreshes, commodityPages = {}, {}, {}, 0, 0, 0
    local quoteDuration, syncQuote, syncSuccess, rejectStart = 10, false, false, false
    local id = 200001
    local function tier(auctionID, quantity, price, owned, accountOwned)
        return { auctionID = auctionID, itemID = id, quantity = quantity, unitPrice = price,
            numOwnerItems = owned or 0, containsOwnerItem = (owned or 0) > 0,
            containsAccountItem = accountOwned or false }
    end
    C_AuctionHouse.GetNumCommoditySearchResults = function() return #rows end
    C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index) return rows[index] end
    C_AuctionHouse.HasFullCommoditySearchResults = function() return full end
    C_AuctionHouse.GetQuoteDurationRemaining = function() return quoteDuration end
    C_AuctionHouse.CancelCommoditiesPurchase = function() cancels = cancels + 1 end
    C_AuctionHouse.RefreshCommoditySearchResults = function(itemID)
        check(itemID == id, "post-buy refresh requests only the purchased commodity")
        commodityRefreshes = commodityRefreshes + 1
    end
    C_AuctionHouse.RequestMoreCommoditySearchResults = function(itemID)
        check(itemID == id, "commodity pagination keeps the selected item")
        commodityPages = commodityPages + 1
    end
    C_AuctionHouse.StartCommoditiesPurchase = function(itemID, quantity)
        check(hardwareClick, "a commodity quantity transaction starts only from the player's Buy quantity click")
        starts[#starts + 1] = { itemID, quantity }
        if rejectStart then
            rejectStart = false
            event("ADDON_ACTION_BLOCKED", "ProfitMaster", "C_AuctionHouse.StartCommoditiesPurchase()")
        elseif syncQuote then
            syncQuote = false
            event("COMMODITY_PRICE_UPDATED", 50, quantity * 50)
        end
    end
    C_AuctionHouse.ConfirmCommoditiesPurchase = function(itemID, quantity)
        check(starts[#starts][1] == itemID and starts[#starts][2] == quantity,
            "server confirmation is bound to the exact item and quantity authorized by the last player click")
        confirms[#confirms + 1] = { itemID, quantity }
        if syncSuccess then syncSuccess = false; event("COMMODITY_PURCHASE_SUCCEEDED") end
    end
    local function openCommodity(book, funds)
        commodity, full, throttle, money = true, true, true, funds or 100000
        values["item:" .. id], values["item:200002"] = 100, 100
        rows, quoteDuration = book or { tier(1, 10, 50), tier(2, 100, 51) }, 10
        listener:ReceiveEvent("browse_complete", {
            { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 110, minPrice = 50 },
            { itemKey = C_AuctionHouse.MakeItemKey(200002), totalQuantity = 2, minPrice = 80 },
        })
        click(window.rows[1].action)
        event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    end
    local beforeCommodityBids = #bids
    openCommodity()
    check(popup.shown and StaticPopupDialogs[popup.which].button1 == "Buy quantity"
        and popup:GetEditBox():GetText() == "10" and popup.data.available == 10,
        "commodity popup defaults to maximum stock at only the cheapest eligible price")
    check(popup.text:find("Buy 10 for 500", 1, true) and popup.text:find("Potential profit: 500", 1, true),
        "commodity popup shows quantity totals with per-item vendor and profit values")
    check(popup:GetButton1().text == "Buy 10" and #starts == 0,
        "commodity caption shows its actual selected transaction quantity without starting a purchase")
    for _, invalid in ipairs({ "", "0", "-1", "1.5", "11", "abc" }) do
        popup:GetEditBox():SetText(invalid)
        confirmPopup()
        check(popup.shown and #starts == 0 and not popup:GetButton1().enabled,
            "invalid or over-tier quantities cannot start a commodity purchase")
    end
    popup:GetEditBox():SetText("4")
    check(popup.text:find("Buy 4 for 200", 1, true) and popup:GetButton1().enabled
        and popup:GetButton1().text == "Buy 4" and #starts == 0,
        "editing quantity immediately updates the displayed total and Buy state")
    confirmPopup()
    check(#starts == 1 and starts[1][2] == 4 and #confirms == 0 and not popup.shown,
        "one Buy quantity click requests one four-item quote and waits for server pricing")
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", id)
    check(#confirms == 0 and commodityRefreshes == 0,
        "an individual-auction completion cannot complete a pending commodity transaction")
    event("COMMODITY_PURCHASE_SUCCEEDED")
    check(commodityRefreshes == 0, "success before the authorized quote is confirmed cannot complete a transaction")
    event("COMMODITY_PRICE_UPDATED", 50, 200)
    event("COMMODITY_PRICE_UPDATED", 50, 200)
    check(#confirms == 1 and confirms[1][2] == 4 and #bids == beforeCommodityBids,
        "matching server pricing confirms the whole quantity once without per-item bids or another click")
    event("COMMODITY_PURCHASE_SUCCEEDED")
    rows = { tier(3, 6, 50), tier(2, 100, 51) }
    runImmediate()
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    check(commodityRefreshes == 1 and window.rows[1].quantity.text == 6 and not popup.shown
        and window.rows[1].action.enabled and #starts == 1,
        "success refreshes only that commodity and keeps remaining same-price stock without another purchase")

    for _, prices in ipairs({ { 51, 510 }, { 50, 501 }, { 49, 490 }, { "SECRET", 500 }, { 50, "SECRET" } }) do
        openCommodity()
        confirmPopup()
        local beforeRejected, beforeCancel = #confirms, cancels
        event("COMMODITY_PRICE_UPDATED", prices[1], prices[2])
        event("COMMODITY_PRICE_UPDATED", 50, 500)
        check(#confirms == beforeRejected and cancels == beforeCancel + 1 and window.rows[1].deal.itemID == 200002,
            "changed unit/total or secret quotes cancel without spending and remove the stale candidate")
    end
    for _, failure in ipairs({ "expired", "gold", "vendor", "combat" }) do
        openCommodity()
        confirmPopup()
        local previous = #confirms
        if failure == "expired" then quoteDuration = 0
        elseif failure == "gold" then money = 1
        elseif failure == "vendor" then values["item:" .. id] = 52
        else InCombatLockdown = function() return true end end
        event("COMMODITY_PRICE_UPDATED", 50, 500)
        local expectedID = (failure == "expired" or failure == "vendor") and 200002 or id
        check(#confirms == previous and window.rows[1].deal.itemID == expectedID,
            "expired or invalid-vendor offers are removed; changed gold/combat never confirm a purchase")
        InCombatLockdown = nil
    end
    openCommodity(nil, 120)
    check(popup:GetEditBox():GetText() == "2", "commodity maximum-stock default respects current gold")
    check(popup:GetButton1().text == "Buy 2" and popup.text:find("Buy 2 for 100", 1, true),
        "commodity affordability cap updates the displayed transaction quantity and total")
    cancelPopup()
    openCommodity({ tier(10, 20, 50, 8), tier(11, 100, 50, 0, true), tier(10, 20, 50, 8) })
    check(popup.data.available == 12 and popup:GetEditBox():GetText() == "12",
        "commodity availability subtracts owned quantities and skips account-owned rows and duplicate IDs")
    cancelPopup()
    check(not addon.CommodityDeal(tier(20, 100, 98)) and not addon.CommodityDeal(tier(21, 100, 99))
        and addon.CommodityDeal(tier(22, 100, 97)).profit == 3,
        "commodity eligibility keeps the inclusive three-copper per-item minimum regardless of quantity")

    openCommodity()
    local canceledCommodity, canceledKind = popup.data, popup.which
    cancelPopup()
    local beforeStale = #starts
    StaticPopupDialogs[canceledKind].OnAccept({}, canceledCommodity)
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    check(#starts == beforeStale, "canceled commodity dialogs and unsolicited price events cannot purchase")
    openCommodity()
    confirmPopup()
    local beforeUnavailable = #confirms
    event("COMMODITY_PRICE_UNAVAILABLE")
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    check(#confirms == beforeUnavailable and window.rows[1].deal.itemID == 200002,
        "unavailable server quotes remove the attempted offer without a retry")

    for _, errorKind in ipairs({ "COMMODITY_PURCHASE_FAILED", "UI_ERROR_MESSAGE", "AUCTION_HOUSE_SHOW_ERROR" }) do
        openCommodity()
        confirmPopup()
        event("COMMODITY_PRICE_UPDATED", 50, 500)
        local beforeFailure = #confirms
        if errorKind == "UI_ERROR_MESSAGE" then event(errorKind, 999, ERR_AUCTION_DATABASE_ERROR)
        else event(errorKind) end
        event("COMMODITY_PRICE_UPDATED", 50, 500)
        drain()
        check(window.rows[1].deal.itemID == 200002 and #confirms == beforeFailure
            and not eventFrame.events.COMMODITY_PRICE_UPDATED,
            "failed commodity buys and internal errors remove only their item and release quote listeners")
    end
    openCommodity()
    rejectStart = true
    confirmPopup()
    check(window.rows[1].deal.itemID == 200002 and not popup.shown,
        "a blocked commodity start removes the attempted item without bypassing the restriction")
    openCommodity()
    confirmPopup()
    local beforeTimeout = #confirms
    timeout()
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    check(#confirms == beforeTimeout and window.rows[1].deal.itemID == 200002,
        "unconfirmed commodity timeout removes the attempted item and cannot later spend gold")

    openCommodity()
    confirmPopup()
    local beforeTabCancel = #confirms
    ahLibrary:SetSelected("OtherAddon")
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    SlashCmdList.PROFITMASTER()
    check(#confirms == beforeTabCancel and window.rows[1].deal.itemID == id,
        "switching tabs while awaiting a quote cancels its authorization")

    openCommodity()
    syncQuote, syncSuccess = true, true
    local beforeSync = #confirms
    confirmPopup()
    check(#confirms == beforeSync + 1 and window.status.text:find("purchase confirmed", 1, true),
        "synchronous quote and success events preserve the completed transaction state")
    rows = { tier(30, 100, 51) }
    runImmediate()
    full = false
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    runImmediate()
    check(commodityPages == 1 and window.rows[1].deal.itemID == id,
        "partial commodity stock results request more data before claiming exhaustion")
    full = true
    event("COMMODITY_SEARCH_RESULTS_ADDED", id)
    check(window.rows[1].deal.itemID == 200002 and not window.rows[2].deal,
        "complete results without stock at the purchased price remove only that item")

    openCommodity()
    confirmPopup()
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    event("COMMODITY_PURCHASE_SUCCEEDED")
    rows = { tier(31, 5, 50) }
    values["item:" .. id] = nil
    runImmediate()
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    check(window.rows[1].deal.itemID == id and window.status.text:find("Vendor data unavailable", 1, true),
        "missing vendor metadata after success is incomplete verification rather than proven exhaustion")

    openCommodity()
    cancelPopup()
    rows = {}
    for i = 1, 1000 do rows[i] = tier(100 + i, 1, i == 1000 and 50 or 51) end
    local normalCommodityRead = C_AuctionHouse.GetCommoditySearchResultInfo
    local readCount = 0
    C_AuctionHouse.GetCommoditySearchResultInfo = function(itemID, index)
        readCount = readCount + 1
        return normalCommodityRead(itemID, index)
    end
    click(window.rows[1].action)
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id + 1)
    check(readCount == 0, "unrelated commodity updates cannot populate the selected quote")
    local beforeBookLookups = itemLookups
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    check(readCount == 200 and not popup.shown, "commodity book reads yield after 200 entries")
    runImmediate()
    check(popup.shown and popup.data.cost == 50 and popup.data.available == 1
        and itemLookups == beforeBookLookups + 1,
        "batched commodity reads find the cheapest tier and reuse one vendor lookup")
    cancelPopup()
    C_AuctionHouse.GetCommoditySearchResultInfo = normalCommodityRead

    openCommodity({})
    check(not popup.shown and window.rows[1].deal.itemID == 200002,
        "a complete empty commodity search removes the stale row and advances the list immediately")

    openCommodity()
    values["item:" .. id] = nil
    local beforeVendorDisappeared = #starts
    confirmPopup()
    check(#starts == beforeVendorDisappeared and window.rows[1].deal.itemID == 200002,
        "an offer whose vendor metadata disappears before Buy is removed without starting a quote")
    values["item:" .. id] = 100

    openCommodity()
    cancelPopup()
    rows, full = {}, false
    click(window.rows[1].action)
    event("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    now = now + 20
    click(findButton("More listings"))
    rows = { tier(32, 2, 50) }
    event("COMMODITY_SEARCH_RESULTS_ADDED", id)
    check(popup.shown and popup.data.available == 2,
        "a manual commodity pagination request gets a fresh verification deadline")
    cancelPopup()

    openCommodity()
    confirmPopup()
    local beforeLateQuote = #confirms
    now = now + 16
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    check(#confirms == beforeLateQuote and window.rows[1].deal.itemID == 200002,
        "an expired overall quote deadline removes the offer even if the client reports remaining quote time")

    openCommodity()
    confirmPopup()
    local beforeClose = #confirms
    event("AUCTION_HOUSE_CLOSED")
    event("COMMODITY_PRICE_UPDATED", 50, 500)
    drain()
    check(#confirms == beforeClose and not eventFrame.events.COMMODITY_PRICE_UPDATED,
        "closing the Auction House cancels pending commodity authorization and timers")
    commodity, money, full = false, 100000, true
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
end
CheckCommodityPurchases()

local function CheckDisenchantOffers()
    local originalInfo, originalLevel, originalAPI = C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, Auctionator.API
    local prices, evicted = { [10940] = 100, [10938] = 200 }, false
    local id, link = 45001, "item:45001"
    C_Item.GetItemInfo = function(reference)
        if reference == id or reference == link or reference == id + 1 or reference == "item:45002" then
            local returned = (reference == id or reference == link) and link or "item:45002"
            if not evicted then return "DE test armor", returned, 2, 10, 1, "", "", 1, "INVTYPE_CHEST", 136244, 100, 4, 1, 1, 0 end
            return nil
        end
        return originalInfo(reference)
    end
    C_Item.GetDetailedItemLevelInfo = function(reference)
        if reference == id or reference == link or reference == id + 1 or reference == "item:45002" then if not evicted then return 10, false, 10 end
        elseif originalLevel then return originalLevel(reference) end
    end
    Auctionator.API = { v1 = { GetAuctionPriceByItemID = function(caller, material)
        check(caller == "ProfitMaster", "disenchant material queries identify their caller")
        return prices[material]
    end } }
    commodity, full, throttle = false, true, true
    check(not window.disenchant:GetChecked() and not addon.Disenchant.Enabled(), "disenchant profits default off")
    check(window.safeDisenchant:GetChecked() and addon.Disenchant.Safe(), "safe disenchant defaults on")
    window.safeDisenchant:SetChecked(false)
    click(window.safeDisenchant) -- Existing scenarios exercise the explicit average mode.
    window.disenchant:SetChecked(true)
    click(window.disenchant)
    check(ProfitMasterDisenchantDB.enabled and addon.Disenchant.Enabled(), "checkbox persists its independent opt-in preference")
    local data = { { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 2, minPrice = 120 } }
    listener:ReceiveEvent("browse_complete", data)
    runImmediate()
    check(window.rows[1].deal.disenchant and window.rows[1].deal.vendor == 100
        and window.rows[1].deal.deNet == 153 and window.rows[1].deal.profit == 33,
        "above-vendor auction qualifies only from after-fee expected disenchant profit")
    check(window.rows[1].item.text:find("|T880:16|t", 1, true) and window.rows[1].vendor.text == "153"
        and window.headers[4].text == "Vendor / DE est.", "disenchant row displays an icon, DE label and estimated proceeds")
    check(addon.Disenchant.ShouldMark(link), "all profitable bag gear qualifies independently of purchase provenance")
    results = { listing(450101, link, 2, 120) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(id))
    check(popup.shown and popup.text:find("DISENCHANT - do not vendor", 1, true)
        and popup.text:find("15% fee allowance", 1, true) and popup.text:find("Random yields", 1, true),
        "live confirmation identifies disenchant intent, fees and random-yield limitation")
    check(popup:GetEditBox():GetText() == "1" and popup:GetButton1().text == "Buy 1",
        "DE offers retain the conservative half-stock initial goal")
    popup:GetEditBox():SetText("2")
    check(popup:GetButton1().text == "Buy 1 of 2" and popup.text:find("Total purchase cost: 240", 1, true)
        and popup.text:find("Estimated total proceeds: 306", 1, true)
        and popup.text:find("Potential total profit: 66", 1, true),
        "edited DE goals display after-fee expected totals while retaining one-auction clicks")
    popup:GetEditBox():SetText("1")
    local beforeChangedPrice = bidAttempts
    prices[10940] = 50
    confirmPopup()
    check(bidAttempts == beforeChangedPrice and not popup.shown and not window.rows[1].deal,
        "fresh Buy-time material valuation rejects an estimate that is no longer profitable")

    prices[10940] = 100
    local duplicates, keyReads, keyInfo = {}, 0, C_AuctionHouse.GetItemKeyInfo
    for i = 1, 10000 do duplicates[i] = { itemKey = data[1].itemKey, totalQuantity = 1, minPrice = 50 + i % 100 } end
    C_AuctionHouse.GetItemKeyInfo = function(...) keyReads = keyReads + 1; return keyInfo(...) end
    listener:ReceiveEvent("browse_complete", duplicates)
    runImmediate()
    C_AuctionHouse.GetItemKeyInfo = keyInfo
    check(keyReads == 10001 and window.rows[1].deal.disenchant and window.rows[1].deal.cost == 50,
        "ten thousand repeated browse offers need one final DE revaluation and retain the cheapest winning price")

    -- Newly learned material prices must reconcile without native metadata or history duplication.
    prices[10940], prices[10938] = nil, nil
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { data[1] }
    listener:ReceiveEvent("browse_progress", 0.5)
    check(not window.rows[1].deal, "missing material prices do not fabricate a zero-cost or profitable result")
    local observations = ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)].records["browse:45001:0:0:0"].samples
    evicted, prices[10940], prices[10938] = true, 100, 200
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", data)
    runImmediate()
    check(window.rows[1].deal.disenchant and window.rows[1].deal.deNet == 153 and window.scan.enabled,
        "final DE pass uses current-scan material prices and retained metadata after native cache eviction")
    check(ProfitMasterDB.markets.TestPvE.days[math.floor(now / 86400)].records["browse:45001:0:0:0"].samples == observations,
        "final disenchant revaluation never records an auction observation twice")
    evicted = false

    -- Fresh live stock from an early buy takes precedence over snapshot reconciliation.
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { data[1] }
    listener:ReceiveEvent("browse_progress", 0.5)
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_progress", 0.99)
    results = { listing(450102, link, 1, 120) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(id))
    check(popup.shown, "early DE quote must open: " .. window.status.text)
    confirmPopup()
    local afterManualBid = bidAttempts
    event("AUCTION_HOUSE_PURCHASE_COMPLETED", 450102)
    results = { listing(450103, link, 1, 120) }
    runImmediate()
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(id))
    listener:ReceiveEvent("browse_complete", data)
    runImmediate()
    check(window.rows[1].deal.disenchant and window.rows[1].deal.available == 1 and window.scan.enabled
        and bidAttempts == afterManualBid and not popup.shown,
        "final DE reconciliation preserves purchased-item live stock and never buys or disenchants automatically")
    window.disenchant:SetChecked(false)
    click(window.disenchant)
    check(not addon.Disenchant.Enabled() and not addon.Disenchant.ShouldMark(link) and not window.rows[1].deal,
        "disabling DE mode removes its estimates and bag recommendations without a network rescan")

    for _, debugEnabled in ipairs({ true, false }) do
        window.debug:SetChecked(debugEnabled)
        click(window.debug)
        window.disenchant:SetChecked(true)
        click(window.disenchant)
        check(addon.Disenchant.Enabled() and addon.Diagnostics.Enabled() == debugEnabled,
            "enabling DE preserves the independently selected debug preference")
        pipelineBrowse.doingFullScan = true
        listener:ReceiveEvent("browse_start")
        local incoming = {
            { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 1, minPrice = 50 },
            { itemKey = C_AuctionHouse.MakeItemKey(id + 1), totalQuantity = 1, minPrice = 120 },
        }
        pipelineBrowse.rawScan = incoming
        listener:ReceiveEvent("browse_progress", 0.3)
        check(window.rows[1].deal.disenchant and window.rows[2].deal.disenchant and window.disenchant.enabled,
            "an enabled DE checkbox can be turned off while the provider scan is still active")
        window.disenchant:SetChecked(false)
        click(window.disenchant)
        check(not addon.Disenchant.Enabled() and addon.Diagnostics.Enabled() == debugEnabled
            and ProfitMasterDebugDB.enabled == debugEnabled and not ProfitMasterDisenchantDB.enabled,
            "disabling DE during scanning changes only its own saved preference with debug on or off")
        check(window.rows[1].deal.itemID == id and not window.rows[1].deal.disenchant
            and window.rows[1].deal.profit == 50 and not window.rows[2].deal,
            "DE-off converts a known profitable vendor offer and removes an offer profitable only through DE")
        check(not window.disenchant.enabled and not window.scan.enabled,
            "discovery continues vendor-only while enabling DE again waits for idle")
        window.disenchant:SetChecked(true)
        window.disenchant.scripts.OnClick(window.disenchant)
        check(not addon.Disenchant.Enabled() and not window.disenchant:GetChecked(),
            "a busy enable request is rejected without changing the saved preference")
        window.debug:SetChecked(not debugEnabled)
        click(window.debug)
        check(not addon.Disenchant.Enabled(), "toggling debug during vendor-only scanning cannot enable DE")
        window.debug:SetChecked(debugEnabled)
        click(window.debug)
        listener:ReceiveEvent("browse_progress", 0.5)
        timeout()
        check(window.rows[1].deal and not window.rows[1].deal.disenchant and not window.rows[2].deal,
            "a later streamed publication cannot restore entries from the old DE best-result map")
        pipelineBrowse.doingFullScan = false
        listener:ReceiveEvent("browse_complete", incoming)
        runImmediate()
        check(window.scan.enabled and window.disenchant.enabled and not window.rows[1].deal.disenchant
            and addon.Diagnostics.Enabled() == debugEnabled,
            "scan completion preserves independent settings and vendor-only results")
    end

    window.debug:SetChecked(true)
    click(window.debug)
    window.disenchant:SetChecked(true)
    click(window.disenchant)
    listener:ReceiveEvent("browse_complete", data)
    runImmediate()
    results = { listing(450190, link, 1, 120) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(id))
    check(popup.shown and not window.disenchant.enabled, "a live purchase quote retains its mode-change lock")
    window.disenchant:SetChecked(false)
    window.disenchant.scripts.OnClick(window.disenchant)
    check(popup.shown and addon.Disenchant.Enabled() and addon.Diagnostics.Enabled(),
        "rejecting a mode change during a quote preserves authorization and never toggles debug")
    cancelPopup()
    window.disenchant:SetChecked(false)
    click(window.disenchant)
    check(not addon.Disenchant.Enabled() and addon.Diagnostics.Enabled(),
        "after canceling the quote DE switches off directly while debug remains enabled")
    C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, Auctionator.API = originalInfo, originalLevel, originalAPI
end
CheckDisenchantOffers()

local function CheckScanPublicationPerformance()
    local rows = {}
    for id = 46001, 46012 do
        values["item:" .. id] = 100 + id % 100
        rows[#rows + 1] = { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 2, minPrice = 50 }
    end
    local sort, sorts = addon.SortDeals, 0
    addon.SortDeals = function(list) sorts = sorts + 1; return sort(list) end
    pipelineBrowse.doingFullScan = true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { rows[1] }
    listener:ReceiveEvent("browse_progress", 0.2)
    check(window.rows[1].deal and sorts == 1, "first candidate publishes immediately without a coalescing delay")
    for i = 2, #rows do
        now = now + 0.01
        pipelineBrowse.rawScan[i] = rows[i]
        listener:ReceiveEvent("browse_progress", 0.2 + i / 100)
    end
    check(sorts == 1, "a burst of incoming candidates does not repeatedly sort and redraw before the publication interval")
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_complete", rows)
    runImmediate()
    check(sorts == 2 and window.scan.enabled and window.page.text == "1 / 2" and window.rows[1].deal.itemID == 46012,
        "final completion immediately publishes all sorted results with no second unchanged forced sort")
    addon.SortDeals = sort

    local beforeText, beforeMoney = textWrites, moneyFormats
    for _ = 1, 20 do SlashCmdList.PROFITMASTER("debug on") end
    check(textWrites == beforeText and moneyFormats == beforeMoney,
        "twenty control refreshes with unchanged visible results perform no text writes or money formatting")
    local first = window.rows[1].deal
    results = { listing(460101, first.link, 1, first.cost) }
    click(window.rows[1].action)
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(first.itemID))
    check(popup.shown and not window.rows[2].action.enabled,
        "cached display values never defer quote controls or purchase locks")
    cancelPopup()
    check(window.rows[2].action.enabled, "purchase controls unlock immediately after cancellation")
    local report = addon.Diagnostics.Report()
    check(report:find("provider_ms=", 1, true) and report:find("batch_ms=", 1, true)
        and report:find("scan_ms=", 1, true), "debug summary separates provider time, processing slices and total elapsed scan time")
end
CheckScanPublicationPerformance()

local function CheckOwnedBrowsePurchases()
    -- The earlier suite exercises the legacy/external provider path. Load the
    -- production pager here to exercise its interaction with the main controller.
    assert(loadfile("addons/ProfitMaster/BrowseScanner.lua"))("ProfitMaster", addon)
    local pagerFrame = frames[#frames]
    local browseRows, browseFull, browseQueries, browsePages = {}, false, 0, 0
    C_AuctionHouse.GetBrowseResults = function() return browseRows end
    C_AuctionHouse.HasFullBrowseResults = function() return browseFull end
    C_AuctionHouse.SendBrowseQuery = function()
        browseQueries, throttle = browseQueries + 1, false
    end
    C_AuctionHouse.RequestMoreBrowseResults = function()
        browsePages, throttle = browsePages + 1, false
    end
    local function native(name, arg, extra)
        if pagerFrame.events[name] then pagerFrame.scripts.OnEvent(pagerFrame, name, arg, extra) end
        event(name, arg, extra)
    end
    local data = {}
    for id = 48001, 48003 do
        values["item:" .. id] = 100
        data[#data + 1] = { itemKey = C_AuctionHouse.MakeItemKey(id), totalQuantity = 1, minPrice = 50 }
    end
    preferFull, throttle, commodity, full = false, true, false, true
    local externalStarts = browseScans
    click(window.scan)
    check(browseQueries == 1 and browseScans == externalStarts and addon.BrowseScanner.Active(),
        "Profit Master's browse button owns native paging without starting the unpausable external scanner")
    browseRows = { data[1] }
    native("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(window.rows[1].deal.itemID == 48001 and window.rows[1].action.enabled and not window.scan.enabled,
        "Buy is enabled on the first received item while owned discovery remains active")
    local beforeQuery, beforePages, beforeBuy = exactQueries, browsePages, bidAttempts
    results = { listing(480101, "item:48001", 1, 50) }
    click(window.rows[1].action)
    check(addon.BrowseScanner.Paused() and exactQueries == beforeQuery and not popup.shown,
        "selecting Buy immediately pauses discovery and waits only for the in-flight server throttle")
    native("ITEM_SEARCH_RESULTS_UPDATED", data[1].itemKey)
    check(not popup.shown, "stale same-key item events cannot open a quote before the queued verification is sent")
    throttle = true
    native("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(exactQueries == beforeQuery + 1 and browsePages == beforePages,
        "native readiness gives the selected item verification priority over another browse page")
    native("ITEM_SEARCH_RESULTS_UPDATED", data[1].itemKey)
    check(popup.shown and addon.BrowseScanner.Active() and addon.BrowseScanner.Paused(),
        "a live purchase confirmation opens before the browse scan completes")
    browseRows = { data[3] }
    native("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    check(popup.shown and window.rows[1].deal.itemID == 48001 and browsePages == beforePages,
        "item-query browse refreshes neither replace the discovery snapshot nor page during the quote")
    confirmPopup()
    check(bidAttempts == beforeBuy + 1 and browsePages == beforePages,
        "one manual confirmation submits one purchase while discovery stays paused")
    native("AUCTION_HOUSE_PURCHASE_COMPLETED", 480101)
    results = {}
    runImmediate()
    native("ITEM_SEARCH_RESULTS_UPDATED", data[1].itemKey)
    check(browsePages == beforePages + 1 and addon.BrowseScanner.Active() and not addon.BrowseScanner.Paused(),
        "completed stock verification resumes discovery from its existing browse query")
    browseFull = true
    native("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { data[2] })
    runImmediate()
    check(not addon.BrowseScanner.Active() and window.scan.enabled and window.rows[1].deal.itemID == 48002
        and bidAttempts == beforeBuy + 1, "remaining pages finish without restoring the purchased offer or sending another bid")

    -- External scans remain isolated, but their rows accept a bounded queued Buy.
    pipelineBrowse.doingFullScan, throttle = true, true
    listener:ReceiveEvent("browse_start")
    pipelineBrowse.rawScan = { data[3] }
    listener:ReceiveEvent("browse_progress", 0.3)
    beforeQuery = exactQueries
    results = { listing(480103, "item:48003", 1, 50) }
    click(window.rows[1].action)
    native("ITEM_SEARCH_RESULTS_UPDATED", data[3].itemKey)
    native("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    check(exactQueries == beforeQuery and not popup.shown,
        "external Auctionator-owned browsing cannot be interrupted by item verification or stale results")
    pipelineBrowse.doingFullScan = false
    listener:ReceiveEvent("browse_progress", 0.99)
    native("ITEM_SEARCH_RESULTS_UPDATED", data[3].itemKey)
    check(exactQueries == beforeQuery + 1 and popup.shown,
        "external scan release automatically starts the already selected read-only check")
    cancelPopup()
    listener:ReceiveEvent("browse_complete", { data[3] })
    runImmediate()

    -- Replicate data is a separate native result store and needs no browse pause.
    local replicate = Auctionator.State.FullScanFrameRef
    replicate.inProgress = true
    listener:ReceiveEvent("start")
    local replicateRows = { scanned(48001, "item:48001", 1, 50) }
    replicate.scanData = replicateRows
    listener:ReceiveEvent("progress", 0.4)
    local beforeReplicaQuery = queries
    results = { listing(480104, "item:48001", 1, 50) }
    click(window.rows[1].action)
    native("ITEM_SEARCH_RESULTS_UPDATED", data[1].itemKey)
    check(queries == beforeReplicaQuery + 1 and popup.shown and replicate.inProgress,
        "replicate processing permits a live item quote without waiting for its independent snapshot to finish")
    cancelPopup()
    replicate.inProgress, replicate.scanData = false, {}
    listener:ReceiveEvent("complete", replicateRows)
    runImmediate()

    for _, outcome in ipairs({ "unaffordable", "missing", "partial" }) do
        throttle, browseFull, full = true, false, true
        click(window.scan)
        browseRows = { data[1] }
        native("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        click(window.rows[1].action)
        throttle = true
        native("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        local funds = money
        if outcome == "unaffordable" then
            money, results = 1, { listing(480201, "item:48001", 1, 50) }
        elseif outcome == "missing" then
            results = { listing(480202, "item:48001:uncached", 1, 50) }
        else results, full = {}, false end
        native("ITEM_SEARCH_RESULTS_UPDATED", data[1].itemKey)
        if outcome == "partial" then
            check(addon.BrowseScanner.Paused() and findButton("More listings"),
                "partial live results retain a bounded manual More listings opportunity")
            timeout()
        end
        check(addon.BrowseScanner.Active() and not addon.BrowseScanner.Paused() and not popup.shown
            and bidAttempts == beforeBuy + 1,
            "unaffordable, missing and abandoned partial results always release discovery without buying")
        money, full = funds, true
        native("AUCTION_HOUSE_CLOSED")
        throttle = true
        event("AUCTION_HOUSE_SHOW")
        SlashCmdList.PROFITMASTER()
    end

    -- AH close and tab leave must release both query scheduling and local waits.
    throttle, browseFull = true, false
    click(window.scan)
    browseRows = { data[1] }
    native("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    click(window.rows[1].action)
    beforeQuery = exactQueries
    native("AUCTION_HOUSE_CLOSED")
    throttle = true
    native("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    drain()
    check(not addon.BrowseScanner.Active() and exactQueries == beforeQuery and bidAttempts == beforeBuy + 1,
        "closing AH cancels queued verification and owned paging without spending or resuming")
    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER()
    throttle = true
    click(window.scan)
    browseRows = { data[1] }
    native("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    ahLibrary:SetSelected("OtherAddon")
    runImmediate()
    check(not addon.BrowseScanner.Active() and window.progress.text.text:find("Partial scan", 1, true),
        "leaving the tab stops owned discovery and labels its existing results partial")
    throttle = true
    SlashCmdList.PROFITMASTER()
    preferFull = true
end
CheckOwnedBrowsePurchases()

local function CheckDebugReport()
    local report = addon.Diagnostics.Report()
    check(report:find("commodity_quote_received", 1, true) and report:find("received_unit=51", 1, true)
        and report:find("expected_unit=50", 1, true) and report:find("removed=true", 1, true),
        "purchase debugging includes expected/received prices, events and row-removal decisions")
    check(report:find("received_unit=<restricted>", 1, true) and not report:find("SECRET", 1, true),
        "enabled purchase logging redacts restricted native payloads")
    local records = ProfitMasterDebugDB.count
    CopyToClipboard = function() error("clipboard API must never be called") end
    click(window.log)
    local copyBox
    for _, frame in ipairs(frames) do if frame.kind == "EditBox" then copyBox = frame end end
    check(copyBox and copyBox.text == addon.Diagnostics.Report() and copyBox.focused and copyBox.highlighted,
        "Debug log opens a selected copyable snapshot using manual Ctrl+C")
    check(ProfitMasterDebugDB.count == records, "viewing a report does not poll or modify the log")
    click(findButton("Close"))
    check(not copyBox.focused and not copyBox:IsShown(), "closing the debug panel releases edit-box focus")
    SlashCmdList.PROFITMASTER("debug off")
    check(not addon.Diagnostics.Enabled() and not window.debug:GetChecked(), "debug off synchronizes the checkbox")
    records = ProfitMasterDebugDB.count
    addon.Diagnostics.Log("must_not_appear")
    check(ProfitMasterDebugDB.count == records, "disabled logging stops recording without discarding the captured failure")
    SlashCmdList.PROFITMASTER("log")
    check(copyBox:IsShown() and copyBox.text:find("Debug: disabled", 1, true),
        "slash log command can display retained diagnostics with debug disabled")
    copyBox.scripts.OnEscapePressed(copyBox)
    CopyToClipboard = nil
end
CheckDebugReport()

beginRecheck(9191)
beforeRefresh = refreshes
event("AUCTION_HOUSE_CLOSED")
drain()
check(refreshes == beforeRefresh and not eventFrame.events.AUCTION_HOUSE_THROTTLED_SYSTEM_READY,
    "closing AH cancels the deferred stock request, deadline and readiness listener")
for _, frame in ipairs(frames) do
    check(not frame.scripts.OnUpdate, "no per-frame polling")
end
print("Profit Master: " .. checks .. " offline assertions passed (Lua 5.1).")
