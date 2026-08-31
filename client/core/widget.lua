--[[
    widget.lua — DXUI V2

    Widget: base class of all widgets. Extends Node and adds the widget
    contract: create / render / input behavior / properties / events /
    destroy.

    A new widget is written WITHOUT touching core/kernel/storage/dispatcher —
    only through existing interfaces:

        local Widget = DXUI.Widget
        local Button = Widget:extend("Button", {
            text  = { default = "", invalidates = { DIRTY.RENDER } },
            color = { default = "#FFFFFF", invalidates = { DIRTY.RENDER } },
        })

        function Button:render(renderer)
            renderer:rect(self.x, self.y, self.width, self.height, self.color)
            if self.text ~= "" then
                renderer:text(self.text, self.x, self.y, self.width, self.height)
            end
        end

    render() — the drawing contract. Called by the renderer (Stage 3), not
    directly by the widget. In Stage 2 render() is a stub contract.
]]

DXUI = DXUI or {}

local DIRTY = DXUI.DIRTY

local Widget = DXUI.Node:extend("Widget", {
    -- Widget adds color as a first-class property (Node has none —
    -- color is a visual trait of a widget, not of the base node).
    -- transform resolves "#FFFFFF"/{r,g,b,a} into packed 0xAARRGGBB on write.
    color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER }, transform = DXUI.resolveColor },
    -- Stage 7b: font (handle from ui.font("Roboto", 12), cached; nil = default).
    font = { default = nil, invalidates = { DIRTY.RENDER } },
    -- Stage 10: node-level effects on ANY widget. Image renders with a
    -- direct shader (cheaper); the rest go through an RT-group (effect layer).
    blur = { default = 0, invalidates = { DIRTY.RENDER } },
    mask = { default = nil, invalidates = { DIRTY.RENDER } },
    -- M23: named effect (registered via DXUI.registerEffect).
    effect = { default = nil, invalidates = { DIRTY.RENDER } },
})

-- ---------------------------------------------------------------------
-- Render contract (renderer lands in Stage 3; here — a stub)
-- ---------------------------------------------------------------------

--- Renders the widget via the public renderer API.
-- Overridden by each concrete widget.
function Widget:render(renderer)
    -- Base widget draws nothing; concrete widgets override.
end

--- Stage 7b: measures content for autoSize — max extent of children
-- (local coords; layout pass calls before placement).
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
-- Events (minimal registry; full bubble system — Stage 4)
-- ---------------------------------------------------------------------

--- Subscribes to an event. fn(event). Returns self (chaining).
-- Listener lives on the node itself (node._listeners); EventBus.emit reads
-- it during bubbling. Works before the node is mounted in a context.
function Widget:on(eventName, fn)
    local listeners = self._listeners
    if not listeners then
        listeners = {}
        rawset(self, "_listeners", listeners)
    end
    local list = listeners[eventName]
    if not list then
        list = {}
        listeners[eventName] = list
    end
    list[#list + 1] = fn
    return self
end

--- Delivers an event starting at this node, bubbling up (Stage 4).
function Widget:emit(eventName, event)
    return DXUI.EventBus.emit(self, eventName, event)
end

--- Style change after creation: equivalent to assigning self.style —
--- both paths go through the single mutation layer.
function Widget:setStyle(name)
    self.style = name
    return self
end

--- Attaches props.children to the node (common helper for widget builders).
function Widget.attachChildren(node, props)
    local children = props and props.children
    if not children then return end
    for i = 1, #children do
        children[i]:setParent(node)
    end
end

-- ---------------------------------------------------------------------
-- M25: drag & drop (high-level)
-- ---------------------------------------------------------------------

--- Makes the node draggable: mousedown captures the pointer, the node
-- follows the cursor. Drop targets under the cursor get dragenter/dragleave;
-- on release a drop target (self or a descendant) gets "drop"
-- ({ node, data, x, y }) and the dragged node gets "dragend".
function Widget:setDraggable(v)
    self._draggable = v == true
    if self._draggable and not self._dndWired then
        self._dndWired = true
        local node = self
        node:on("mousedown", function(e)
            if e.button ~= "left" then return end
            if not node:isAlive() or not node._draggable then return end
            local dp = node.context and node.context.dispatcher
            if not dp then return end
            local startX, startY = node.x, node.y
            local mx, my = e.x, e.y
            dp:beginDrag(function(px, py)
                if not node:isAlive() then dp:endDrag() return end
                node:setPosition(startX + (px - mx), startY + (py - my))
            end, function(dropTarget, x, y)
                if not node:isAlive() then return end
                node:emit("dragend", { dropTarget = dropTarget, x = x, y = y })
                if dropTarget and dropTarget:isAlive() then
                    dropTarget:emit("drop", { node = node, data = node._dragData, x = x, y = y })
                end
            end)
        end)
    end
    return self
end

--- Marks the node as a drop target (drops land on it or its descendants).
function Widget:setDropTarget(v)
    self._dropTarget = v == true
    return self
end

--- Arbitrary payload carried by the drag (delivered in the "drop" event).
function Widget:setDragData(data)
    self._dragData = data
    return self
end

-- ---------------------------------------------------------------------
-- M25: translation (see translation.lua for the registry)
-- ---------------------------------------------------------------------

--- Binds the node's text (a property: "text" by default, e.g. "title" for
-- Window) to a translation key. Re-applies on locale change.
function Widget:setTextKey(key, target)
    local oldNode = DXUI._textBindings and self._textKey
    self._textKey = key
    self._textTarget = target or "text"
    if DXUI._textBindings then
        DXUI._textBindings[self] = true
    end
    self:applyTranslation()
    return self
end

--- Re-reads the current locale and updates the bound property.
function Widget:applyTranslation()
    if not self._textKey then return end
    local tr = DXUI.tr
    if not tr then return end -- translation.lua not loaded yet
    local prop = self._textTarget or "text"
    if self._textArgs then
        self[prop] = tr(self._textKey, self._textArgs)
    else
        self[prop] = tr(self._textKey)
    end
    return self
end

-- ---------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------
DXUI.Widget = Widget
