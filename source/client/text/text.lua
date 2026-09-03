---Text subsystem: measurement, layout, caching — rendering stays in
---the renderer/backend (align/valign native dxDrawText params).
---
---Measurement backend is INJECTED by the backend driver (backend_mta sets
---DXUI.Text.setMeasurer with dxGetTextSize; tests inject a deterministic
---monospace measurer). Outside any driver a monospace estimate is used.
---
---Caches (bounded): per-line measurement, full layout results. Byte-level
---UTF-8 limitation (Lua 5.1 has no native UTF-8) — documented.

DXUI = DXUI or {}

local Text = {}

-- monospace estimate fallback
local CHAR_W = 7
local LINE_H = 15
local CACHE_CAP = 4096
local LAYOUT_CACHE_CAP = 256

-- ---------------------------------------------------------------------
-- Two-generation cache: on cap, only the STALE previous generation is
-- cleared and promoted, so the current generation's hot entries survive.
-- A full wipe on cap would thrash under a working set larger than the cap.
-- ---------------------------------------------------------------------
local function makeGenCache(cap)
    local gen1, gen2 = {}, {}
    local cur, count = gen1, 0
    return {
        get = function(key)
            local v = cur[key]
            if v ~= nil then return v end
            return ((cur == gen1) and gen2 or gen1)[key]
        end,
        put = function(key, value)
            if count >= cap then
                local old = (cur == gen1) and gen2 or gen1
                for k in pairs(old) do old[k] = nil end
                cur, count = old, 0
            end
            count = count + 1
            cur[key] = value
        end,
    }
end

-- ---------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------

-- fn(text, scale, font) -> w, h (screen-independent)
local measurer = nil
local measureCache = makeGenCache(CACHE_CAP)
local layoutCache = makeGenCache(LAYOUT_CACHE_CAP)

--- Injects the measurement backend (called by backend_mta / tests).
function Text.setMeasurer(fn)
    measurer = fn
end

--- Cache key for a (text, font, scale) triple. Length-prefixed so a
-- separator byte inside the text cannot collide with another entry.
local function cacheKey(str, font, scale)
    return #str .. ":" .. str .. "|" .. tostring(font) .. "|" .. tostring(scale)
end

--- Strips #RRGGBB color codes (the rich-measurement view of a line:
--- embedded codes render zero-width — see Label.rich).
local function stripCodes(s)
    return (s:gsub("#%x%x%x%x%x%x", ""))
end

--- Measures ONE line (no wrap). Returns w, h (design units). `rich`
--- measures the code-stripped string (colorCoded draw semantics); the
--- stripped form IS the cache key, so plain and rich measurements of
--- the same source line never collide.
local function measureLine(str, font, scale, rich)
    if rich then str = stripCodes(str) end
    local key = cacheKey(str, font, scale)
    local cached = measureCache.get(key)
    if cached then return cached[1], cached[2] end
    local w, h
    if measurer then
        w, h = measurer(str, scale, font)
    else
        w, h = #str * CHAR_W * scale, LINE_H * scale
    end
    measureCache.put(key, { w, h })
    return w, h
end

--- Measures multi-line text (no wrap): max line width, lines × height.
--- `rich` (4th arg) measures the code-stripped lines (see measureLine).
function Text.measure(text, font, scale, rich)
    scale = scale or 1
    if text == nil or text == "" then return 0, 0 end
    local maxWidth = 0
    local lines = 0
    local _, lineHeight = measureLine("Ag", font, scale)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        local w = measureLine(line, font, scale, rich)
        if w > maxWidth then maxWidth = w end
    end
    return maxWidth, lines * lineHeight
end

-- ---------------------------------------------------------------------
-- Layout: word-wrap with color-code carry, ellipsis
-- ---------------------------------------------------------------------

--- Returns the last #RRGGBB color code in a string, or nil.
local function activeColorCode(s)
    local code = nil
    for c in s:gmatch("#%x%x%x%x%x%x") do code = c end
    return code
end

