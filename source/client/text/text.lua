--[[
    text.lua — DXUI V3

    Text subsystem (§38): measurement, layout, caching — rendering stays in
    the renderer/backend (align/valign native dxDrawText params).

    Measurement backend is INJECTED by the backend driver (backend_mta sets
    DXUI.Text.setMeasurer with dxGetTextSize; tests inject a deterministic
    monospace measurer). Outside any driver a monospace estimate is used.

    Caches (bounded): per-line measurement, full layout results. Byte-level
    UTF-8 limitation (Lua 5.1 has no native UTF-8) — documented.
]]

DXUI = DXUI or {}

local Text = {}

local CHAR_W = 7  -- monospace estimate fallback
local LINE_H = 15
local CACHE_CAP = 4096
local LAYOUT_CACHE_CAP = 256

-- ---------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------

local measurer = nil   -- fn(text, scale, font) -> w, h (screen-independent)
local measureCache = {}
local measureCacheCount = 0
local layoutCache = {}
local layoutCacheCount = 0

--- Injects the measurement backend (called by backend_mta / tests).
function Text.setMeasurer(fn)
    measurer = fn
end

--- Measures ONE line (no wrap). Returns w, h (design units).
local function measureLine(str, font, scale)
    local key = str .. "\1" .. tostring(font) .. "\1" .. tostring(scale)
    local cached = measureCache[key]
    if cached then return cached[1], cached[2] end
    local w, h
    if measurer then
        w, h = measurer(str, scale, font)
    else
        w, h = #str * CHAR_W * scale, LINE_H * scale
    end
    if measureCacheCount >= CACHE_CAP then
        measureCache, measureCacheCount = {}, 0
    end
    measureCacheCount = measureCacheCount + 1
    measureCache[key] = { w, h }
    return w, h
end

--- Measures multi-line text (no wrap): max line width, lines × height.
function Text.measure(text, font, scale)
    scale = scale or 1
    if text == nil or text == "" then return 0, 0 end
    local maxWidth = 0
    local lines = 0
    local _, lineHeight = measureLine("Ag", font, scale)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        local w = measureLine(line, font, scale)
        if w > maxWidth then maxWidth = w end
    end
    return maxWidth, lines * lineHeight
end

-- ---------------------------------------------------------------------
-- Layout: word-wrap with color-code carry, ellipsis
-- ---------------------------------------------------------------------

local function activeColorCode(s)
    local code = nil
    for c in s:gmatch("#%x%x%x%x%x%x") do code = c end
    return code
end

--- Word-wrap: splits into lines <= wrapWidth, wrapping by words; a word
-- wider than wrapWidth is hard-cut (word break); the active #RRGGBB code
-- is carried to the next line (color coding).
function Text.wrap(text, font, scale, wrapWidth)
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
            for word in paragraph:gmatch("%S+") do
                local candidate = (line == "") and word or (line .. " " .. word)
                local w = measureLine(candidate, font, scale)
                if w <= wrapWidth then
                    line = candidate
                elseif line == "" then
                    local code = ""
                    local wordLeft = word
                    while wordLeft ~= "" do
                        local piece = wordLeft:sub(1, 1)
                        wordLeft = wordLeft:sub(2)
                        while wordLeft ~= ""
                            and measureLine(code .. piece .. wordLeft:sub(1, 1), font, scale) <= wrapWidth do
                            piece = piece .. wordLeft:sub(1, 1)
                            wordLeft = wordLeft:sub(2)
                        end
                        lines[#lines + 1] = code .. piece
                        code = activeColorCode(code .. piece) or ""
                    end
                    line = code
                else
                    lines[#lines + 1] = line
                    local code = activeColorCode(line)
                    line = (code or "") .. word
                end
            end
            lines[#lines + 1] = line
        end
    end
    local width, height = 0, #lines * lineHeight
    for i = 1, #lines do
        local w = measureLine(lines[i], font, scale)
        if w > width then width = w end
    end
    return { lines = lines, lineHeight = lineHeight, width = width, height = height }
end

--- Ellipsis: truncates with "..." to maxWidth (binary search on prefix).
function Text.ellipsis(text, font, scale, maxWidth)
    scale = scale or 1
    if text == nil or text == "" then return text end
    local w = measureLine(text, font, scale)
    if w <= maxWidth then return text end
    local suffix = "..."
    if measureLine(suffix, font, scale) > maxWidth then return "" end
    local lo, hi, best = 0, #text, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local pw = measureLine(text:sub(1, mid), font, scale)
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
-- width), default — split by \n. Result is a SHARED cached table —
-- callers must treat it as read-only.
function Text.layout(text, font, scale, opts)
    scale = scale or 1
    opts = opts or {}
    local mode = opts.wrap and "wrap" or (opts.ellipsis and "ellipsis" or "plain")
    local w = opts.width or 0
    local key = text .. "\1" .. tostring(font) .. "\1" .. tostring(scale)
        .. "\1" .. mode .. "\1" .. tostring(w)
    local cached = layoutCache[key]
    if cached then return cached end
    local laid
    if mode == "wrap" and w > 0 then
        laid = Text.wrap(text, font, scale, w)
    elseif mode == "ellipsis" and w > 0 then
        local line = Text.ellipsis(text, font, scale, w)
        local _, lh = Text.measure("Ag", font, scale)
        laid = { lines = { line }, lineHeight = lh, height = lh }
    else
        laid = Text.wrap(text, font, scale, nil)
    end
    if layoutCacheCount >= LAYOUT_CACHE_CAP then
        layoutCache, layoutCacheCount = {}, 0
    end
    layoutCacheCount = layoutCacheCount + 1
    layoutCache[key] = laid
    return laid
end

--- Column/selection geometry foundation (Edit uses it): pixel x of a
-- character index within a single line.
function Text.charX(line, font, scale, col)
    if col <= 0 then return 0 end
    local w = Text.measure(line:sub(1, col), font, scale)
    return w
end

function Text.clearCache()
    measureCache, measureCacheCount = {}, 0
    layoutCache, layoutCacheCount = {}, 0
end

DXUI.Text = Text