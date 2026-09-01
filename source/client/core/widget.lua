--[[
    widget.lua — DXUI V3

    BaseWidget — extends BaseNode with the widget contract:
      - visual traits: color, font, effects (capabilities);
      - the render(renderer) contract — called by the render pass, never
        by the widget itself; primitives only (no DX access);
      - style/theme application with the user/system/theme owner guard
        (sparse overrides);
      - content measurement for autoSize;
      - translation binding.

    A new widget is written WITHOUT touching core/kernel:

        local Button = DXUI.Widget:extend("Button", {
            text = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
        })
        function Button:render(renderer)
            renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
            ...
        end
]]

DXUI = DXUI or {}

local DIRTY = DXUI.DIRTY

--- onSet hook for the textKey property: registers the binding in the weak
-- registry (translate.lua owns it) and applies the translation at once.
local function onTextKeySet(node, value)
    if value == nil then return end
    local Translate = DXUI.Translate
    if Translate and Translate._bindings then
        Translate._bindings[node] = true
    end
    node._textTarget = node._textTarget or "text"
    if node.applyTranslation then node:applyTranslation() end
end

local Widget = DXUI.Node:extend("Widget", {
    -- surface color (packed). Value object access: button.color.r = 255.
    color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- font handle (from ui:font(...), cached; nil = default). A font change
    -- alters measured text size, so it invalidates layout too.
    font = { default = nil, invalidates = { DIRTY.RENDER, DIRTY.LAYOUT } },
    -- visual capabilities (optional, cheap when unset)
    blur  = { default = 0,         invalidates = { DIRTY.RENDER } },
    mask  = { default = nil,       invalidates = { DIRTY.RENDER } },
    effect = { default = nil,      invalidates = { DIRTY.RENDER } },
    -- translation key: writing it binds the widget's text (see setTextKey
    -- for the target-property form) and re-renders on every locale change
    textKey = { default = nil, onSet = onTextKeySet },
})

-- State names recognized as state overrides inside a style block.
local STYLE_STATE_NAMES = { hover = true, pressed = true, focused = true, selected = true, disabled = true }

-- ---------------------------------------------------------------------
-- Render contract
-- ---------------------------------------------------------------------

--- Renders the widget via the public renderer API. Overridden per widget.
function Widget:render(renderer)
    -- base widget draws nothing
end

--- Color: pack/unpack via value objects. Accepts int | "#hex" | table.
function Widget:setColor(c)
    self:_set("color", DXUI.resolveColor(c))
    return self
end
--- Returns the packed color int.
function Widget:getColor()
    return DXUI.ColorToInt(self._data.color)
end

--- Measures content for autoSize: max extent of children (local coords).
-- Label overrides with text measurement.
function Widget:_measureContent()
    local mx, my = 0, 0
    local children = self._children
    for i = 1, #children do
        local c = children[i]
        local x2 = c.x + c.width
        local y2 = c.y + c.height
        if x2 > mx then mx = x2 end
        if y2 > my then my = y2 end
    end
    return mx, my
end

-- ---------------------------------------------------------------------
-- Style / theme application: engine defaults -> global theme ->
-- resource theme -> component -> part role -> state -> instance override
-- -> explicit runtime override. Only non-user/system props are theme-owned.
-- ---------------------------------------------------------------------