--- Word-wrap: splits into lines <= wrapWidth, wrapping by words; a word
-- wider than wrapWidth is hard-cut (word break); the active #RRGGBB code
-- is carried to the next line (color coding). `rich` measures the
-- code-stripped candidates (codes render zero-width).
function Text.wrap(text, font, scale, wrapWidth, rich)
    scale = scale or 1
    local _, lineHeight = measureLine("Ag", font, scale)
    local lines = {}
    if wrapWidth == nil or wrapWidth <= 0 then
        for line in (text .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end
    else
        for paragraph in (text .. "\n"):gmatch("(.-)\n") do
            local line = ""
            local anyWord = false
            -- capture each word with the whitespace preceding it so
            -- original spacing (tabs, multiple spaces) is preserved
            for ws, word in paragraph:gmatch("(%s*)(%S+)") do
                anyWord = true
                local candidate = (line == "") and (ws .. word) or (line .. ws .. word)
                local w = measureLine(candidate, font, scale, rich)
                if w <= wrapWidth then
                    line = candidate
                elseif line == "" then
                    -- hard-cut: a single word wider than the wrap width;
                    -- grow the candidate one char at a time (O(n), not
                    -- O(n^2) triple-concat per char)
                    local code = ""
                    local wordLeft = word
                    while wordLeft ~= "" do
                        local cand = code
                        while wordLeft ~= "" do
                            local nextCand = cand .. wordLeft:sub(1, 1)
                            -- always emit at least one char; stop growing
                            -- once the next char overflows the wrap width
                            if cand ~= code and measureLine(nextCand, font, scale, rich) > wrapWidth then break end
                            cand = nextCand
                            wordLeft = wordLeft:sub(2)
                        end
                        lines[#lines + 1] = cand
                        code = activeColorCode(cand) or ""
                    end
                    line = code
                else
                    lines[#lines + 1] = line
                    local code = activeColorCode(line)
                    line = (code or "") .. word
                end
            end
            -- push the trailing line, unless a hard-cut consumed the whole
            -- paragraph and left nothing to carry (no spurious empty line)
            if not (anyWord and line == "") then
                lines[#lines + 1] = line
            end
        end
    end
    local width, height = 0, #lines * lineHeight
    for i = 1, #lines do
        local w = measureLine(lines[i], font, scale, rich)
        if w > width then width = w end
    end
    return { lines = lines, lineHeight = lineHeight, width = width, height = height }
end

--- Ellipsis: truncates with "..." to maxWidth (binary search on prefix).
--- `rich` measures code-stripped prefixes (codes render zero-width).
function Text.ellipsis(text, font, scale, maxWidth, rich)
    scale = scale or 1
    if text == nil or text == "" then return text end
    local w = measureLine(text, font, scale, rich)
    if w <= maxWidth then return text end
    local suffix = "..."
    if measureLine(suffix, font, scale) > maxWidth then return "" end
    local lo, hi, best = 0, #text, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local pw = measureLine(text:sub(1, mid), font, scale, rich)
        if pw + measureLine(suffix, font, scale) <= maxWidth then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return text:sub(1, best) .. suffix
end

--- One-call text layout with caching. opts: wrap (by width), ellipsis (to
-- width), rich (measure code-stripped — #RRGGBB renders), default —
-- split by \n. Result is a SHARED cached table — callers must treat it
-- as read-only.
function Text.layout(text, font, scale, opts)
    scale = scale or 1
    opts = opts or {}
    local mode = opts.wrap and "wrap" or (opts.ellipsis and "ellipsis" or "plain")
    local w = opts.width or 0
    local key = cacheKey(text, font, scale) .. "|" .. mode .. "|" .. tostring(w)
        .. (opts.rich and "|r" or "")
    local cached = layoutCache.get(key)
    if cached then return cached end
    local laid
    if mode == "wrap" and w > 0 then
        laid = Text.wrap(text, font, scale, w, opts.rich)
    elseif mode == "ellipsis" and w > 0 then
        local line = Text.ellipsis(text, font, scale, w, opts.rich)
        local _, lh = Text.measure("Ag", font, scale)
        laid = { lines = { line }, lineHeight = lh, height = lh }
    else
        laid = Text.wrap(text, font, scale, nil, opts.rich)
    end
    layoutCache.put(key, laid)
    -- return a shallow copy so a mutating caller cannot corrupt the cached
    -- scalars; the `lines` ARRAY stays shared — every internal caller is
    -- read-only, so treat laid.lines as read-only (a per-call deep copy
    -- would allocate on every Label render)
    return { lines = laid.lines, lineHeight = laid.lineHeight,
             width = laid.width, height = laid.height }
end

--- Column/selection geometry foundation (Edit uses it): pixel x of a
-- character index within a single line.
function Text.charX(line, font, scale, col)
    if col <= 0 then return 0 end
    local w = Text.measure(line:sub(1, col), font, scale)
    return w
end

--- Clears the measurement and layout caches.
function Text.clearCache()
    measureCache = makeGenCache(CACHE_CAP)
    layoutCache = makeGenCache(LAYOUT_CACHE_CAP)
end

DXUI.Text = Text