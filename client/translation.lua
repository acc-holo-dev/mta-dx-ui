--[[
    translation.lua — DXUI

    Lightweight translation: locale dictionaries + key lookup with %1..%N
    substitution. Widgets bind a text property to a key via
    node:setTextKey(key, target) (Widget method) and re-apply on setLocale.

        DXUI.addLocale("ru", { ["menu.open"] = "Open" })
        DXUI.setLocale("ru")
        label:setTextKey("menu.open")   -- label.text = "Open"
]]

DXUI = DXUI or {}

DXUI._translations = DXUI._translations or {} -- lang -> { key = text }
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

function DXUI.getLocale()
    return DXUI.locale
end

--- Looks up key in the active locale; substitutions %1..%N applied.
-- Falls back to the key itself when missing.
function DXUI.tr(key, ...)
    local dict = DXUI._translations[DXUI.locale]
    local text = (dict and dict[key]) or key
    local n = select("#", ...)
    if n > 0 then
        for i = 1, n do
            text = text:gsub("%%" .. i, tostring((select(i, ...))))
        end
    end
    return text
end

--- Convenience alias: label:setTextKey("key") via tr().
DXUI._t = DXUI.tr
