--[[
    translation.lua — DXUI V3

    Lightweight translation: locale dictionaries + key lookup with %1..%N
    substitution. Widgets bind a text property to a key via
    node:setTextKey(key, target) (Widget method) and re-apply on setLocale.
]]

DXUI = DXUI or {}

-- lang -> { key = text }
DXUI._translations = DXUI._translations or {}
DXUI.locale = DXUI.locale or "en"

-- Weak registry of text-bound nodes (alive keys only)
DXUI._textBindings = setmetatable({}, { __mode = "k" })

--- Adds or merges a dictionary for a locale.
function DXUI.addLocale(lang, dict)
    local cur = DXUI._translations[lang]
    if not cur then cur = {}; DXUI._translations[lang] = cur end
    for k, v in pairs(dict) do cur[k] = v end
end

--- Sets the active locale and re-translates all bound nodes.
function DXUI.setLocale(lang)
    DXUI.locale = lang or "en"
    for node in pairs(DXUI._textBindings) do
        if node.applyTranslation and not node._destroyed then
            node:applyTranslation()
        else
            DXUI._textBindings[node] = nil
        end
    end
end

--- Returns the active locale.
function DXUI.getLocale()
    return DXUI.locale
end

--- Looks up key in the active locale; substitutions %1..%N applied.
-- Falls back to the key itself when missing. Single-pass gsub: arguments
-- with more than one digit (%10) resolve, and replacement text is inserted
-- literally (a "%" inside a value cannot corrupt the pattern).
function DXUI.tr(key, ...)
    local dict = DXUI._translations[DXUI.locale]
    local text = (dict and dict[key]) or key
    local n = select("#", ...)
    if n > 0 then
        local args = { ... }
        text = text:gsub("%%(%d+)", function(i)
            local v = args[tonumber(i)]
            if v ~= nil then return tostring(v) end
            -- unknown index: keep the original %N
            return nil
        end)
    end
    return text
end

DXUI._t = DXUI.tr