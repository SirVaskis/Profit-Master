-- Offline log retention/privacy checks; no WoW process or file writes.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local addon = {}
local clock = 10
time = function() return 1800000000 end
GetTime = function() return clock end
C_AddOns = { GetAddOnMetadata = function(name) return name == "ProfitMaster" and "0.1.17" or "346" end }
local restricted = setmetatable({}, { __tostring = function() error("restricted value was read") end })
issecretvalue = function(value) return value == restricted end
assert(loadfile("addons/ProfitMaster/Diagnostics.lua"))("ProfitMaster", addon)
local log = addon.Diagnostics
local saved = log.Initialize(nil)
check(saved and not log.Enabled() and saved.count == 0, "debug defaults off without recording events")
log.Log("disabled", { value = restricted })
check(saved.sequence == 0, "disabled logging does not format or store payloads")
log.SetEnabled(true)
check(log.Enabled() and saved.count == 1, "explicit enable starts logging")
clock = 10.125
log.Log("quote_received", { expected_unit = 50, received_unit = 51, expected_total = 250,
    received_total = 255, quantity = 5, hidden = restricted, object = {} })
local report = log.Report()
check(report:find("t=10.125", 1, true) and report:find("expected_total=250", 1, true)
    and report:find("received_total=255", 1, true), "reports preserve prices, quantities, ordering and session timing")
check(report:find("hidden=<restricted>", 1, true) and report:find("object=<table>", 1, true),
    "restricted/object values are never read through tostring or serialized")
log.Log("format", { text = "|cffffffff|Hitem:1|h[Example]|h|r\nnext\tline" })
check(log.Report():find("text=[Example] next line", 1, true), "reports strip links, colors and embedded line breaks")
log.SetEnabled(false)
local stoppedAt, kept = saved.sequence, saved.count
log.Log("ignored", { text = "should not appear" })
check(saved.sequence == stoppedAt and saved.count == kept, "turning debug off retains old events and stops new ones")
check(log.Initialize(saved) == saved and not log.Enabled() and saved.count == kept,
    "disabled preference and collected events survive reload initialization")
log.SetEnabled(true)
for i = 1, 1500 do log.Log("ring", { n = i }) end
report = log.Report()
check(saved.count == 1000 and report:find(" ring n=501\n", 1, true)
    and report:sub(-11) == "ring n=1500", "the newest thousand events survive overflow in chronological order")
check(not report:find(" ring n=500\n", 1, true), "overflow discards old events instead of growing without limit")
local sequence = saved.sequence
check(log.Initialize(saved) == saved and log.Enabled() and saved.sequence == sequence + 1 and saved.count == 1000,
    "enabled logs survive reload and include a new session marker")
