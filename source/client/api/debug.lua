---DXUI.Debug — structured diagnostics with levels, categories, and
---rate limiting. Pure Lua 5.1, no MTA dependency (works in tests).
---
---Levels (ascending severity):
---    TRACE = 1  -- per-frame, per-event detail (very verbose)
---    DEBUG = 2  -- internal flow, state transitions
---    INFO  = 3  -- lifecycle, user-facing operations
---    WARN  = 4  -- recoverable issues, fallbacks
---    ERROR = 5  -- failures that break functionality
---
---Categories (subsystem tags):
---    CORE, LIFECYCLE, PROPERTY, LAYOUT, INPUT, EVENT, RENDER,
---    STYLE, RESOURCE, ANIMATION, WIDGET, PERFORMANCE, THEME, TEXT
---
---Usage:
---    DXUI.Debug.log("STYLE", "DEBUG", "theme applied", {
---        widget = "Button#42", style = "primary", state = "hover"
---    })
---    DXUI.Debug.warn("PROPERTY", "set on unknown property: " .. key)
---    DXUI.Debug.error("RENDER", "shader compilation failed: " .. err)

DXUI = DXUI or {}

local Debug = {}
Debug.__index = Debug

-- ---------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------

Debug.LEVELS = {
    TRACE = 1,
    DEBUG = 2,
    INFO = 3,
    WARN = 4,
    ERROR = 5,
}

Debug.CATEGORIES = {
    CORE = true, LIFECYCLE = true, PROPERTY = true, LAYOUT = true,
    INPUT = true, EVENT = true, RENDER = true, STYLE = true,
    RESOURCE = true, ANIMATION = true, WIDGET = true, PERFORMANCE = true,
    THEME = true, TEXT = true,
}

-- Default: WARN in production, DEBUG in dev mode
local defaultLevel = (DXUI.config and DXUI.config.dev) and Debug.LEVELS.DEBUG or Debug.LEVELS.WARN

-- Per-category level overrides (nil = use global)
local categoryLevels = {}

-- Global minimum level
local globalLevel = defaultLevel

-- Rate limiting: per (category, key) once per interval
local rateLimits = {}
local RATE_WINDOW_MS = 1000

-- Once-only logs: (category, key) -> true
local onceLog = {}

-- Aggregated performance counters (flushed periodically)
local perfCounters = {}
local PERF_FLUSH_MS = 2000
local lastPerfFlush = 0

-- Output sink (can be replaced for tests)
local sink = nil

local function defaultSink(level, category, msg, fields)
    local prefix = string.format("[DXUI][%s][%s]", category, level)
    local fieldStr = ""
    if fields and next(fields) then
        local parts = {}
        for k, v in pairs(fields) do
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
        fieldStr = " " .. table.concat(parts, " ")
    end
    local line = prefix .. " " .. msg .. fieldStr
    if outputDebugString then
        outputDebugString(line)
    else
        print(line)
    end
end

local function shouldLog(category, level)
    if not Debug.CATEGORIES[category] then return false end
    local catLevel = categoryLevels[category]
    local minLevel = catLevel or globalLevel
    return level >= minLevel
end

--- Cheap guard for the structured helpers: true when a log at `level`
--- (default DEBUG) in `category` would emit. The helpers build field
--- tables, so they must early-out BEFORE allocating when off (production
--- hot paths).
local function debugEnabled(category, level)
    return shouldLog(category, level or Debug.LEVELS.DEBUG)
end

local function checkRateLimit(category, key)
    local now = (getTickCount and getTickCount()) or 0
    local rk = category .. "\1" .. key
    local last = rateLimits[rk]
    if last and (now - last) < RATE_WINDOW_MS then return false end
    rateLimits[rk] = now
    return true
end

local function checkOnce(category, key)
    local ok = onceLog[category .. "\1" .. key]
    if ok then return false end
    onceLog[category .. "\1" .. key] = true
    return true
