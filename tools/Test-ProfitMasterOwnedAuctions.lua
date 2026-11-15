-- Offline owned-auction payout/display checks. No game input or auction queries.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local secret = setmetatable({}, { __tostring = function() error("restricted data was formatted") end })
issecretvalue = function(value) return value == secret end
Enum = { AuctionStatus = { Active = 0, Sold = 1 }, PlayerInteractionType = { Auctioneer = 21 } }
local objects, created, moneyCalls, moneyValues = {}, {}, 0, {}
local function lastTotal() return moneyValues[#moneyValues - 1] end
local function lastIncoming() return moneyValues[#moneyValues] end
local function Native(parent)
    local frame = { parent = parent, shown = true, children = {}, scripts = {}, events = {}, regions = {} }
    if parent then parent.children[#parent.children + 1] = frame end
    objects[#objects + 1] = frame
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:SetShown(value)
        local before = {}
        for _, object in ipairs(objects) do before[object] = object:IsVisible() end
        self.shown = value
        for _, object in ipairs(objects) do
            if not before[object] and object:IsVisible() and object.scripts.OnShow then object.scripts.OnShow(object) end
        end
    end
    function frame:Show() self:SetShown(true) end
    function frame:Hide() self:SetShown(false) end
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:SetScript(name, callback)
        check(name == "OnEvent" or name == "OnShow", "module installs only owned event/visibility scripts")
        self.scripts[name] = callback
    end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:EnableMouse(enabled) self.mouse = enabled end
    function frame:CreateFontString()
        local region = { writes = 0 }
        function region:SetText(value) self.text, self.writes = value, self.writes + 1 end
        function region:SetAllPoints() self.allPoints = true end
        function region:SetJustifyH(value) self.justify = value end
        function region:SetWordWrap(value) self.wrap = value end
        self.regions[#self.regions + 1] = region
        return region
    end
    return frame
end
CreateFrame = function(kind, name, parent)
    check(kind == "Frame" and name == nil, "module creates only unnamed private frames")
    local frame = Native(parent)
    created[#created + 1] = frame
    return frame
end
local function ForbiddenOperation() error("display must not query, poll, hook or change game input") end
C_Timer = { NewTimer = ForbiddenOperation, NewTicker = ForbiddenOperation, After = ForbiddenOperation }
hooksecurefunc, SetBinding, UseContainerItem = ForbiddenOperation, ForbiddenOperation, ForbiddenOperation
GetMoneyString = function(value)
    check(type(value) == "number" and value >= 0 and value == math.floor(value), "only verified whole copper reaches the money formatter")
    moneyCalls = moneyCalls + 1
    moneyValues[#moneyValues + 1] = value
    return "money:" .. tostring(value)
end
local rows, full, reads, fullReads, numberOverride = {}, true, 0, 0, nil
C_AuctionHouse = {
    GetNumOwnedAuctions = function() return numberOverride or #rows end,
    GetOwnedAuctionInfo = function(index) reads = reads + 1; return rows[index] end,
    HasFullOwnedAuctionResults = function() fullReads = fullReads + 1; return full end,
    QueryOwnedAuctions = ForbiddenOperation,
    SendBrowseQuery = ForbiddenOperation, SendSearchQuery = ForbiddenOperation, PlaceBid = ForbiddenOperation,
}
local logs, debugEnabled = {}, false
local addon = { Diagnostics = {
    Enabled = function() return debugEnabled end,
    Log = function(name, fields) logs[#logs + 1] = { name = name, fields = fields } end,
} }
assert(loadfile("addons/ProfitMaster/OwnedAuctions.lua"))("ProfitMaster", addon)
addon.OwnedAuctions.Initialize()
local eventFrame = created[1]
local function event(name, arg)
    if eventFrame.events[name] then eventFrame.scripts.OnEvent(eventFrame, name, arg) end
end
check(#created == 1 and reads == 0, "initialization registers events without accessing auction data or creating a footer early")
addon.OwnedAuctions.Initialize()
check(#created == 1, "repeated initialization reuses the original event frame")
event("AUCTION_HOUSE_SHOW")
check(#created == 1, "missing native Auctions UI leaves attachment pending")
AuctionHouseFrame = Native()
AuctionHouseFrame.AuctionsFrame = Native(AuctionHouseFrame)
local auctions = AuctionHouseFrame.AuctionsFrame
auctions.CancelAuctionButton = Native(auctions)
local cancel = auctions.CancelAuctionButton
local originalClick, originalHitRectangle = function() end, { 0, 0, 0, 0 }
cancel.scripts.OnClick, cancel.hitRectangle = originalClick, originalHitRectangle
cancel.forbidden = true
event("ADDON_LOADED", "Blizzard_AuctionHouseUI")
check(#created == 1, "a forbidden native Cancel button is never used as an attachment surface")
cancel.forbidden = false
event("ADDON_LOADED", "Blizzard_AuctionHouseUI")
local footer = created[2]
check(#created == 2 and footer.parent == cancel and footer.width == 430 and footer.height == 22 and footer.mouse == false,
    "one mouse-transparent footer is attached beneath Cancel's native visibility hierarchy")
check(footer.point[1] == "RIGHT" and footer.point[2] == cancel and footer.point[3] == "LEFT" and footer.point[4] == -12,
    "footer extends left of Cancel without moving the native control")
check(footer.text.text == "Total (5% cut): Loading...   Incoming: Loading..." and reads == 0,
    "opening waits for fresh owned-auction data instead of presenting stale cache as a total")
check(cancel.scripts.OnClick == originalClick and cancel.hitRectangle == originalHitRectangle,
    "normal cancellation input and native hit rectangle remain untouched")

local function auction(id, price, quantity, status, seconds)
    return { auctionID = id, status = status or Enum.AuctionStatus.Active, buyoutAmount = price,
        quantity = quantity or 1, timeLeftSeconds = seconds }
end
rows = {
    auction(1, 200, 3), auction(2, 11, 2), auction(3, 21, 1),
    auction(4, 999999, 1000, Enum.AuctionStatus.Sold), auction(5, 10000, 2, nil, 0),
    auction(6, 0, 1), auction(7, nil, 1),
}
-- The native list may filter visually; the module must use the complete API store.
auctions.filteredRows = { rows[1] }
auctions.GetDataProvider = ForbiddenOperation
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 1000608 and lastIncoming() == 999999
    and footer.text.text == "Total (5%, no bid-only): money:1000608   Incoming: money:999999",
    "total combines active after-fee estimates and verbatim sold money, while incoming includes sold only without quantity multiplication or a second fee")
local previousWrites = footer.text.writes
event("AUCTION_HOUSE_SHOW")
event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Auctioneer)
check(lastTotal() == 1000608 and lastIncoming() == 999999 and footer.text.writes == previousWrites,
    "duplicate auctioneer-open events after owned results preserve readiness and the calculated total")
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.writes == previousWrites, "identical native updates do not rewrite the footer label")
addon.OwnedAuctions.Initialize()
check(#created == 2 and #footer.regions == 1, "repeat initialization creates no additional footer or font region")

full = false
local beforeRead = reads
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text:find("Loading...", 1, true) and reads == beforeRead,
    "partial coverage is visibly loading and cannot become an authoritative subtotal")
full = secret
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text:find("Loading...", 1, true), "restricted coverage is not interpreted as full or as zero")
full, rows = true, {}
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 0 and lastIncoming() == 0 and footer.text.text == "Total (5% cut): money:0   Incoming: money:0",
    "a verified complete empty owned store displays real zeros for both figures")
rows = { auction(8, 125, secret, Enum.AuctionStatus.Sold, 0), auction(9, secret, secret, nil, -1) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 125 and lastIncoming() == 125,
    "sold rows use their reported money without inspecting quantity or expiry, while known expired active rows are excluded")
local soldBid = auction(14, nil, secret, Enum.AuctionStatus.Sold, secret)
soldBid.bidAmount = 75
rows = { auction(15, 100, 2), auction(16, 50, 1000, Enum.AuctionStatus.Sold), soldBid }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 315 and lastIncoming() == 125,
    "sold auctions fall back to reported bid money when buyout money is absent and ignore quantity/time")
rows = { rows[1], soldBid }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 265 and lastIncoming() == 75,
    "native removal of a paid sold row reduces both total and incoming without retained historical money")
local soldZero = auction(17, 0, 1000, Enum.AuctionStatus.Sold)
soldZero.bidAmount = 999
rows = { auction(18, 100, 2), soldZero }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 190 and lastIncoming() == 0,
    "known zero sold money remains zero and is not replaced by a bid fallback or multiplied")

-- A native owned-store index is a financial record; cancellation IDs are not
-- financial inputs and need not be positive, present, public, or unique.
local sharedBid = auction(0, nil, secret, Enum.AuctionStatus.Sold)
sharedBid.bidAmount = 75
rows = { auction(0, 100, 2), auction(0, 50, 9999, Enum.AuctionStatus.Sold), sharedBid }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 315 and lastIncoming() == 125,
    "zero and shared sold IDs do not reject otherwise complete canonical financial records")
rows = { auction(nil, 100, 1), auction(secret, 20, secret, Enum.AuctionStatus.Sold),
    auction(0, 30, secret, Enum.AuctionStatus.Sold), auction(secret, 100, 2) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 335 and lastIncoming() == 50,
    "missing or restricted unused IDs are never inspected or required to sum public prices")
rows = { auction(123, 100, 1), auction(123, 75, secret, Enum.AuctionStatus.Sold), auction(123, 200, 1) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 360 and lastIncoming() == 75,
    "reused active and sold IDs do not deduplicate distinct canonical owned-store entries")
rows = { auction(0, 100, 0) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 0 and lastIncoming() == 0,
    "a valid zero-quantity active row contributes zero rather than invalidating complete totals")
rows = { auction(0, 0, secret), { status = Enum.AuctionStatus.Active, buyoutAmount = nil } }
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text == "Total (5%, no bid-only): money:0   Incoming: money:0",
    "known bid-only rows are excluded before irrelevant missing or restricted quantities are inspected")

rows = { auction(0, secret, 1), auction(0, 125, secret, Enum.AuctionStatus.Sold) }
local beforePartialFormat = moneyCalls
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text == "Total (5% cut): Unavailable   Incoming: money:125" and moneyCalls == beforePartialFormat + 1
    and lastIncoming() == 125, "unknown active proceeds preserve independently verified incoming and format only the known value")
local beforeDebugWrites, beforeLogs = footer.text.writes, #logs
debugEnabled = true
event("OWNED_AUCTIONS_UPDATED")
local failureLog = logs[#logs]
check(#logs == beforeLogs + 1 and failureLog.name == "owned_totals" and failureLog.fields.missing == "active_price"
    and failureLog.fields.row == 1 and failureLog.fields.rows == 2 and failureLog.fields.total == nil
    and failureLog.fields.incoming == 125 and footer.text.writes == beforeDebugWrites,
    "enabling diagnostics after an unchanged unavailable display records its reason without rewriting the UI")
debugEnabled = false
event("OWNED_AUCTIONS_UPDATED")
check(#logs == beforeLogs + 1, "disabled diagnostics skip owned-total records on ordinary native refreshes")

local invalidSets = {
    { rows = { auction(10, secret, 1) }, incoming = 0 }, { rows = { auction(10, 100, secret) }, incoming = 0 },
    { rows = { auction(10, -1, 1) }, incoming = 0 }, { rows = { auction(10, 1.5, 1) }, incoming = 0 },
    { rows = { auction(10, 100, 1.5) }, incoming = 0 }, { rows = { auction(10, math.huge, 1) }, incoming = 0 },
    { rows = { auction(10, 100, 1, secret) } }, { rows = { auction(10, 100, 1, 99) } }, { rows = { secret } },
    { rows = { { auctionID = 10, quantity = 1, buyoutAmount = 100 } } },
    { rows = { auction(10, 9007199254740991, 2) }, incoming = 0 },
    { rows = { auction(10, 9007199254740991, 1), auction(11, 9007199254740991, 1) }, incoming = 0 },
    { rows = { auction(10, secret, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, -1, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, 1.5, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, nil, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, math.huge, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, 9007199254740991, 1, Enum.AuctionStatus.Sold), auction(11, 1, 1, Enum.AuctionStatus.Sold) } },
    { rows = { auction(10, 9007199254740991, 1, Enum.AuctionStatus.Sold), auction(11, 100, 1) }, incoming = 9007199254740991 },
}
for _, invalid in ipairs(invalidSets) do
    rows = invalid.rows
    local beforeFormat = moneyCalls
    event("OWNED_AUCTIONS_UPDATED")
    local expected = invalid.incoming ~= nil and ("money:" .. tostring(invalid.incoming)) or "Unavailable"
    check(footer.text.text == "Total (5% cut): Unavailable   Incoming: " .. expected
        and moneyCalls == beforeFormat + (invalid.incoming ~= nil and 1 or 0),
        "invalid financial data only invalidates dependent figures and only independently known money is formatted")
end
rows, numberOverride = {}, 1
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text:find("Unavailable", 1, true), "a missing row within the declared native count is explicitly unavailable")
numberOverride = secret
event("OWNED_AUCTIONS_UPDATED")
check(footer.text.text:find("Unavailable", 1, true), "restricted native counts are not compared or used as loop bounds")
numberOverride, rows = nil, { auction(11, 9007199254740991, 1) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 8556839292003941 and lastIncoming() == 0,
    "large exact active copper values use split fee arithmetic while sold-only incoming remains zero")

cancel:Hide() -- Native Bids mode hides Cancel; the child follows automatically.
beforeRead, previousWrites = reads, footer.text.writes
rows = { auction(12, 100, 1) }
event("OWNED_AUCTIONS_UPDATED")
check(not footer:IsVisible() and reads == beforeRead and footer.text.writes == previousWrites,
    "Bids/hidden Cancel modes perform no owned-row scan or hidden footer write")
check(footer:IsShown(), "hiding a parent leaves the footer's local shown flag true, so IsShown alone cannot gate hidden work")
cancel:Show()
check(footer:IsVisible() and lastTotal() == 95 and lastIncoming() == 0, "returning to Auctions refreshes both inherited figures on show")
auctions:Hide() -- Other AH addon tabs hide native Auctions content.
beforeRead = reads
event("OWNED_AUCTIONS_UPDATED")
check(not footer:IsVisible() and footer:IsShown() and reads == beforeRead,
    "other AH tabs leave the footer locally shown but visually hidden, with no data refresh work")
auctions:Show()
check(footer:IsVisible() and lastTotal() == 95 and lastIncoming() == 0, "native Auctions restoration updates the existing footer")
event("AUCTION_HOUSE_CLOSED")
AuctionHouseFrame:Hide()
beforeRead = reads
event("OWNED_AUCTIONS_UPDATED")
check(not footer:IsVisible() and footer:IsShown() and reads == beforeRead,
    "closed Auction House data events cannot refresh a locally shown but visually hidden footer")
AuctionHouseFrame:Show()
event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", secret)
check(footer.text.text:find("Loading...", 1, true), "restricted interaction type does not open a new owned-data session")
event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Auctioneer)
check(footer.text.text:find("Loading...", 1, true), "a new auctioneer session waits for fresh results")
rows = { auction(13, 300, 2) }
event("OWNED_AUCTIONS_UPDATED")
check(lastTotal() == 570 and lastIncoming() == 0 and #created == 2, "reopening uses new native results while reusing the original two frames")
event("AUCTION_HOUSE_SHOW")
check(lastTotal() == 570 and lastIncoming() == 0 and footer.text.text == "Total (5% cut): money:570   Incoming: money:0",
    "a later duplicate open cannot reset a ready reopened session")
check(cancel.scripts.OnClick == originalClick and cancel.hitRectangle == originalHitRectangle,
    "all refreshes preserve native cancellation behavior and input geometry")
local isVisible = footer.IsVisible
footer.IsVisible = function() return secret end
beforeRead = reads
event("OWNED_AUCTIONS_UPDATED")
check(reads == beforeRead, "restricted visibility is skipped before branching on the frame's visible state")
footer.IsVisible = isVisible
print("Profit Master owned auctions: " .. checks .. " offline assertions passed (Lua 5.1).")
