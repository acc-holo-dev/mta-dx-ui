--[[
    theme.lua — DXUI

    Style/theme system. Global theme + per-node style + state matrix.

        DXUI.setTheme({
            Button = {
                default = {
                    color = "#444444", textColor = "#FFFFFF",
                    hover    = { color = "#5588BB" },
                    pressed  = { color = "#3A6EA5" },
                    disabled = { color = "#333333" },
                },
                primary = { color = "#3A6EA5", hover = { color = "#5588BB" } },
            },
        })

        ui:button({ text = "OK" })                    -- style "default"
        ui:button({ text = "OK", style = "primary" }) -- style "primary"

    State matrix: inside a style block, keys "hover"/"pressed"/"focused"/
    "disabled" are state overrides applied on top of the base properties when
    the node's state matches. State priority: disabled > pressed > hover >
    focused > normal. State is tracked centrally by the dispatcher (hover/
    pressed/focused) and the enabled property (disabled).

    Resolution happens on invalidation (not every frame): _applyStyleState
    reverts style-managed properties to class defaults, then applies base +
    state override. _userSet guard: properties set explicitly by the user are
    never overwritten by the theme.
]]

DXUI = DXUI or {}

-- State names recognized as state overrides inside a style block.
local STATE_NAMES = { hover = true, pressed = true, focused = true, disabled = true }

--- Sets the global theme and re-applies it to all existing nodes.
function DXUI.setTheme(theme)
    DXUI.theme = theme
    local contexts = DXUI._contexts
    if contexts then
        for i = 1, #contexts do
            DXUI._reapplyTheme(contexts[i].root)
        end
    end
end

--- Recursively re-applies the theme to a node and its subtree.
function DXUI._reapplyTheme(node)
    if DXUI.Widget and DXUI.Widget._applyStyleState then
        DXUI.Widget._applyStyleState(node)
    end
    local children = node._children
    for i = 1, #children do
        DXUI._reapplyTheme(children[i])
    end
end

--- Returns the style block for a class + style name (or inline table).
function DXUI.getStyle(className, styleName)
    if type(styleName) == "table" then return styleName end
    local t = DXUI.theme
    if not t then return nil end
    local classTheme = t[className]
    if not classTheme then return nil end
    return classTheme[styleName or "default"]
end

--- Applies the full effective style (base + state override) to a node.
-- Reverts all style-managed properties to class defaults, then applies the
-- base style (skipping state keys) and the current state override.
function DXUI.Widget._applyStyleState(node)
    if node._destroyed then return end
    local block = DXUI.getStyle(node._class._name, node.style)
    local state = node._state or "normal"
    local override = (state ~= "normal") and block and block[state] or nil

    node._applyingTheme = true
    -- revert style-managed properties to class defaults
    local applied = node._themeApplied
    if applied then
        for k in pairs(applied) do
            if not node._userSet[k] then
                local spec = node._spec[k]
                if spec then node[k] = spec.default end
            end
        end
    end
    node._themeApplied = {}
    -- apply base style
    if block then
        for k, v in pairs(block) do
            if not STATE_NAMES[k] and node._spec[k] ~= nil and not node._userSet[k] then
                node[k] = v
                node._themeApplied[k] = true
            end
        end
    end
    -- apply state override
    if override then
        for k, v in pairs(override) do
            if node._spec[k] ~= nil and not node._userSet[k] then
                node[k] = v
                node._themeApplied[k] = true
            end
        end
    end
    node._applyingTheme = nil
end

--- Build-time: apply theme defaults (state is "normal" at build).
function DXUI.Widget.applyThemeDefaults(node, props)
    DXUI.Widget._applyStyleState(node)
end

--- Runtime style switch (node.style = "primary").
function DXUI.Widget.applyStyle(node, styleName)
    DXUI.Widget._applyStyleState(node)
end

--- onSet hook for the style property: apply style after creation.
function DXUI.Widget._onStyleSet(node, styleName)
    if node._building then return end
    DXUI.Widget._applyStyleState(node)
end