end

-- ---------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------

--- Sets the global minimum log level (TRACE..ERROR or 1..5).
function Debug.setLevel(level)
    if type(level) == "string" then
        level = Debug.LEVELS[level:upper()] or Debug.LEVELS.WARN
    end
    globalLevel = level
end

--- Sets a category-specific minimum level (overrides global).
function Debug.setCategoryLevel(category, level)
    if type(level) == "string" then
        level = Debug.LEVELS[level:upper()] or Debug.LEVELS.WARN
    end
    categoryLevels[category] = level
end

--- Enables/disables a category entirely.
function Debug.setCategoryEnabled(category, enabled)
    if enabled then
        categoryLevels[category] = nil
    else
        categoryLevels[category] = Debug.LEVELS.ERROR + 1
    end
end

--- Replaces the output sink (for tests or custom logging).
--- fn(level, category, msg, fields)
function Debug.setSink(fn)
    sink = fn
end

--- Resets all configuration to defaults.
function Debug.reset()
    globalLevel = defaultLevel
    categoryLevels = {}
    rateLimits = {}
    onceLog = {}
    perfCounters = {}
    lastPerfFlush = 0
end

--- Core logging function.
---@param category string one of Debug.CATEGORIES
---@param level string|number "TRACE".."ERROR" or 1..5
---@param msg string message
---@param fields? table key-value context (widget, property, old/new, etc.)
---@param opts? table { once = bool, rateLimit = bool, rateKey = string }
function Debug.log(category, level, msg, fields, opts)
    opts = opts or {}
    if type(level) == "string" then level = Debug.LEVELS[level:upper()] or Debug.LEVELS.INFO end
    if not shouldLog(category, level) then return end
    if opts.once and not checkOnce(category, opts.rateKey or msg) then return end
    if opts.rateLimit and not checkRateLimit(category, opts.rateKey or msg) then return end
    local fn = sink or defaultSink
    fn(level, category, msg, fields)
end

--- Convenience: TRACE
function Debug.trace(category, msg, fields, opts) Debug.log(category, "TRACE", msg, fields, opts) end
--- Convenience: DEBUG
function Debug.debug(category, msg, fields, opts) Debug.log(category, "DEBUG", msg, fields, opts) end
--- Convenience: INFO
function Debug.info(category, msg, fields, opts) Debug.log(category, "INFO", msg, fields, opts) end
--- Convenience: WARN
function Debug.warn(category, msg, fields, opts) Debug.log(category, "WARN", msg, fields, opts) end
--- Convenience: ERROR
function Debug.error(category, msg, fields, opts) Debug.log(category, "ERROR", msg, fields, opts) end

--- Logs once per (category, key).
function Debug.once(category, level, msg, fields, key)
    Debug.log(category, level, msg, fields, { once = true, rateKey = key })
end

--- Logs at most once per RATE_WINDOW_MS per (category, key).
function Debug.throttle(category, level, msg, fields, key)
    Debug.log(category, level, msg, fields, { rateLimit = true, rateKey = key })
end

--- Performance counter increment (aggregated, flushed periodically).
--- category = "PERFORMANCE", key = counter name, delta = increment (default 1).
--- Cheap no-op when performance logging is off (the guard runs before any
--- table write, so the hot path stays allocation-free in production).
function Debug.perf(category, key, delta)
    if not debugEnabled("PERFORMANCE", Debug.LEVELS.INFO) then return end
    delta = delta or 1
    local k = category .. "\1" .. key
    perfCounters[k] = (perfCounters[k] or 0) + delta
    local now = (getTickCount and getTickCount()) or 0
    if now - lastPerfFlush >= PERF_FLUSH_MS then
        Debug.flushPerf()
        lastPerfFlush = now
    end
end

