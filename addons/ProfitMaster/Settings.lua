local _, addon = ...
local settings = {}
addon.Settings = settings

local panel, minimapButton, saved, dragging
local offsetX, offsetY = -8, -24

local function Coordinate(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value >= -10000 and value <= 10000
end

local function Label(parent, x, y, width, text, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Check(parent, y, text, callback)
    local control = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    control:SetSize(24, 24)
    control:SetPoint("TOPLEFT", 24, y)
    Label(parent, 52, y - 8, 390, text, "GameFontNormal")
    control:SetScript("OnClick", function(self) callback(self:GetChecked() == true) end)
    return control
end

function settings.Refresh(canDisenchant, canSafe, canMinimum, message)
    if not panel or not panel:IsShown() then return end
    panel.debug:SetChecked(addon.Diagnostics.Enabled())
    panel.disenchant:SetChecked(addon.Disenchant.Enabled())
    panel.safeDisenchant:SetChecked(addon.Disenchant.Safe())
    panel.disenchant:SetEnabled(canDisenchant)
    panel.safeDisenchant:SetEnabled(canSafe)
    panel.minimumProfit:SetEnabled(canMinimum)
    panel.prepareListings:SetChecked(addon.Listings.Enabled())
    panel.oneClickPrepared:SetChecked(addon.Listings.OneClick())
    panel.prepareListings:SetEnabled(canMinimum)
    panel.oneClickPrepared:SetEnabled(canMinimum)
    if not panel.minimumProfit:HasFocus() then
        local text = tostring(addon.GetMinimumProfit())
        if panel.minimumProfit:GetText() ~= text then panel.minimumProfit:SetText(text) end
    end
    local status = (not canMinimum and "Finish or cancel the current purchase / price check to change profit settings."
        or not canSafe and "During scans you can change Min profit or turn DE off. Other DE changes wait until idle."
        or message)
    if panel.status:GetText() ~= status then panel.status:SetText(status) end
end

function settings.Toggle()
    if panel and panel:IsShown() then panel:Hide(); return end
    if not panel then
        panel = CreateFrame("Frame", nil, UIParent, "InsetFrameTemplate")
        panel:SetSize(480, 550)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        Label(panel, 24, -18, 430, "Profit Master - settings", "GameFontNormalLarge")
        panel.debug = Check(panel, -48, "Enable debug logging", addon.ChangeDebug)
        Label(panel, 52, -78, 400, "Keep diagnostic events for the manually opened debug report.")
        panel.disenchant = Check(panel, -108, "Disenchant profits", addon.ChangeDisenchant)
        Label(panel, 52, -138, 400, "Include disenchant deals and vendor / DE advice in your bags, anywhere.")
        panel.safeDisenchant = Check(panel, -168, "Safe disenchant", addon.ChangeSafeDisenchant)
        Label(panel, 52, -198, 400, "Use the cheapest baseline outcome after 15%. Drops and sale prices remain unverified.")
        panel.prepareListings = Check(panel, -228, "Prepare item listings", addon.ChangePrepareListings)
        Label(panel, 52, -258, 400, "Check up to 20 affordable rows while this tab is idle; buys take priority.")
        panel.oneClickPrepared = Check(panel, -288, "Buy prepared items with one click", addon.ChangeOneClickPrepared)
        Label(panel, 52, -318, 400, "Buy 1 spends gold on that click. Turn off to always open confirmation.")
        Label(panel, 24, -373, 185, "Minimum profit per item:", "GameFontNormal")
        panel.minimumProfit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        local field = panel.minimumProfit
        field:SetSize(92, 22)
        field:SetPoint("TOPLEFT", 218, -366)
        field:SetAutoFocus(false)
        field:SetNumeric(true)
        field:SetMaxLetters(9)
        Label(panel, 320, -373, 120, "copper")
        Label(panel, 24, -401, 428, "Enter or click away to apply. Escape restores the saved amount.")
        local function ResetMinimum(self) self:SetText(tostring(addon.GetMinimumProfit())) end
        local function CommitMinimum(self)
            addon.ChangeMinimumProfit(tonumber(self:GetText()))
            ResetMinimum(self)
        end
        field:SetScript("OnEnterPressed", function(self) CommitMinimum(self); self:ClearFocus() end)
        field:SetScript("OnEditFocusLost", function(self) CommitMinimum(self); self:HighlightText(0, 0) end)
        field:SetScript("OnEscapePressed", function(self) ResetMinimum(self); self:ClearFocus() end)
        panel.status = Label(panel, 24, -430, 428, "")
        panel.status:SetHeight(62)
        local log = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        log:SetSize(110, 24)
        log:SetPoint("BOTTOMLEFT", 24, 18)
        log:SetText("Debug report")
        log:SetScript("OnClick", function() panel:Hide(); addon.Diagnostics.Show() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetSize(80, 24)
        close:SetPoint("BOTTOMRIGHT", -24, 18)
        close:SetText("Close")
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnHide", function() field:ClearFocus() end)
        panel:SetScript("OnShow", function() addon.RefreshSettings() end)
    end
    panel:Show()
    addon.RefreshSettings()
end

local function AnchorButton()
    minimapButton:ClearAllPoints()
    -- A free offset, not a circular orbit: works with round and square minimaps.
    minimapButton:SetPoint("CENTER", Minimap, "TOPLEFT", offsetX, offsetY)
    minimapButton:SetUserPlaced(false)
end

local function FinishDrag()
    if not dragging then return end
    dragging = false
    minimapButton:StopMovingOrSizing()
    if not Minimap:IsForbidden() then
        local x, y = minimapButton:GetCenter()
        local left, top = Minimap:GetLeft(), Minimap:GetTop()
        local buttonScale, mapScale = minimapButton:GetEffectiveScale(), Minimap:GetEffectiveScale()
        if Coordinate(x) and Coordinate(y) and Coordinate(left) and Coordinate(top)
            and Coordinate(buttonScale) and buttonScale > 0 and Coordinate(mapScale) and mapScale > 0 then
            local dx, dy = x * buttonScale / mapScale - left, y * buttonScale / mapScale - top
            if Coordinate(dx) and Coordinate(dy) then
                offsetX, offsetY = dx, dy
                if saved then saved.minimap = { x = dx, y = dy } end
            end
        end
    end
    AnchorButton()
end

function settings.Initialize(database)
    saved = database
    local position = saved and saved.minimap
    if type(position) == "table" and Coordinate(position.x) and Coordinate(position.y) then
        offsetX, offsetY = position.x, position.y
    end
    if minimapButton then AnchorButton() end
end

function settings.CreateMinimapButton()
    if minimapButton or not Minimap or Minimap:IsForbidden() then return end
    minimapButton = CreateFrame("Button", nil, Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetMovable(true)
    minimapButton:SetClampedToScreen(true)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetAtlas("bags-junkcoin")
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:SetScript("OnClick", function() if not dragging then settings.Toggle() end end)
    minimapButton:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        dragging = true
        GameTooltip:Hide()
        self:StartMoving()
    end)
    minimapButton:SetScript("OnDragStop", FinishDrag)
    minimapButton:SetScript("OnHide", FinishDrag)
    minimapButton:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Profit Master")
        GameTooltip:AddLine("Click for settings. Drag to reposition on round or square minimaps.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AnchorButton()
end