--- Applies the full effective style (base + state override) to the node.
--- `animate` is true only for VISUAL-STATE changes on a live node: when the
--- component declares `transition = { duration, easing }`, differing
--- animatable props (numbers, colors — per channel) tween through the
--- instance Anim layer with the "theme" owner. Construction, theme
--- switches and style changes apply instantly. Properties explicitly set
--- by the user are never overwritten (owner guard). Early-out: with no
--- style block, no state override and nothing applied before, this writes
--- NOTHING (hover toggling stays zero-cost).
function Widget:_applyStyleState(animate)
    if self._destroyed then return end
    local classStyle = DXUI.Theme and DXUI.Theme.getComponentStyle(
        self._class._name, self.style) or nil
    -- disabled wins over any explicit state (enabled is structural)
    local state = (self.enabled == false) and "disabled" or (self._state or "normal")
    local override = (state ~= "normal") and classStyle and classStyle.states[state] or nil
    local applied = self._themeApplied

    if not classStyle and not override and not (applied and next(applied)) then
        return
    end

    -- effective target map: component base merged with the state override
    -- (one pass, no write when the value is already correct)
    local target = nil
    if classStyle then
        target = {}
        local props = classStyle.props
        for k, v in pairs(props) do
            if STYLE_STATE_NAMES[k] == nil then target[k] = v end
        end
    end
    if override then
        if not target then target = {} end
        for k, v in pairs(override) do target[k] = v end
    end

    -- transitions: state changes on a live, animatable node only
    local transition = nil
    if animate and target and classStyle and classStyle.transition then
        local duration = tonumber(classStyle.transition.duration) or 0
        if duration > 0 and self._context and self._context.anim then
            transition = classStyle.transition
        end
    end

    self._applyingTheme = true
    -- revert theme-managed properties that are no longer themed
    if applied then
        for k in pairs(applied) do
            if not (target and target[k] ~= nil) then
                local owner = self._owner and self._owner[k]
                if owner ~= "user" and owner ~= "system" then
                    local spec = self._spec[k]
                    if spec then self[k] = spec.default end
                end
            end
        end
    end
    self._themeApplied = {}

    if target then
        for k, v in pairs(target) do
            if self._spec[k] ~= nil then
                local owner = self._owner and self._owner[k]
                if owner ~= "user" and owner ~= "system" then
                    local current = self._data[k]
                    if transition and type(v) == "number" and type(current) == "number"
                        and current ~= v then
                        -- tween via the Anim layer; the "theme" owner keeps
                        -- the prop tracked for the next theme switch
                        local easings = DXUI.Easing or {}
                        local ease = easings[transition.easing] or easings.out
                        self._themeApplied[k] = true
                        self._context.anim:_startStep(self, { [k] = v },
                            transition.duration, ease, nil, "theme")
                    else
                        self[k] = v
                        self._themeApplied[k] = true
                    end
                end
            end
        end
    end
    self._applyingTheme = nil
end

--- Build-time: apply theme defaults (state is "normal" at build).
function Widget.applyThemeDefaults(node)
    if node._class and node._class._applyStyleState then
        node:_applyStyleState()
    end
end

--- Re-applies the node's CURRENT style (node.style = "primary" path).
function Widget.applyStyle(node)
    if node._class and node._class._applyStyleState then
        node:_applyStyleState()
    end
end

--- onSet hook for the style property (wired from node.lua).
function Widget._onStyleSet(node, styleName)
    if node._building then return end
    if node._class and node._class._applyStyleState then
        node:_applyStyleState()
    end
end

--- Attaches props.children to the node (widget builder helper).
function Widget.attachChildren(node, props)
    local children = props and props.children
    if not children then return end
    for i = 1, #children do
        children[i]:setParent(node)
    end
end

-- ---------------------------------------------------------------------
-- Translation binding (see translation.lua for the registry)
-- ---------------------------------------------------------------------

--- Binds the node's text property ("text" by default, e.g. "title" for
-- Window) to a translation key; sugar over the textKey property. Re-applied
-- on every locale change.
function Widget:setTextKey(key, target)
    if target then self._textTarget = target end
    self:_set("textKey", key)
    return self
end

--- Applies the bound translation key to the text property. The instance
-- locale (ui:setLocale) wins over the engine locale (DXUI.setLocale).
function Widget:applyTranslation()
    local key = self.textKey
    if key == nil then return end
    local Translate = DXUI.Translate
    if not Translate then return end
    local context = self._context
    local locale = (context and context._locale) or Translate.locale
    local text = Translate.trFor(locale, key)
    local prop = self._textTarget or "text"
    if self._spec[prop] then self[prop] = text end
    return self
end

-- ---------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------
DXUI.Widget = Widget