local addonName, addon = ...
local diagnostics = {}
addon.Diagnostics = diagnostics

local saved, reportWindow, reportText, reportScroll
local LIMIT = 1000
local MEMORY_INTERVAL = 15
local memoryCurrent, memoryPrevious, memoryAttemptAt, memoryViewedAt, memoryStatus

local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end

local function PreciseTime()
    if type(GetTimePreciseSec) ~= "function" then return nil end
    local value = GetTimePreciseSec()
    if Number(value) then return value end
end

local function Public(value)
    if issecretvalue and issecretvalue(value) then return "<restricted>" end
    local kind = type(value)
    if kind == "string" then
        return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
            :gsub("[\r\n\t]", " "):sub(1, 240)
    elseif kind == "number" or kind == "boolean" or kind == "nil" then return tostring(value) end
    return "<" .. kind .. ">"
end

function diagnostics.Initialize(value)
    saved = nil
    if value == nil then value = { version = 1, enabled = false, entries = {}, next = 1, count = 0, sequence = 0 } end
    if type(value) ~= "table" or value.version ~= 1 or type(value.entries) ~= "table"
        or type(value.next) ~= "number" or value.next < 1 or value.next > LIMIT or value.next ~= math.floor(value.next)
        or type(value.count) ~= "number" or value.count < 0 or value.count > LIMIT or value.count ~= math.floor(value.count)
        or type(value.sequence) ~= "number" or value.sequence < 0 or value.sequence >= math.huge
        or value.sequence ~= math.floor(value.sequence) then return nil end
    saved = value
    diagnostics.Log("session", { version = C_AddOns.GetAddOnMetadata(addonName, "Version"),
        auctionator = C_AddOns.GetAddOnMetadata("Auctionator", "Version") })
    return saved
end

function diagnostics.Enabled()
    return saved and saved.enabled == true or false
end