log.Log("long", { text = string.rep("x", 10000) })
check(#saved.entries[(saved.next - 2) % 1000 + 1] <= 1024, "each retained record is bounded")
local unknown = { version = 99, marker = "keep" }
check(log.Initialize(unknown) == nil and unknown.marker == "keep" and not log.Enabled(),
    "unknown saved-log formats are preserved without an automatic reset")

-- Manual memory snapshots use only the native addon counters, never a scan,
-- forced collection, background timer or process-memory approximation.
local secretNumber = 65535
issecretvalue = function(value) return value == restricted or value == secretNumber end
collectgarbage = function() error("diagnostics must not request garbage collection") end
CopyToClipboard = function() error("copying remains a manual Ctrl+C action") end
local forbidden = setmetatable({}, { __index = function() error("diagnostics must not query or schedule work") end })
C_AuctionHouse, C_Item, C_Timer = forbidden, forbidden, forbidden
local function NewMemoryLog()
    local state = { clock = 100, delay = 0.25, updates = 0, reads = 0, clocks = 0,
        values = { ProfitMaster = 2048, Auctionator = 1024 } }
    GetTime = function() return state.clock end
    GetTimePreciseSec = function() state.clocks = state.clocks + 1; return state.clock end
    UpdateAddOnMemoryUsage = function()
        state.updates = state.updates + 1
        state.clock = state.clock + state.delay
    end
    GetAddOnMemoryUsage = function(name)
        check(name == "ProfitMaster" or name == "Auctionator", "memory reads use only the two requested addon names")
        state.reads = state.reads + 1
        return state.values[name]
    end
    local container = {}
    assert(loadfile("addons/ProfitMaster/Diagnostics.lua"))("ProfitMaster", container)
    local diagnostics = container.Diagnostics
    local database = diagnostics.Initialize(nil)
    return diagnostics, state, database, container
end

local memory, state, database, container = NewMemoryLog()
check(memory.Report():find("Not captured; open /pmaster log", 1, true)
    and state.updates == 0 and state.reads == 0 and state.clocks == 0,
    "formatting an unsampled report never probes the clock or memory API")
check(memory.CaptureMemory() == true and state.updates == 1 and state.reads == 2,
    "an explicit capture refreshes once and reads each addon once")
report = memory.Report()
check(report:find("Current: t=100.250 s; age 0.0 s; Profit Master 2.000 MiB (2048.0 KB); Auctionator 1.000 MiB (1024.0 KB); refresh 250.000 ms", 1, true),
    "memory report uses precise sample time, measured update cost and KB/1024 MiB units")
check(report:find("Previous: not captured", 1, true) and report:find("not WoW process RAM or a peak", 1, true)
    and report:find("No explicit garbage collection is requested", 1, true), "first snapshot states its scope without inventing a previous sample or peak")
check(database.count == 0 and database.sequence == 0, "manual sampling works with debug disabled without adding log events")
local clockReads = state.clocks
state.clock = 104
check(memory.Report() == report and state.clocks == clockReads and state.updates == 1 and state.reads == 2,
    "report formatting is pure and preserves the age at the latest explicit capture request")
state.clock = 105
check(memory.CaptureMemory() == false and state.updates == 1 and state.reads == 2,
    "a repeat request inside 15 seconds reuses the shared module sample")
report = memory.Report()
check(report:find("Cached sample; request again in 10.0 s", 1, true) and report:find("age 4.8 s", 1, true),
    "cached reports show both sample age and remaining refresh wait")
state.clock = 114.999
check(not memory.CaptureMemory() and state.updates == 1
    and memory.Report():find("request again in 0.1 s", 1, true), "the rate limit remains in force just before the boundary")
state.clock = 115
state.values.ProfitMaster, state.values.Auctionator = 3072, 512
memory.SetEnabled(true)
check(memory.CaptureMemory() and state.updates == 2, "a fresh capture is allowed exactly 15 seconds after the previous refresh began")
report = memory.Report()
check(report:find("Previous: t=100.250 s; age 15.0 s", 1, true)
    and report:find("Profit Master +1.000 MiB (+1024.0 KB); Auctionator -0.500 MiB (-512.0 KB)", 1, true),
    "a second capture reports signed changes against the previous fresh sample")
check(database.count == 2 and report:find("memory_sample auctionator_kb=512 profitmaster_kb=3072 update_ms=250", 1, true),
    "enabled debugging adds one compact memory event to the existing bounded ring")
state.clock = 130
state.values.ProfitMaster, state.values.Auctionator = 1024, 0
check(memory.CaptureMemory() and state.updates == 3, "later manual requests can take another fresh sample")
report = memory.Report()
check(report:find("Current: t=130.250 s", 1, true) and report:find("Previous: t=115.250 s", 1, true)
    and not report:find("t=100.250 s", 1, true), "only the last two fresh runtime snapshots remain in the memory section")
local savedKeys = 0
for _ in pairs(database) do savedKeys = savedKeys + 1 end
check(savedKeys == 6 and database.memoryCurrent == nil and database.memoryPrevious == nil,
    "memory snapshots do not add growing data or snapshot tables to SavedVariables")
state.clock = 120
check(not memory.CaptureMemory() and state.updates == 3 and memory.Report():find("clock moved backwards", 1, true),
    "a backwards precise clock cannot bypass the global refresh rate limit")

for _, value in ipairs({ {}, { value = restricted }, { value = secretNumber }, { value = 0 / 0 },
    { value = -1 }, { value = math.huge }, { value = "2048" } }) do
    local badMemory, badState = NewMemoryLog()
    badState.values.ProfitMaster = value.value
    check(badMemory.CaptureMemory(), "a valid native refresh remains a fresh sample when one addon value is unavailable")
    local badReport = badMemory.Report()
    check(badReport:find("Profit Master Unknown; Auctionator 1.000 MiB", 1, true),
        "missing, restricted, NaN, negative, infinite and nonnumeric memory values remain unknown independently")
end
for _, value in ipairs({ {}, { value = restricted }, { value = secretNumber }, { value = 0 / 0 },
    { value = -1 }, { value = math.huge } }) do
    local badMemory, badState = NewMemoryLog()
    badState.clock = value.value
    check(not badMemory.CaptureMemory() and badState.updates == 0 and badState.reads == 0
        and badMemory.Report():find("Precise clock unavailable", 1, true),
        "invalid precise clocks skip native refreshes without reading restricted values")
end
local absent, absentState = NewMemoryLog()
GetTimePreciseSec = nil
check(not absent.CaptureMemory() and absentState.updates == 0 and absentState.reads == 0,
    "an unavailable precise clock skips memory measurement gracefully")
absent, absentState = NewMemoryLog()
UpdateAddOnMemoryUsage = nil
check(not absent.CaptureMemory() and absentState.reads == 0 and absent.Report():find("Memory API unavailable", 1, true),
    "a missing native refresh function is reported without querying stale counters")
absent, absentState = NewMemoryLog()
GetAddOnMemoryUsage = nil
check(not absent.CaptureMemory() and absentState.updates == 0 and absent.Report():find("Memory API unavailable", 1, true),
    "a missing native read function avoids an expensive unusable refresh")
absent, absentState = NewMemoryLog()
local preciseReads = 0
GetTimePreciseSec = function() preciseReads = preciseReads + 1; return preciseReads == 1 and 100 or restricted end
check(absent.CaptureMemory() and absent.Report():find("Current: t=100.000 s", 1, true)
    and absent.Report():find("refresh Unknown", 1, true), "a restricted end time preserves the valid start timestamp without fabricating update cost")

-- The copyable panel requests one capture before it formats the report. It
-- remains reusable and releases/captures focus through the existing scripts.
local shown, shownState = NewMemoryLog()
local nodes, editor, instructions, firstCreatedBeforeRefresh = {}, nil, nil, false
local methods = {}
local function Node(kind)
    local node = setmetatable({ kind = kind, scripts = {} }, { __index = methods })
    nodes[#nodes + 1] = node
    return node
end
for _, name in ipairs({ "SetSize", "SetPoint", "SetFrameStrata", "EnableMouse", "EnableMouseWheel",
    "SetWidth", "SetMultiLine", "SetAutoFocus", "SetFontObject", "SetMaxLetters", "SetScrollChild",
    "SetHeight", "SetCursorPosition", "SetVerticalScroll" }) do methods[name] = function() end end
function methods:CreateFontString() return Node("FontString") end
function methods:SetText(text)
    self.text = text
    if self.kind == "FontString" and text:find("Ctrl+C", 1, true) then instructions = self end
end
function methods:SetScript(event, callback)
    check(event ~= "OnUpdate", "memory diagnostics never installs per-frame work")
    self.scripts[event] = callback
end
function methods:GetNumLines() return 1 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return 0 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide() end end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HighlightText() self.selected = true end
UIParent, ChatFontNormal = {}, {}
CreateFrame = function(kind)
    if #nodes == 0 then firstCreatedBeforeRefresh = shownState.updates == 0 end
    local node = Node(kind)
    if kind == "EditBox" then editor = node end
    return node
end
shown.Show()
check(firstCreatedBeforeRefresh and shownState.updates == 1 and shownState.reads == 2
    and editor.text:find("Current: t=100.250 s", 1, true), "Show builds its reusable UI before sampling, then formats the captured report")
check(editor.focused and editor.selected and instructions.text:find("Ctrl+C", 1, true),
    "the report stays selected for manual Ctrl+C without a clipboard API")
local nodeCount = #nodes
shownState.clock = 105
shown.Show()
check(shownState.updates == 1 and shownState.reads == 2 and #nodes == nodeCount
    and editor.text:find("Cached sample", 1, true), "reopening the existing panel reuses both frames and rate-limited memory data")
shownState.clock = 115
shown.Show()
check(shownState.updates == 2 and shownState.reads == 4 and #nodes == nodeCount,
    "the panel takes its next fresh capture only on an eligible manual open")
editor.scripts.OnEscapePressed()
check(not editor.focused, "closing with Escape still clears the report edit box focus")

local profileLog, profileState, profileSaved, profileAddon = NewMemoryLog()
profileAddon.LastScanProfile = { outcome = "complete", source = "browse", at = 1800000000, rows = 6000, minimum_profit = 50,
    scan_ms = 1000, active_ms = 900, pause_ms = 100, provider_ms = 800, post_input_ms = 200,
    vendor_missing_ids = 40, vendor_missing_refs = 60, vendor_requests = 40, vendor_ready = 35,
    vendor_failed = 2, vendor_unresolved = 3, vendor_pending_ms = 500, vendor_pending_after_input_ms = 100,
    vendor_ready_avg_ms = 100, vendor_ready_max_ms = 300, vendor_loading_cpu_ms = 4,
    vendor_retry_cpu_ms = 5, valuation_cpu_ms = 6, de_cpu_ms = 7, history_ms = 8, batch_ms = 9 }
report = profileLog.Report()
for key, value in pairs(profileAddon.LastScanProfile) do
    check(report:find(key .. "=" .. tostring(value), 1, true), "the report retains the last profile's known field: " .. key)
end
check(report:find("Vendor pending time overlaps provider/processing time", 1, true)
    and report:find("provider time includes pauses", 1, true)
    and report:find("post_input_ms includes all finalization", 1, true)
    and report:find("instrumented slices, not native profiler CPU", 1, true), "profile caveats preserve overlap, pause and timing semantics")
check(profileLog.Report() == report and profileSaved.count == 0 and profileState.clocks == 0
    and profileState.updates == 0 and profileState.reads == 0,
    "the latest scan profile is available with debug off without probing, logging or mutating data")
profileAddon.LastScanProfile.outcome = restricted
profileAddon.LastScanProfile.vendor_requests = secretNumber
profileAddon.LastScanProfile.vendor_ready = -1
profileAddon.LastScanProfile.batch_ms = 0 / 0
report = profileLog.Report()
check(report:find("outcome=Unknown", 1, true) and report:find("vendor_requests=Unknown", 1, true)
    and report:find("vendor_ready=Unknown", 1, true) and report:find("batch_ms=Unknown", 1, true),
    "restricted and invalid profile fields are not formatted as trustworthy measurements")
profileAddon.LastScanProfile = restricted
check(profileLog.Report():find("No completed/cancelled scan profile yet", 1, true),
    "a restricted profile table is skipped before any field access")
print("Profit Master diagnostics: " .. checks .. " offline assertions passed (Lua 5.1).")
