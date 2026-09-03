---Locale dictionaries and live translation (DXUI.Translate).
---
---A dictionary maps keys to values for one locale. A value may be:
---
---  - a plain string:   menu_save = "Сохранить"
---  - a plural table:  items = { one = "%1 элемент", few = "%1 элемента",
---                          many = "%1 элементов" }   (en: one/other)
---  - a font entry:    title = { text = "Заголовок", font = "Roboto.ttf:12" }
---
---Widgets bind their text to a key through the `textKey` property (or the
---`setTextKey(key, prop)` method — `prop` defaults to "text", e.g. "title"
---for a Window) and re-render automatically whenever the locale changes —
---no widget recreation needed.
---
---tr(key, n) with a NUMBER first substitution picks the CLDR-ish plural
---form for that count (see pluralFor: ru — one/few/many, en — one/other)
---before substituting. Per-locale fonts resolve through the shared font
---cache ("path:size[:quality]" systemFont specs — see widgets/edit.lua
---applyTranslation, the consumer side).
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

--- Whether a dictionary value is a plural table ({one|few|many|other}).
local function isPluralTable(v)
    return type(v) == "table"
        and (v.other ~= nil or v.many ~= nil or v.one ~= nil or v.few ~= nil)
end

---CLDR-ish plural form for a count: ru — one/few/many; en — one/other;
---any other language — "other". Declarative rules only, no loadstring.
---@param locale? string locale name (nil = the engine locale)
---@param n number count
---@return string "one"|"few"|"many"|"other"
function Translate.pluralFor(locale, n)
    local base = baseLocale(locale or Translate.locale or "en")
    n = math.floor(math.abs(tonumber(n) or 0))
    if base == "ru" then
        local n10, n100 = n % 10, n % 100
        if n10 == 1 and n100 ~= 11 then return "one" end
        if n10 >= 2 and n10 <= 4 and (n100 < 10 or n100 >= 20) then return "few" end
        return "many"
    end
    if base == "en" then
        return (n == 1) and "one" or "other"
    end
    return "other"
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
---A NUMBER first substitution picks the plural form when the value is a
---plural table (see pluralFor).
---@param key string translation key
---@param ... string|number substitution values
---@return string text
function Translate.tr(key, ...)
    return Translate.trFor(nil, key, ...)
end

---Translates a key in an EXPLICIT locale (nil = the engine locale),
---substituting %1..%N. A NUMBER first substitution with a plural-table
---value picks the CLDR-ish form for that count; {text=…, font=…} entries
---translate as .text.
---@param locale? string locale name
---@param key string translation key
---@param ... string|number substitution values (a leading NUMBER drives
---       the plural form)
---@return string text
function Translate.trFor(locale, key, ...)
    local raw = Translate.lookup(locale or Translate.locale, key)
    local text = raw
    if type(raw) == "table" then
        local n = select(1, ...)
        if isPluralTable(raw) then
            if type(n) == "number" then
                local form = Translate.pluralFor(locale, n)
                text = raw[form] or raw.other or raw.many or raw.one or raw.few or key
            else
                -- plural table used without a count: the neutral form
                text = raw.other or raw.many or raw.one or raw.few or key
            end
        else
            text = raw.text or key
        end
    end
    if text == nil then text = key end
    if type(text) ~= "string" then text = tostring(text) end
    return substitute(text, ...)
end

---Re-applies every binding whose node belongs to `instance` (nil = all).
---Dead/foreign entries are dropped from the weak registry.
---@param instance? table UI instance to scope the re-apply to
function Translate.applyFor(instance)
    for node in pairs(Translate._bindings) do
        if instance and node._context ~= instance then
            -- another instance's binding: untouched by this switch
        elseif node.applyTranslation and not node._destroyed then
            -- one failing binding must not abort the whole re-translate pass
            local ok, err = pcall(node.applyTranslation, node)
            if not ok then
                Translate._bindings[node] = nil
                DXUI._warn("applyTranslation failed: " .. tostring(err))
            end
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