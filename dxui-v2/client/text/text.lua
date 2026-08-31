--[[
    text.lua — DXUI V2

    Text engine (§41): самостоятельная подсистема, разделённая на:
      - measurement — измерение текста (кэшируется, §43);
      - layout      — word-wrap с переносом color-кодов, ellipsis;
      - rendering   — остаётся в renderer/backend (align/valign/scale через
                      нативные параметры dxDrawText).

    Measurement backend: MTA — dxGetTextSize (точно); вне MTA (тесты) —
    monospace-оценка (7×scale на символ, 15×scale на строку) — детерминирована
    и полностью тестируема.

    Кэш (§43): ключ содержит text+font+scale+wrapWidth — смена любого из них
    даёт другой ключ (нет stale-значений). Ограничен CAP (динамический текст);
    чистится в releaseResources.
]]

DXUI = DXUI or {}

local Text = {}

local CHAR_W = 7   -- monospace-оценка (вне MTA)
local LINE_H = 15
local CACHE_CAP = 4096

-- ---------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------

local measureCache = {}
local measureCacheCount = 0

--- Измеряет ОДНУ строку (без wrap). Возвращает w, h.
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
        measureCache, measureCacheCount = {}, 0 -- простой bounded-cache
    end
    measureCacheCount = measureCacheCount + 1
    measureCache[key] = { w, h }
    return w, h
end

--- Измеряет многострочный текст (без wrap): max ширина строки, строки × высота.
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
-- Layout: word-wrap с переносом color-кодов
-- ---------------------------------------------------------------------

--- Последний активный #RRGGBB-код в строке (MTA color coding).
local function activeColorCode(s)
    local code = nil
    for c in s:gmatch("#%x%x%x%x%x%x") do code = c end
    return code
end

--- Word-wrap (§41): разбивает text на строки ≤ wrapWidth с переносом по
-- словам; слово шире wrapWidth жёстко разрезается (word break). Активный
-- #RRGGBB-код переносится в начало следующей строки (color coding).
-- Возвращает { lines = {...}, lineHeight, width, height }.
function Text.wrap(text, font, scale, wrapWidth)
    scale = scale or 1
    local _, lineHeight = measureLine("Ag", font, scale)
    local lines = {}

    if wrapWidth == nil or wrapWidth <= 0 then
        -- без wrap: просто разбить по \n
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
                    -- одно слово шире wrapWidth — жёсткий word break: режем
                    -- кусками ≤ wrapWidth, активный цвет переносится
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
                    -- не влезает: закрыть строку, перенести активный цвет
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

--- Ellipsis (§41): обрезает текст с "..." до maxWidth (одна строка).
function Text.ellipsis(text, font, scale, maxWidth)
    scale = scale or 1
    if text == nil or text == "" then return text end
    local w = measureLine(text, font, scale)
    if w <= maxWidth then return text end
    -- оценка: сколько символов влезает вместе с "..."
    local charW = w / #text
    local keep = math.floor((maxWidth - 3 * charW) / charW)
    if keep < 0 then keep = 0 end
    return text:sub(1, keep) .. "..."
end

--- Очистка кэша измерений (releaseResources).
function Text.clearCache()
    measureCache, measureCacheCount = {}, 0
end

DXUI.Text = Text