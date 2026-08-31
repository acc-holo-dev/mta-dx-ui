--[[
    text.lua — DXUI V2

    Text engine: a standalone subsystem split into:
      - measurement — text measurement (cached);
      - layout      — word-wrap with color-code carry, ellipsis;
      - rendering   — stays in renderer/backend (align/valign/scale via
                      native dxDrawText params).

    Measurement backend: MTA — dxGetTextSize (accurate); outside MTA (tests) —
    monospace estimate (7x scale per char, 15x scale per line) — deterministic
    and fully testable.

    Cache: key holds text+font+scale+wrapWidth — changing any of them gives a
    different key (no stale values). Bounded by CAP (dynamic text);
    cleared in releaseResources.
]]

DXUI = DXUI or {}

local Text = {}

local CHAR_W = 7   -- monospace estimate (outside MTA)
local LINE_H = 15
local CACHE_CAP = 4096

-- ---------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------

local measureCache = {}
local measureCacheCount = 0

--- Measures ONE line (no wrap). Returns w, h.
local function measureLine(str, font, scale)
    local key = str .. "\1" .. tostring(font) .. "\1" .. tostring(scale)
    local cached = measureCache[key]
    if cached then return cached[1], cached[2] end

    local w, h
    if dxGetTextSize then
        w, h = dxGetTextSize(str, scale, font or "default")
    else
        w, h = #str * CHAR_W * scale, LINE_H * scale
    end

    if measureCacheCount >= CACHE_CAP then
        measureCache, measureCacheCount = {}, 0 -- simple bounded cache
    end
    measureCacheCount = measureCacheCount + 1
    measureCache[key] = { w, h }
    return w, h
end

--- Measures multi-line text (no wrap): max line width, lines x height.
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
-- Layout: word-wrap with color-code carry
-- ---------------------------------------------------------------------

--- Last active #RRGGBB code in the string (MTA color coding).
local function activeColorCode(s)
    local code = nil
    for c in s:gmatch("#%x%x%x%x%x%x") do code = c end
    return code
end

--- Word-wrap: splits text into lines <= wrapWidth, wrapping by words;
-- a word wider than wrapWidth is hard-cut (word break). The active
-- #RRGGBB code is carried to the start of the next line (color coding).
-- Returns { lines = {...}, lineHeight, width, height }.
function Text.wrap(text, font, scale, wrapWidth)
    scale = scale or 1
    local _, lineHeight = measureLine("Ag", font, scale)
    local lines = {}

    if wrapWidth == nil or wrapWidth <= 0 then
        -- no wrap: just split by \n
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
                    -- one word wider than wrapWidth — hard word break: cut
                    -- into pieces <= wrapWidth, carry the active color
                    local code = ""
                    while word ~= "" do
                        local piece = word:sub(1, 1)
                        word = word:sub(2)
                        while word ~= ""
                            and measureLine(code .. piece .. word:sub(1, 1), font, scale) <= wrapWidth do
                            piece = piece .. word:sub(1, 1)
                            word = word:sub(2)
                        end
                        lines[#lines + 1] = code .. piece
                        code = activeColorCode(code .. piece) or ""
                    end
                    line = code
                else
                    -- does not fit: close the line, carry the active color
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

--- Ellipsis: truncates text with "..." to maxWidth (one line).
function Text.ellipsis(text, font, scale, maxWidth)
    scale = scale or 1
    if text == nil or text == "" then return text end
    local w = measureLine(text, font, scale)
    if w <= maxWidth then return text end
    -- estimate: how many chars fit together with "..."
    local charW = w / #text
    local keep = math.floor((maxWidth - 3 * charW) / charW)
    if keep < 0 then keep = 0 end
    return text:sub(1, keep) .. "..."
end

--- Clears the measurement cache (releaseResources).
function Text.clearCache()
    measureCache, measureCacheCount = {}, 0
end

DXUI.Text = Text