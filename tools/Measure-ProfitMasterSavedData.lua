-- Read-only offline SavedVariables inventory/heap measurement. No WoW APIs.
-- Saved code runs with an empty environment and an instruction budget, and
-- cannot reach these tooling io/os/debug functions. Never writes the source file.
local path = assert(os.getenv("PROFITMASTER_SAVED_PATH"), "Set PROFITMASTER_SAVED_PATH to the saved ProfitMaster.lua file")
if jit then jit.off() end -- Count hooks must also bound loops in a malformed file.
local allowed = { ProfitMasterDB = true, ProfitMasterDebugDB = true, ProfitMasterDisenchantDB = true }
local file = assert(io.open(path, "rb"))
local bytes = assert(file:seek("end"))
file:close()
assert(bytes <= 64 * 1024 * 1024, "SavedVariables file exceeds the offline 64 MiB measurement limit")

local function Heap()
    local previous
    for _ = 1, 8 do
        collectgarbage("collect")
        local current = collectgarbage("count")
        if previous and math.abs(current - previous) < 0.001 then return current end
        previous = current
    end
    return previous
end

-- LuaJIT's compiler has a lower constants limit than WoW's SavedVariables
-- writer. For large files, accept only literal data rather than executing a
-- giant chunk. Individual quoted-string tokens still use Lua's exact decoder.
local function LiteralData()
    local input = assert(io.open(path, "rb"))
    local source = input:read("*a")
    input:close()
    local position, depth, value = 1, 0
    local function Space()
        position = source:find("%S", position) or (#source + 1)
    end
    local function Quoted()
        local first, quote = position, source:sub(position, position)
        local last = position
        repeat
            last = assert(source:find(quote, last + 1, true), "Unterminated saved string")
            local escapes, cursor = 0, last - 1
            while source:sub(cursor, cursor) == "\\" do escapes, cursor = escapes + 1, cursor - 1 end
            if escapes % 2 == 0 then break end
        until false
        local token = source:sub(first, last)
        local decode = assert(loadstring("return " .. token))
        setfenv(decode, {})
        position = last + 1
        return decode()
    end
    local function Name()
        local first, last = source:find("^[_%a][_%w]*", position)
        assert(first == position, "Expected a literal field name")
        position = last + 1
        return source:sub(first, last)
    end
    local function Table()
        depth = depth + 1
        assert(depth <= 64, "Saved table nesting exceeds measurement limit")
        position = position + 1
        local result, arrayIndex = {}, 1
        Space()
        while source:sub(position, position) ~= "}" do
            assert(position <= #source, "Unterminated saved table")
            local key, entry
            if source:sub(position, position) == "[" then
                position = position + 1
                key = value()
                assert(type(key) == "string" or type(key) == "number" or type(key) == "boolean", "Unsupported saved table key")
                Space()
                assert(source:sub(position, position) == "]", "Expected saved key terminator")
                position = position + 1
                Space()
                assert(source:sub(position, position) == "=", "Expected saved field assignment")
                position = position + 1
                entry = value()
            else
                key, arrayIndex = arrayIndex, arrayIndex + 1
                entry = value()
            end
            result[key] = entry
            Space()
            local separator = source:sub(position, position)
            assert(separator == "," or separator == ";" or separator == "}", "Expected literal field separator")
            if separator ~= "}" then position = position + 1; Space() end
        end
        position, depth = position + 1, depth - 1
        return result
    end
    value = function()
        Space()
        local first = source:sub(position, position)
        if first == "{" then return Table() end
        if first == '"' or first == "'" then return Quoted() end
        local start, finish = source:find("^[%+%-]?0[xX][%da-fA-F]+", position)
        if start ~= position then start, finish = source:find("^[%+%-]?[%d%.]+[eE]?[%+%-]?%d*", position) end
        if start == position then
            local number = assert(tonumber(source:sub(start, finish)), "Invalid saved numeric literal")
            position = finish + 1
            return number
        end
        local word = Name()
        if word == "true" then return true end
        if word == "false" then return false end
        assert(word == "nil", "Executable expression is not SavedVariables literal data")
        return nil
    end
    local environment = {}
    Space()
    while position <= #source do
        local name = Name()
        assert(allowed[name], "Unexpected global in SavedVariables literal data")
        Space()
        assert(source:sub(position, position) == "=", "Expected root SavedVariables assignment")
        position = position + 1
        environment[name] = value()
        Space()
    end
    return environment
end

local function Load()
    local before = Heap()
    local chunk, compileFailure = loadfile(path)
    local environment = {}
    if chunk then setfenv(chunk, environment)
    else assert(compileFailure:find("more than 65536 constants", 1, true), compileFailure) end
    local instructions = 0
    debug.sethook(function()
        instructions = instructions + 10000
        if instructions > 250000000 then error("SavedVariables exceeded the offline instruction budget") end
    end, "", 10000)
    local method = chunk and "sandboxed chunk" or "strict literal parser (compiler constant limit)"
    local ok, failure = pcall(chunk or LiteralData)
    if not chunk and ok then environment = failure end
    debug.sethook()
    chunk = nil
    assert(ok, failure)
    for name in pairs(environment) do assert(allowed[name], "Unexpected global in SavedVariables sandbox") end
    for name in pairs(allowed) do assert(type(environment[name]) == "table", "Missing expected SavedVariables table: " .. name) end
    return environment, before, Heap(), method
end

local function Count(value)
    local count = 0
    if type(value) == "table" then for _ in pairs(value) do count = count + 1 end end
    return count
end

local function Number(value, minimum)
    return type(value) == "number" and value == value and value < math.huge
        and value > -math.huge and value >= minimum
end

local function Inventory(db)
    local result = { items = Count(db.items), vendors = 0, zeroVendors = 0, markets = Count(db.markets),
        dayBuckets = 0, legacyRows = 0, legacySamples = 0, rollupRows = 0, trimmedSnapshots = 0, meanContributions = 0 }
    local days = {}
    for _, item in pairs(db.items or {}) do
        if type(item) == "table" and Number(item.vendorPrice, 0) then
            result.vendors = result.vendors + 1
            if item.vendorPrice == 0 then result.zeroVendors = result.zeroVendors + 1 end
        end
    end
    for _, market in pairs(db.markets or {}) do
        if type(market) == "table" and type(market.days) == "table" then
            for day, bucket in pairs(market.days) do
                if type(bucket) == "table" then
                    result.dayBuckets = result.dayBuckets + 1
                    if type(day) == "number" then days[day] = true end
                    for _, row in pairs(bucket.records or {}) do
                        result.legacyRows = result.legacyRows + 1
                        if type(row) == "table" and Number(row.samples, 0) then result.legacySamples = result.legacySamples + row.samples end
                    end
                    for _, row in pairs(bucket.trimmedMeans or {}) do
                        result.rollupRows = result.rollupRows + 1
                        if type(row) == "table" and Number(row.count, 0) then result.meanContributions = result.meanContributions + row.count end
                    end
                    if Number(bucket.trimmedScans, 0) then result.trimmedSnapshots = result.trimmedSnapshots + bucket.trimmedScans end
                end
            end
        end
    end
    result.days = Count(days)
    local sorted = {}
    for day in pairs(days) do sorted[#sorted + 1] = day end
    table.sort(sorted)
    result.firstDay = sorted[1] and os.date("!%Y-%m-%d", sorted[1] * 86400) or "none"
    result.lastDay = sorted[#sorted] and os.date("!%Y-%m-%d", sorted[#sorted] * 86400) or "none"
    return result
end

local function Fields(payload)
    local fields = {}
    for name, value in payload:gmatch("([%a_][%w_]*)=([^ ]+)") do fields[name] = value end
    return fields
end

local function DebugEvents(db)
    local events = {}
    if type(db.entries) ~= "table" or not Number(db.count, 0) or not Number(db.next, 1) then return events end
    local limit = 1000
    for offset = 0, math.min(db.count, limit) - 1 do
        local index = (db.next - db.count - 1 + offset) % limit + 1
        local line = db.entries[index]
        if type(line) == "string" then
            local epoch, seconds, sequence, event, payload = line:match("^(%d+) t=([%d%.]+) #(%d+) (%S+)%s*(.*)$")
            if epoch then events[#events + 1] = { epoch = tonumber(epoch), seconds = tonumber(seconds),
                sequence = tonumber(sequence), event = event, fields = Fields(payload) } end
        end
    end
    table.sort(events, function(a, b) return a.sequence < b.sequence end)
    return events
end

local function ScanWindows(events)
    local completed, window = {}, { events = {} }
    for _, event in ipairs(events) do
        if event.event == "session" then window = { events = {} }
        elseif event.event == "scan_start" then window = { start = event, events = {} } end
        window.events[#window.events + 1] = event
        if event.event == "scan_complete" then
            window.finish = event
            completed[#completed + 1] = window
            window = { events = {} }
        end
    end
    return completed
end

local environment, before, after, method = Load()
local loaded = Heap()
environment.ProfitMasterDisenchantDB = nil
local withoutSettings = Heap()
environment.ProfitMasterDebugDB = nil
local withoutDebug = Heap()
local main = environment.ProfitMasterDB
main.items = nil
local withoutItems = Heap()
main.markets = nil
local withoutMarkets = Heap()
environment.ProfitMasterDB = nil
main = nil
local released = Heap()
local retained, settingsHeap, debugHeap, mainHeap = loaded - released,
    loaded - withoutSettings, withoutSettings - withoutDebug, withoutDebug - released
local itemsHeap, marketsHeap, remainderHeap = withoutDebug - withoutItems, withoutItems - withoutMarkets, withoutMarkets - released
environment = nil
Heap()
environment = Load()
local inventory = Inventory(environment.ProfitMasterDB)
local debugDB = environment.ProfitMasterDebugDB
local events = DebugEvents(debugDB)
print(string.format("FILE bytes=%d (%.3f MiB); schema=%s; minimumProfit=%s", bytes, bytes / 1048576,
    tostring(environment.ProfitMasterDB.version), tostring(environment.ProfitMasterDB.minimumProfit)))
print(string.format("DATA items=%d verifiedVendorPrices=%d (zero=%d) markets=%d dayBuckets=%d distinctUTCDays=%d [%s..%s] legacyRows=%d legacySamples=%d rollupRows=%d trimmedSnapshots=%d meanContributions=%d",
    inventory.items, inventory.vendors, inventory.zeroVendors, inventory.markets, inventory.dayBuckets, inventory.days,
    inventory.firstDay, inventory.lastDay, inventory.legacyRows, inventory.legacySamples,
    inventory.rollupRows, inventory.trimmedSnapshots, inventory.meanContributions))
print(string.format("DEBUG enabled=%s retained=%s parsed=%d sequence=%s [%s..%s]; DE enabled=%s", tostring(debugDB.enabled),
    tostring(debugDB.count), #events, tostring(debugDB.sequence), events[1] and events[1].sequence or "none",
    events[#events] and events[#events].sequence or "none", tostring(environment.ProfitMasterDisenchantDB.enabled)))
print(string.format("HEAP full root-release delta=%.3f KiB (%.3f MiB); load-minus-prior-baseline=%.3f KiB", retained, retained / 1024, after - before))
print("LOAD " .. method .. "; complete literal source and decoder chunks released before heap measurement")

local completed = ScanWindows(events)
for i = math.max(1, #completed - 2), #completed do
    local window = completed[i]
    local firstLoad, lastLoad, lastProgress, publications, pauses = nil, nil, nil, 0, 0
    for _, event in ipairs(window.events) do
        if event.event == "vendor_load_start" and not firstLoad then firstLoad = event end
        if event.event == "vendor_load" then
            if not firstLoad then firstLoad = event end
            lastLoad, lastProgress = event, event.fields
        end
        if event.event == "scan_publish" then publications = publications + 1 end
        if event.event == "search_sent" then pauses = pauses + 1 end
    end
    local finish = window.finish
    local elapsed = window.start and finish.seconds - window.start.seconds
    local span = firstLoad and lastLoad and lastLoad.seconds - firstLoad.seconds
    print(string.format("SCAN #%d..#%d source=%s rows=%s candidates=%s wall=%s; vendor first=#%s last=#%s span=%s completed=%s/%s ready=%s failed=%s receivingAtStart=%s purchaseSearches=%d",
        window.start and window.start.sequence or 0, finish.sequence, finish.fields.source or "unknown", finish.fields.rows or "unknown",
        finish.fields.candidates or "unknown", elapsed and string.format("%.3fs", elapsed) or "start not retained",
        firstLoad and firstLoad.sequence or "none", lastLoad and lastLoad.sequence or "none", span and string.format("%.3fs", span) or "not retained",
        lastProgress and lastProgress.completed or "unknown", lastProgress and lastProgress.total or "unknown",
        lastProgress and lastProgress.ready or "unknown", lastProgress and lastProgress.failed or "unknown",
        firstLoad and firstLoad.fields.receiving or "unknown", pauses))
    local profiles = {}
    for name, value in pairs(finish.fields) do
        if name:match("_ms$") or name:match("^vendor_") or name == "unavailable" then profiles[#profiles + 1] = name .. "=" .. value end
    end
    table.sort(profiles)
    print("  recorded scan-complete fields: " .. table.concat(profiles, " "))
end
print("Vendor span is first retained load-start/completion to last completion, not exclusive loading CPU or critical-path delay; it can overlap scanning/purchase waits.")

print(string.format("HEAP marginal release ProfitMasterDisenchantDB=%.3f KiB; ProfitMasterDebugDB=%.3f KiB; ProfitMasterDB=%.3f KiB",
    settingsHeap, debugHeap, mainHeap))
print(string.format("HEAP main subtrees items=%.3f KiB (%.3f MiB); markets=%.3f KiB (%.3f MiB); main remainder=%.3f KiB",
    itemsHeap, itemsHeap / 1024, marketsHeap, marketsHeap / 1024, remainderHeap))
print("Offline Lua 5.1-compatible OBS LuaJIT heap with JIT disabled, not WoW/addon-attributed RAM. Marginal releases are ordered settings -> debug -> items -> markets -> main remainder; shared strings/allocator effects are charged to whichever subtree releases them last.")