--- Flushes aggregated performance counters as a single INFO line.
function Debug.flushPerf()
    if not next(perfCounters) then return end
    local parts = {}
    for k, v in pairs(perfCounters) do
        local key = k:match("\1(.+)")
        parts[#parts + 1] = key .. "=" .. v
    end
    Debug.info("PERFORMANCE", "counters " .. table.concat(parts, " "), nil)
    perfCounters = {}
end

--- Structured lifecycle event (mount/destroy/style/animate).
function Debug.lifecycle(event, node, extra)
    if not debugEnabled("LIFECYCLE", Debug.LEVELS.INFO) then return end
    local fields = { widget = node._class and node._class._name or "?", id = node._id }
    if extra then for k, v in pairs(extra) do fields[k] = v end end
    Debug.info("LIFECYCLE", event, fields)
end

--- Structured property change (old/new, owner, invalidation).
function Debug.prop(node, key, old, new, owner, invalidates)
    if not debugEnabled("PROPERTY") then return end
    local fields = { widget = node._class and node._class._name or "?", id = node._id, property = key, old = tostring(old), new = tostring(new), owner = owner }
    if invalidates then fields.invalidates = table.concat(invalidates, ",") end
    Debug.debug("PROPERTY", "changed", fields)
end

--- Structured style application (theme/component/state).
function Debug.style(node, source, state, props)
    if not debugEnabled("STYLE") then return end
    local fields = { widget = node._class and node._class._name or "?", id = node._id, source = source, state = state }
    if props then for k, v in pairs(props) do fields[k] = v end end
    Debug.debug("STYLE", "apply", fields)
end

--- Structured input event (target, coords, layer).
function Debug.input(event, target, x, y, layer)
    if not debugEnabled("INPUT") then return end
    local fields = { event = event, target = target._class and target._class._name or "?", id = target._id, x = x, y = y, layer = layer }
    Debug.debug("INPUT", event, fields)
end

--- Structured render pass (dirty flags, nodes, items). Rate-limited to
--- once per RATE_WINDOW_MS per instance — a per-frame log would spam.
function Debug.render(instance, layoutRuns, rebuilds, items, nodes)
    if not debugEnabled("RENDER") then return end
    local fields = { instance = instance.name, layoutRuns = layoutRuns, rebuilds = rebuilds, items = items, nodes = nodes }
    Debug.log("RENDER", "DEBUG", "pass", fields, { rateLimit = true, rateKey = instance.name })
end

--- Structured theme operation (switch/compile/reapply).
function Debug.theme(op, theme, component, styleKey)
    if not debugEnabled("THEME", Debug.LEVELS.INFO) then return end
    local fields = { operation = op, theme = theme, component = component, styleKey = styleKey }
    Debug.info("THEME", op, fields)
end

--- Structured resource load/release.
function Debug.resource(op, type, key, success)
    if not debugEnabled("RESOURCE") then return end
    local fields = { operation = op, type = type, key = key, success = success }
    Debug.debug("RESOURCE", op, fields)
end

--- Structured animation event (start/update/stop).
function Debug.anim(event, node, props, duration, easing)
    if not debugEnabled("ANIMATION") then return end
    local fields = { widget = node._class and node._class._name or "?", id = node._id, props = props and table.concat(props, ",") or "", duration = duration, easing = easing }
    Debug.debug("ANIMATION", event, fields)
end

--- Structured text/layout measurement.
function Debug.text(op, widget, text, font, result)
    if not debugEnabled("TEXT") then return end
    local fields = { widget = widget, text = text, font = font }
    if result then fields.width = result[1]; fields.height = result[2] end
    Debug.debug("TEXT", op, fields)
end

--- Returns current configuration for inspection.
function Debug.getConfig()
    return {
        globalLevel = globalLevel,
        categoryLevels = categoryLevels,
    }
end

DXUI.Debug = Debug

-- Back-compat: DXUI._warn routes through Debug
DXUI._warn = function(msg)
    Debug.warn("CORE", msg)
end