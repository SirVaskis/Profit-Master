local _, addon = ...
local owned = {}
addon.OwnedAuctions = owned

-- Chosen for this display: faction AH consignment rate in build 70938's
-- AuctionHouse DB2. The API does not expose the current auctioneer's rate.
local CUT_PERCENT = 5
local PREFIX = "Total (" .. CUT_PERCENT .. "% cut): "
local MAX_EXACT = 9007199254740991
local eventFrame, footer
local houseOpen, ready = false, false
local previousText

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Integer(value, minimum)
    return Public(value) and type(value) == "number" and value >= minimum
        and value <= MAX_EXACT and value == math.floor(value)
end

local function Forbidden(frame)
    return frame.IsForbidden and frame:IsForbidden()
end

local function SetText(text)
    if text ~= previousText then
        footer.text:SetText(text)
        previousText = text
    end
end

local function Total()
    local count = C_AuctionHouse.GetNumOwnedAuctions()
    if not Integer(count, 0) then return nil, nil, 0, "owned_count" end
    local active, incoming, bidOnly = 0, 0, 0
    local activeOK, incomingOK = true, true
    local problem, problemRow
    local function Missing(reason, index)
        if not problem then problem, problemRow = reason, index end
    end
    for i = 1, count do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        -- Each index is one canonical owned record. Cancellation IDs need not
        -- identify sold payout rows, and are not inputs to either money total.
        if not Public(info) or type(info) ~= "table" or not Public(info.status) then
            activeOK, incomingOK = false, false
            Missing("owned_row", i)
        elseif info.status == Enum.AuctionStatus.Active then
            local expired = Public(info.timeLeftSeconds) and type(info.timeLeftSeconds) == "number"
                and info.timeLeftSeconds <= 0
            if not expired then
                local price = info.buyoutAmount
                if not Public(price) then
                    activeOK = false
                    Missing("active_price", i)
                elseif price == nil or price == 0 then
                    bidOnly = bidOnly + 1
                elseif not Integer(price, 1) or not Integer(info.quantity, 0) then
                    activeOK = false
                    Missing("active_price_or_quantity", i)
                else
                    -- Owned prices are per unit, including commodity listings.
                    local gross = price * info.quantity
                    if not Integer(gross, 0) then
                        activeOK = false
                        Missing("active_amount", i)
                    else
                        -- Conservative whole-copper estimate per listing. Split
                        -- the calculation to avoid multiplying large totals by 95.
                        local net = math.floor(gross / 100) * (100 - CUT_PERCENT)
                            + math.floor((gross % 100) * (100 - CUT_PERCENT) / 100)
                        active = active + net
                        if not Integer(active, 0) then activeOK = false; Missing("active_sum", i) end
                    end
                end
            end
        elseif info.status == Enum.AuctionStatus.Sold then
            -- Sold rows already expose the native Incoming Amount for the
            -- whole sale. Do not multiply its quantity or deduct the cut again.
            local payout = Public(info.buyoutAmount) and (info.buyoutAmount or info.bidAmount)
            if not Integer(payout, 0) then
                incomingOK = false
                Missing("incoming_amount", i)
            else
                incoming = incoming + payout
                if not Integer(incoming, 0) then incomingOK = false; Missing("incoming_sum", i) end
            end
        else
            activeOK, incomingOK = false, false
            Missing("owned_status", i)
        end
    end
    local total = activeOK and incomingOK and active + incoming or nil
    if total and not Integer(total, 0) then total = nil; Missing("total_sum", 0) end
    return total, incomingOK and incoming or nil, bidOnly, problem, problemRow, count
end

local function Refresh()
    if not footer then return end
    local visible = footer:IsVisible()
    if not Public(visible) or not visible then return end
    local loading = PREFIX .. "Loading...   Incoming: Loading..."
    if not houseOpen or not ready then SetText(loading); return end
    local full = C_AuctionHouse.HasFullOwnedAuctionResults()
    if not Public(full) or full ~= true then SetText(loading); return end
    local total, incoming, bidOnly, problem, row, count = Total()
    local prefix = bidOnly > 0 and ("Total (" .. CUT_PERCENT .. "%, no bid-only): ") or PREFIX
    local text = prefix .. (total ~= nil and GetMoneyString(total) or "Unavailable")
        .. "   Incoming: " .. (incoming ~= nil and GetMoneyString(incoming) or "Unavailable")
    SetText(text)
    if addon.Diagnostics and addon.Diagnostics.Enabled() then
        addon.Diagnostics.Log("owned_totals", { total = total, incoming = incoming,
            rows = count, missing = problem, row = row, bid_only = bidOnly })
    end
end

local function Attach()
    if footer or not AuctionHouseFrame or Forbidden(AuctionHouseFrame) then return end
    local auctions = AuctionHouseFrame.AuctionsFrame
    if not auctions or Forbidden(auctions) then return end
    local button = auctions.CancelAuctionButton
    if not button or Forbidden(button) then return end
    -- This child follows Cancel's visibility on Auctions/Bids and addon tabs.
    -- It extends left of the button without changing its click rectangle.
    footer = CreateFrame("Frame", nil, button)
    footer:SetSize(430, 22)
    footer:SetPoint("RIGHT", button, "LEFT", -12, 0)
    footer:EnableMouse(false)
    footer.text = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer.text:SetAllPoints()
    footer.text:SetJustifyH("RIGHT")
    footer.text:SetWordWrap(false)
    footer:SetScript("OnShow", Refresh)
    Refresh()
end

local function Open()
    if not houseOpen then houseOpen, ready = true, false end
    Attach()
    Refresh()
end

function owned.Initialize()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, arg)
        if event == "AUCTION_HOUSE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
            and Public(arg) and arg == Enum.PlayerInteractionType.Auctioneer) then Open()
        elseif event == "AUCTION_HOUSE_CLOSED" then houseOpen, ready = false, false
        elseif event == "OWNED_AUCTIONS_UPDATED" and houseOpen then
            ready = true
            Attach()
            Refresh()
        elseif event == "ADDON_LOADED" and arg == "Blizzard_AuctionHouseUI" and houseOpen then Attach() end
    end)
    for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "OWNED_AUCTIONS_UPDATED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "ADDON_LOADED" }) do eventFrame:RegisterEvent(event) end
end
