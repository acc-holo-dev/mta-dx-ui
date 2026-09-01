--[[
    widget.lua — DXUI V3

    BaseWidget — extends BaseNode with the widget contract:
      - visual traits: color, font, effects (capabilities, §36);
      - the render(renderer) contract — called by the render pass, never
        by the widget itself; primitives only (no DX access);
      - style/theme application with the user/system/theme owner guard
        (sparse overrides, §54);
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

local Widget = DXUI.Node:extend("Widget", {
    -- surface color (packed). Value object access: button.color.r = 255.
    color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- font handle (from ui:font(...), cached; nil = default).
    font = { default = nil, invalidates = { DIRTY.RENDER } },
    -- visual capabilities (optional, cheap when unset)
    blur  = { default = 0,         invalidates = { DIRTY.RENDER } },
    mask  = { default = nil,       invalidates = { DIRTY.RENDER } },
    effect = { default = nil,      invalidates = { DIRTY.RENDER } },
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
-- Style / theme application (§53-54): engine defaults -> global theme ->
-- resource theme -> component -> part role -> state -> instance override
-- -> explicit runtime override. Only non-user/system props are theme-owned.
-- ---------------------------------------------------------------------

--- Applies the full effective style (base + state override) to the node.
-- Reverts style-managed properties to their class defaults, then applies
-- the compiled component style and the current state override. Properties
-- explicitly set by the user are never overwritten (owner guard).
-- Early-out: with no style block, no state override and nothing applied
-- before, this writes NOTHING (hover toggling stays zero-cost).
function Widget:_applyStyleState()
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

    self._applyingTheme = true
    -- revert theme-managed properties to class defaults
    if applied then
        for k in pairs(applied) do
            local owner = self._owner and self._owner[k]
            if owner ~= "user" and owner ~= "system" then
                local spec = self._spec[k]
                if spec then self[k] = spec.default end
            end
        end
    end
    self._themeApplied = {}

    -- base component style (compiled: tokens resolved, transitions merged)
    if classStyle then
        local props = classStyle.props
        for k, v in pairs(props) do
            if STYLE_STATE_NAMES[k] == nil and self._spec[k] ~= nil then
                local owner = self._owner and self._owner[k]
                if owner ~= "user" and owner ~= "system" then
                    self[k] = v
                    self._themeApplied[k] = true
                end
            end
        end
    end
    -- state override
    if override then
        for k, v in pairs(override) do
            if self._spec[k] ~= nil then
                local owner = self._owner and self._owner[k]
                if owner ~= "user" and owner ~= "system" then
                    self[k] = v
                    self._themeApplied[k] = true
                end
            end
        end
    end
    self._applyingTheme = nil
end

--- Build-time: apply theme defaults (state is "normal" at build).
function Widget.applyThemeDefaults(node, props)
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
-- Window) to a translation key; re-applied on locale change.
function Widget:setTextKey(key, target)
    self._textKey = key
    self._textTarget = target or "text"
    if DXUI._textBindings then
        DXUI._textBindings[self] = true
    end
    self:applyTranslation()
    return self
end

function Widget:applyTranslation()
    if not self._textKey then return end
    local tr = DXUI.tr
    if not tr then return end
    local prop = self._textTarget or "text"
    self[prop] = tr(self._textKey)
    return self
end

-- ---------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------
DXUI.Widget = Widget