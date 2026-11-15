-- Real production handlers with the existing offline AH harness. No game input.
local file = assert(io.open("tools/Test-ProfitMaster.lua", "r"))
local source = file:read("*a")
file:close()
local cases = [=[
local function CheckSettingsUI()
    local beforeChecks = checks
    local function requests() return queries + exactQueries + refreshes + more + scans + browseScans end
    local beforeRequests, beforeBids = requests(), bidAttempts
    -- Native movement is mocked; points are expressed in each frame's own scale.
    function methods:SetClampedToScreen(value) self.clamped = value end
    function methods:SetMovable(value) self.movable = value end
    function methods:SetUserPlaced(value) self.userPlaced = value end
    function methods:SetHighlightTexture(value) self.highlight = value end
    function methods:SetTexture(value) self.texture = value end
    function methods:SetAtlas(value) self.atlas = value end
    function methods:RegisterForClicks(...) self.clicks = { ... } end
    function methods:RegisterForDrag(...) self.dragButtons = { ... } end
    function methods:StartMoving() self.moving = true end
    function methods:StopMovingOrSizing() self.moving = false end
    function methods:GetCenter() return self.centerX, self.centerY end
    function methods:GetEffectiveScale() return self.scale or 1 end
    function methods:GetLeft() return self.left end
    function methods:GetTop() return self.top end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:IsForbidden() return self.forbidden == true end
    local combat = false
    InCombatLockdown = function() return combat end
    Minimap = CreateFrame("Frame")
    Minimap.left, Minimap.top, Minimap.scale = 100, 200, 2
    GameTooltip = {
        SetOwner = function(self, owner) self.owner = owner end,
        SetText = function(self, text) self.text = text end,
        AddLine = function(self, text) self.line = text end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    addon.Settings.CreateMinimapButton()
    local icon
    for _, button in ipairs(buttons) do if button.parent == Minimap then icon = button end end
    check(icon and icon.movable and icon.clamped and icon.dragButtons[1] == "LeftButton",
        "minimap launcher uses a bounded native draggable button")
    check(icon.point[2] == Minimap and icon.point[3] == "TOPLEFT" and icon.point[4] == -8,
        "default position references the map corner, not a circle radius or angle")
    local frameCount = #frames
    addon.Settings.CreateMinimapButton()
    check(#frames == frameCount, "repeated startup cannot duplicate the minimap button")
    icon.scripts.OnEnter(icon)
    check(GameTooltip.shown and GameTooltip.text == "Profit Master"
        and GameTooltip.line:find("square", 1, true), "launcher tooltip identifies settings and free placement")
    icon.scripts.OnLeave(icon)
    check(not GameTooltip.shown, "launcher tooltip closes on mouse leave")
    click(icon)
    local panel
    for _, frame in ipairs(frames) do if frame.minimumProfit and frame ~= window then panel = frame end end
    check(panel and panel:IsShown() and panel.parent == UIParent, "minimap click opens independent settings while AH is closed")
    check(panel.debug:GetChecked() == addon.Diagnostics.Enabled()
        and panel.safeDisenchant:GetChecked() == addon.Disenchant.Safe()
        and panel.minimumProfit:GetText() == tostring(addon.GetMinimumProfit()),
        "panel reflects effective saved settings without an auction house")
    local previousDebug = addon.Diagnostics.Enabled()
    panel.debug:SetChecked(not previousDebug)
    click(panel.debug)
    check(addon.Diagnostics.Enabled() == not previousDebug and window.debug:GetChecked() == not previousDebug,
        "panel uses the same debug setting and updates the AH checkbox")
    window.debug:SetChecked(previousDebug)
    click(window.debug)
    check(panel.debug:GetChecked() == previousDebug, "AH settings synchronize back into the open panel")
    panel.disenchant:SetChecked(true)
    click(panel.disenchant)
    check(addon.Disenchant.Enabled() and window.disenchant:GetChecked(), "outside-AH DE setting synchronizes to auction controls")
    panel.safeDisenchant:SetChecked(false)
    click(panel.safeDisenchant)
    check(not addon.Disenchant.Safe() and not window.safeDisenchant:GetChecked(), "safe setting is shared in both directions")
    local field = panel.minimumProfit
    field:SetFocus()
    field:SetText("10")
    field.scripts.OnEnterPressed(field)
    check(addon.GetMinimumProfit() == 10 and ProfitMasterDB.minimumProfit == 10
        and window.minimumProfit:GetText() == "10" and not field:HasFocus(),
        "settings minimum applies, persists and synchronizes on Enter")
    field:SetFocus()
    field:SetText("12")
    field:ClearFocus()
    check(addon.GetMinimumProfit() == 12 and window.minimumProfit:GetText() == "12", "focus loss applies minimum from the panel")
    field:SetFocus()
    field:SetText("99")
    field.scripts.OnEscapePressed(field)
    check(addon.GetMinimumProfit() == 12 and field:GetText() == "12", "Escape restores the saved minimum")
    field:SetText("bad")
    field.scripts.OnEnterPressed(field)
    check(field:GetText() == "12" and addon.GetMinimumProfit() == 12, "invalid input cannot change the minimum")
    check(requests() == beforeRequests and bidAttempts == beforeBids,
        "opening/settings changes outside the AH issue no queries or purchases")

    -- Dragging keeps arbitrary square corners, works at differing frame scales,
    -- and stays anchored to the minimap when the map is moved/resized by an addon.
    click(icon) -- close panel
    icon.centerX, icon.centerY, icon.scale = 480, 620, 1
    icon.scripts.OnDragStart(icon)
    check(icon.moving, "drag starts native movement without a polling handler")
    icon.scripts.OnDragStop(icon)
    check(not icon.moving and ProfitMasterDB.minimap.x == 140 and ProfitMasterDB.minimap.y == 110,
        "drag saves scale-correct offsets from the map corner")
    check(icon.point[2] == Minimap and icon.point[3] == "TOPLEFT"
        and icon.point[4] == 140 and icon.point[5] == 110 and icon.userPlaced == false,
        "square corner placement is kept exactly, not projected onto a circle")
    local function restore(shape, x, y)
        Minimap.shape = shape
        addon.Settings.Initialize({ minimap = { x = x, y = y } })
        check(icon.point[2] == Minimap and icon.point[4] == x and icon.point[5] == y,
            "position restores without shape assumptions: " .. shape)
    end
    restore("SQUARE", 90, -90)
    restore("ROUND", -15, -45)
    combat = true
    icon.scripts.OnDragStart(icon)
    check(not icon.moving, "combat does not begin a minimap drag")
    combat = false
    Minimap.forbidden = true
    icon.scripts.OnDragStart(icon)
    icon.scripts.OnDragStop(icon)
    check(icon.point[4] == -15, "unavailable map coordinates cannot replace the last usable offset")
    Minimap.forbidden = false
    addon.Settings.Initialize(ProfitMasterDB)

    event("AUCTION_HOUSE_SHOW")
    SlashCmdList.PROFITMASTER("settings")
    check(panel:IsShown(), "slash settings is an alternate access path")
    canFullScan = true
    click(window.scan)
    check(not panel.safeDisenchant.enabled and panel.minimumProfit.enabled,
        "settings panel mirrors safe/minimum locks during a scan")
    panel.safeDisenchant:SetChecked(true)
    panel.safeDisenchant.scripts.OnClick(panel.safeDisenchant)
    check(not addon.Disenchant.Safe() and not panel.safeDisenchant:GetChecked(),
        "stale panel click cannot alter the scan's valuation mode")
    listener:ReceiveEvent("complete", {})
    runImmediate()
    check(panel.safeDisenchant.enabled, "completed scan releases settings locks")

    values["item:49701"] = 100
    listener:ReceiveEvent("complete", { scanned(49701, "item:49701", 1, 80) })
    runImmediate()
    commodity, full, throttle = false, true, true
    results = { listing(497101, "item:49701", 1, 80) }
    click(window.rows[1].action)
    check(not panel.minimumProfit.enabled and not panel.safeDisenchant.enabled and not panel.disenchant.enabled,
        "live verification locks the independent panel as well as the auction controls")
    panel.disenchant:SetChecked(false)
    panel.disenchant.scripts.OnClick(panel.disenchant)
    field:SetText("1")
    field.scripts.OnEnterPressed(field)
    check(addon.Disenchant.Enabled() and panel.disenchant:GetChecked() and addon.GetMinimumProfit() == 12,
        "queued panel toggles/edits cannot bypass active purchase guards")
    event("ITEM_SEARCH_RESULTS_UPDATED", C_AuctionHouse.MakeItemKey(49701))
    check(popup.shown and not panel.minimumProfit.enabled, "an open quote retains all settings locks")
    cancelPopup()
    event("AUCTION_HOUSE_CLOSED")
    drain()
    SlashCmdList.PROFITMASTER("settings") -- close
    SlashCmdList.PROFITMASTER("settings") -- reopen
    local reusable = #frames
    SlashCmdList.PROFITMASTER("settings")
    SlashCmdList.PROFITMASTER("settings")
    check(#frames == reusable, "reopening settings reuses its controls")
    local report = findButton("Debug report")
    check(report, "settings exposes the existing manual debug report")
    click(report)
    check(not panel:IsShown(), "opening the report dismisses settings instead of overlapping dialogs")
    for _, frame in ipairs(frames) do
        check(not frame.scripts.OnUpdate and not frame.scripts.OnKeyDown and not frame.scripts.OnKeyUp,
            "settings/minimap add no polling or keyboard interception")
    end
    check(bidAttempts == beforeBids, "all settings/drag tests leave real purchase submission untouched")
    print("Profit Master settings/minimap: " .. (checks - beforeChecks) .. " offline assertions passed (Lua 5.1).")
end
CheckSettingsUI()
]=]
assert(loadstring(source .. cases, "@Test-ProfitMasterSettings"))()
