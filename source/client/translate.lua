---Locale dictionaries and live translation (DXUI.Translate).
---
---A dictionary maps keys to strings for one locale:
---
---    ui:addLocale("ru", { menu_save = "Сохранить" })
---
---Widgets bind their text to a key through the `textKey` property (or the
---`setTextKey(key, prop)` method — `prop` defaults to "text", e.g. "title"
---for a Window) and re-render automatically whenever the locale changes —
---no widget recreation needed.
---
---Locale resolution for a binding: the instance locale (see `ui:setLocale`)
---wins over the engine locale (see `DXUI.setLocale`). Lookup falls back to
---the locale's base language ("ru-RU" -> "ru") and then to the raw key.

DXUI = DXUI or {}

local Translate = {}
DXUI.Translate = Translate

--- lang -> { key = text }
Translate._dicts = {}

--- Active engine locale.
Translate.locale = "en"

--- Weak registry of bound nodes (alive keys only).
Translate._bindings = setmetatable({}, { __mode = "k" })

---Adds or merges a dictionary for a locale.
---@param lang string locale name ("en", "ru", "ru-RU", ...)
---@param dict table<string,string> key -> text
function Translate.addLocale(lang, dict)
    local cur = Translate._dicts[lang]
    if not cur then
        cur = {}
        Translate._dicts[lang] = cur
    end
    for k, v in pairs(dict) do cur[k] = v end
end

---Base language of a locale ("ru-RU" -> "ru"; "ru" -> "ru").
---@param lang string locale name
---@return string base
local function baseLocale(lang)
    return (lang:match("^([^-_]+)")) or lang
end

---Raw lookup with the fallback chain: exact locale -> base language -> key.
---@param lang string locale name
---@param key string translation key
---@return string text
function Translate.lookup(lang, key)
    local dicts = Translate._dicts
    local dict = dicts[lang]
    local text = dict and dict[key]
    if text == nil and lang then
        local base = baseLocale(lang)
        if base ~= lang then
            dict = dicts[base]
            text = dict and dict[key]
        end
    end
    if text == nil then return key end
    return text
end

---Substitutes %1..%N placeholders. Single-pass gsub: multi-digit indexes
---(%10) resolve, and replacement text is inserted literally (a "%" inside
---a value cannot corrupt the pattern).
---@param text string template
---@param ... string|number values
---@return string result
local function substitute(text, ...)
    local n = select("#", ...)
    if n == 0 then return text end
    local args = { ... }
    return (text:gsub("%%(%d+)", function(i)
        local v = args[tonumber(i)]
        if v ~= nil then return tostring(v) end
        -- unknown index: keep the original %N
        return nil
    end))
end

---Translates a key in the ACTIVE engine locale, substituting %1..%N.
---@param key string translation key
---@param ... string|number substitution values
---@return string text
function Translate.tr(key, ...)
    return substitute(Translate.lookup(Translate.locale, key), ...)
end

---Translates a key in an EXPLICIT locale (nil = the engine locale),
---substituting %1..%N.
---@param locale? string locale name
---@param key string translation key
---@param ... string|number substitution values
---@return string text
function Translate.trFor(locale, key, ...)
    return substitute(Translate.lookup(locale or Translate.locale, key), ...)
end

---Re-applies every binding whose node belongs to `instance` (nil = all).
---Dead/foreign entries are dropped from the weak registry.
---@param instance? table UI instance to scope the re-apply to
function Translate.applyFor(instance)
    for node in pairs(Translate._bindings) do
        if instance and node._context ~= instance then
            -- another instance's binding: untouched by this switch
        elseif node.applyTranslation and not node._destroyed then
            node:applyTranslation()
        else
            Translate._bindings[node] = nil
        end
    end
end

---Sets the ENGINE locale and re-translates every bound node. Emits
---"localeChange" on each tracked UI root (see ui:on).
---@param lang string locale name
function Translate.setLocale(lang)
    Translate.locale = lang or "en"
    Translate.applyFor(nil)
    local uis = DXUI._uis
    if uis then
        for i = 1, #uis do
            local root = uis[i] and uis[i].root
            if root and root.emit then root:emit("localeChange", Translate.locale) end
        end
    end
end

---Returns the active engine locale.
---@return string locale
function Translate.getLocale()
    return Translate.locale
end

-- Engine-level aliases (the historical public names).
DXUI.addLocale = Translate.addLocale
DXUI.setLocale = Translate.setLocale
DXUI.getLocale = Translate.getLocale
DXUI.tr = Translate.tr
DXUI._translations = Translate._dicts
DXUI._textBindings = Translate._bindings