function diagnostics.Log(event, fields)
    if not diagnostics.Enabled() then return end
    local parts = {}
    for key, value in pairs(fields or {}) do
        if not (issecretvalue and issecretvalue(key)) and type(key) == "string" then
            parts[#parts + 1] = Public(key) .. "=" .. Public(value)
        end
    end
    table.sort(parts)
    saved.sequence = saved.sequence + 1
    local line = string.format("%d t=%.3f #%d %s %s", time(), GetTime(), saved.sequence, Public(event), table.concat(parts, " "))
    saved.entries[saved.next] = line:sub(1, 1024)
    saved.next, saved.count = saved.next % LIMIT + 1, math.min(LIMIT, saved.count + 1)
end

function diagnostics.SetEnabled(enabled)
    if not saved then return end
    if enabled then
        saved.enabled = true
        diagnostics.Log("debug_enabled", { version = C_AddOns.GetAddOnMetadata(addonName, "Version") })
    else
        diagnostics.Log("debug_disabled")
        saved.enabled = false
    end
end

-- Native AddonList limits this expensive global refresh to once per 15 seconds.
-- Only an explicit report open requests a sample; Report itself never samples.
function diagnostics.CaptureMemory()
    local now = PreciseTime()
    memoryViewedAt = now
    if not now then memoryStatus = "Precise clock unavailable"; return false end
    if memoryAttemptAt and now < memoryAttemptAt then
        memoryStatus = "Precise clock moved backwards"
        return false
    end
    if memoryAttemptAt and now - memoryAttemptAt < MEMORY_INTERVAL then
        memoryStatus = "cached"
        return false
    end
    if type(UpdateAddOnMemoryUsage) ~= "function" or type(GetAddOnMemoryUsage) ~= "function" then
        memoryStatus = "Memory API unavailable"
        return false
    end
    memoryAttemptAt = now
    UpdateAddOnMemoryUsage()
    local finished = PreciseTime()
    local profitMaster = GetAddOnMemoryUsage("ProfitMaster")
    local auctionator = GetAddOnMemoryUsage("Auctionator")
    local updateMS = finished and finished >= now and (finished - now) * 1000 or nil
    memoryPrevious = memoryCurrent
    memoryCurrent = { at = finished and finished >= now and finished or now,
        profitMaster = Number(profitMaster) and profitMaster or nil,
        auctionator = Number(auctionator) and auctionator or nil,
        updateMS = Number(updateMS) and updateMS or nil }
    memoryViewedAt, memoryStatus = memoryCurrent.at, "fresh"
    diagnostics.Log("memory_sample", { profitmaster_kb = memoryCurrent.profitMaster,
        auctionator_kb = memoryCurrent.auctionator, update_ms = memoryCurrent.updateMS })
    return true
end

local function MemoryValue(value)
    if value == nil then return "Unknown" end
    return string.format("%.3f MiB (%.1f KB)", value / 1024, value)
end

local function MemorySample(label, sample)
    if not sample then return label .. ": not captured" end
    local age = memoryViewedAt and memoryViewedAt >= sample.at
        and string.format("%.1f s", memoryViewedAt - sample.at) or "Unknown"
    local cost = sample.updateMS and string.format("%.3f ms", sample.updateMS) or "Unknown"
    return string.format("%s: t=%.3f s; age %s; Profit Master %s; Auctionator %s; refresh %s",
        label, sample.at, age, MemoryValue(sample.profitMaster), MemoryValue(sample.auctionator), cost)
end

local function MemoryDelta(current, previous)
    if current == nil or previous == nil then return "Unknown" end
    local delta = current - previous
    return string.format("%+.3f MiB (%+.1f KB)", delta / 1024, delta)
end

local function MemoryReport(lines)
    lines[#lines + 1] = "Memory (manual snapshots; ages at latest capture request)"
    if memoryStatus == "cached" then
        local remaining = math.ceil(math.max(0, MEMORY_INTERVAL - (memoryViewedAt - memoryAttemptAt)) * 10) / 10
        lines[#lines + 1] = string.format("Cached sample; request again in %.1f s for a fresh sample (15 s limit).", remaining)
    elseif memoryStatus == "fresh" then
        lines[#lines + 1] = "Fresh sample."
    elseif memoryStatus then
        lines[#lines + 1] = "Memory capture unavailable: " .. memoryStatus .. "."
    else
        lines[#lines + 1] = "Not captured; open /pmaster log to request a sample."
    end
    lines[#lines + 1] = MemorySample("Current", memoryCurrent)
    lines[#lines + 1] = MemorySample("Previous", memoryPrevious)
    if memoryCurrent and memoryPrevious then
        lines[#lines + 1] = "Change since previous: Profit Master "
            .. MemoryDelta(memoryCurrent.profitMaster, memoryPrevious.profitMaster) .. "; Auctionator "
            .. MemoryDelta(memoryCurrent.auctionator, memoryPrevious.auctionator)
    end
    lines[#lines + 1] = "Addon Lua allocation attribution, not WoW process RAM or a peak. No explicit garbage collection is requested."
    lines[#lines + 1] = "Deltas include normal/report allocations and garbage collection. Capture before and after the scan, not during it."
    lines[#lines + 1] = ""
end

local PROFILE_LINES = {
    { "Result", "outcome", "source", "at", "rows", "minimum_profit" },
    { "Elapsed ms", "scan_ms", "active_ms", "pause_ms", "provider_ms", "post_input_ms" },
    { "Vendor counts", "vendor_missing_ids", "vendor_missing_refs", "vendor_requests",
        "vendor_ready", "vendor_failed", "vendor_unresolved", "vendor_queued" },
    { "Vendor wait ms", "vendor_pending_ms", "vendor_pending_after_input_ms",
        "vendor_ready_avg_ms", "vendor_ready_max_ms" },
    { "Instrumented CPU ms", "vendor_loading_cpu_ms", "vendor_retry_cpu_ms", "valuation_cpu_ms", "de_cpu_ms" },
    { "Other work ms", "history_ms", "batch_ms" },
}

local function ProfileReport(lines)
    lines[#lines + 1] = "Last scan profile"
    local profile = addon.LastScanProfile
    if (issecretvalue and issecretvalue(profile)) or type(profile) ~= "table" then
        lines[#lines + 1] = "No completed/cancelled scan profile yet."
    else
        for _, fields in ipairs(PROFILE_LINES) do
            local parts = {}
            for index = 2, #fields do
                local key, text = fields[index], "Unknown"
                local value = profile[key]
                if key == "outcome" or key == "source" then
                    if not (issecretvalue and issecretvalue(value)) and type(value) == "string" then text = Public(value) end
                elseif Number(value) then text = Public(value) end
                parts[#parts + 1] = key .. "=" .. text
            end
            lines[#lines + 1] = fields[1] .. ": " .. table.concat(parts, "; ")
        end
        lines[#lines + 1] = "minimum_profit is copper. Vendor pending time overlaps provider/processing time."
        lines[#lines + 1] = "Active, vendor pending and ready times exclude pauses; provider time includes pauses."
        lines[#lines + 1] = "post_input_ms includes all finalization. CPU timings cover instrumented slices, not native profiler CPU."
        lines[#lines + 1] = "Loader CPU includes readiness callbacks that can run during a purchase pause; unresolved counts requested IDs, queued counts unsent IDs."
    end
    lines[#lines + 1] = ""
end

function diagnostics.Report()
    local lines = { "Profit Master " .. Public(C_AddOns.GetAddOnMetadata(addonName, "Version")) .. " debug log",
        "Auctionator " .. Public(C_AddOns.GetAddOnMetadata("Auctionator", "Version")),
        "Debug: " .. (diagnostics.Enabled() and "enabled" or "disabled") .. "; retained events: " .. (saved and saved.count or 0) .. "/" .. LIMIT,
        "Prices are copper. t = client session seconds. Entries are oldest to newest.",
        "Enable debug before reproducing the problem. This report is a snapshot.", "" }
    local check = addon.LastPriceCheck
    if not (issecretvalue and issecretvalue(check)) and type(check) == "table" then
        local fields = {}
        for _, key in ipairs({ "item", "attempt", "state", "queue_ms", "reply_ms", "results_to_preview_ms", "total_ms" }) do
            fields[#fields + 1] = key .. "=" .. Public(check[key])
        end
        lines[#lines + 1] = "Latest price check: " .. table.concat(fields, "; ")
        lines[#lines + 1] = "Recorded transition times in ms. Reply ends at first matching results; results-to-preview includes processing/extra pages."
        lines[#lines + 1] = ""
    end
    ProfileReport(lines)
    MemoryReport(lines)
    if saved then
        for offset = 0, saved.count - 1 do
            local index = (saved.next - saved.count - 1 + offset) % LIMIT + 1
            local line = saved.entries[index]
            if type(line) == "string" and not (issecretvalue and issecretvalue(line)) then lines[#lines + 1] = line:sub(1, 1024) end
        end
    end
    return table.concat(lines, "\n")
end

function diagnostics.Show()
    if not reportWindow then
        reportWindow = CreateFrame("Frame", nil, UIParent, "InsetFrameTemplate")
        reportWindow:SetSize(680, 440)
        reportWindow:SetPoint("CENTER")
        reportWindow:SetFrameStrata("DIALOG")
        reportWindow:EnableMouse(true)
        local title = reportWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Profit Master - debug log")
        local instructions = reportWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        instructions:SetPoint("TOPLEFT", 16, -42)
        instructions:SetText("Text is selected: press Ctrl+C to copy. Mouse wheel scrolls. Escape closes.")
        local close = CreateFrame("Button", nil, reportWindow, "UIPanelButtonTemplate")
        close:SetSize(70, 24)
        close:SetPoint("TOPRIGHT", -16, -12)
        close:SetText("Close")
        close:SetScript("OnClick", function() reportWindow:Hide() end)
        reportScroll = CreateFrame("ScrollFrame", nil, reportWindow)
        reportScroll:SetPoint("TOPLEFT", 16, -64)
        reportScroll:SetPoint("BOTTOMRIGHT", -16, 16)
        reportScroll:EnableMouseWheel(true)
        local function Scroll(_, delta)
            reportScroll:SetVerticalScroll(math.max(0, math.min(reportScroll:GetVerticalScrollRange(),
                reportScroll:GetVerticalScroll() - delta * 42)))
        end
        reportScroll:SetScript("OnMouseWheel", Scroll)
        reportText = CreateFrame("EditBox", nil, reportScroll)
        reportText:SetPoint("TOPLEFT")
        reportText:SetWidth(640)
        reportText:SetMultiLine(true)
        reportText:SetAutoFocus(false)
        reportText:SetFontObject(ChatFontNormal)
        reportText:SetMaxLetters(0)
        reportText:EnableMouseWheel(true)
        reportText:SetScript("OnMouseWheel", Scroll)
        reportText:SetScript("OnEscapePressed", function() reportWindow:Hide() end)
        reportWindow:SetScript("OnHide", function() reportText:ClearFocus() end)
        reportScroll:SetScrollChild(reportText)
    end
    reportWindow:Show()
    -- Include the reusable report UI in both samples, so its first creation is
    -- not charged only to the post-scan side of a before/after comparison.
    diagnostics.CaptureMemory()
    reportText:SetText(diagnostics.Report())
    reportText:SetHeight(math.max(350, reportText:GetNumLines() * 16 + 16))
    reportText:SetCursorPosition(0)
    reportScroll:SetVerticalScroll(0)
    reportText:SetFocus()
    reportText:HighlightText()
end
