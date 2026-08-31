--[[
    window.lua — DXUI V2

    Window: a composite widget. One logical object for the user; internally a
    frame (the node itself) + title bar + title text (drawn in render) +
    close button (a separate interactive child).

    Public API: setTitle/getTitle/setClosable/close/setModal/setDraggable.
    The "close" event is preventable (e:preventDefault() cancels the destroy).

    Stage 7: drag (via the title bar through dispatcher capture), modal (overlay +
    focus lock + input trap).
]]

DXUI = DXUI or {}

local BAR_H = 24      -- title bar height
local CLOSE_W = 16
local CLOSE_H = 16
local MODAL_OVERLAY_COLOR = 0x80000000

local Window = DXUI.Widget:extend("Window", {
    title = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    titleBarColor = { default = 0xFF334455, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    titleTextColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    closable = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    draggable = { default = false, invalidates = {} },
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } }, -- Stage 9: rounded corners
})

function Window:render(renderer)
    -- frame
    if self.radius > 0 then
        renderer:roundedRect(self.worldX, self.worldY, self.width, self.height, self.radius, self.color)
    else
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end
    -- title bar + title text (drawn here, not as separate nodes)
    if self.title ~= "" or self.closable then
        renderer:rect(self.worldX, self.worldY, self.width, BAR_H, self.titleBarColor)
        if self.title ~= "" then
            renderer:text(self.title, self.worldX + 4, self.worldY + 2, self.width - 8, BAR_H - 4, self.titleTextColor)
        end
    end
end

function Window:setTitle(text)
    self.title = text
    return self
end

function Window:getTitle()
    return self.title
end

function Window:setClosable(v)
    self.closable = v == true
    if self.closable then self:_ensureCloseButton() end
    if self._closeButton then
        self._closeButton.visible = self.closable
    end
    return self
end

--- Creates the close button lazily (at build or on later setClosable(true)).
-- The button is a separate interactive child anchored to the top-right
-- corner via relative layout + anchor TR (follows the size).
function Window:_ensureCloseButton()
    if self._closeButton then return self end
    local k = self._context
    if not k or self._destroyed then return self end
    local closeBtn = DXUI.Button.build(k, {
        layoutMode = "relative",
        x = 1, y = 0,
        anchor = "tr",
        width = CLOSE_W, height = CLOSE_H,
        text = "x",
        color = 0xFFFF6060,
    })
    closeBtn:setParent(self)
    closeBtn:on("click", function() self:close() end)
    rawset(self, "_closeButton", closeBtn)
    return self
end

function Window:setDraggable(v)
    self.draggable = v == true
    return self
end

--- Close request. The "close" event bubbles; a listener can cancel the
-- destroy via event:preventDefault(). By default — destroy.
function Window:close()
    if self._destroyed then return self end
    local event = self:emit("close", {})
    if not event.defaultPrevented and not self.destroyed then
        self:destroy()
    end
    return self
end

-- ---------------------------------------------------------------------
-- Modal: overlay + focus lock + input trap
-- ---------------------------------------------------------------------

function Window:setModal(v)
    local k = self._context
    if not k then return self end
    local enable = (v ~= false and v ~= nil)

    if enable then
        if self._modal then return self end

        -- window + subtree in LAYER_MODAL (children inherit the layer via setParent)
        self.layer = DXUI.LAYER.MODAL

        -- overlay (background dim), root node. stretch-layout: size follows
        -- the layout space (design resolution / screen); the layout pass
        -- restores it when the resolution changes
        local overlay = k:panel({
            layoutMode = "stretch",
            color = MODAL_OVERLAY_COLOR,
            layer = DXUI.LAYER.MODAL,
            zIndex = 0,
        })
        overlay:setParent(k.root)
        self.zIndex = 1 -- window above overlay (inside the MODAL layer)

        -- register in the dispatcher (focus lock + input trap)
        k.dispatcher:pushModal(self, overlay)
        self._modal = { overlay = overlay, dismissOnClickOutside = (type(v) == "table" and v.dismissOnClickOutside == true) }

        if self._modal.dismissOnClickOutside then
            overlay:on("click", function() self:close() end)
        end

        -- auto-focus the window
        k:setFocus(self)
    else
        if not self._modal then return self end
        k.dispatcher:popModal(self)
        if self._modal.overlay and self._modal.overlay:isAlive() then
            self._modal.overlay:destroy()
        end
        self._modal = nil
        self.layer = DXUI.LAYER.BASE
        self.zIndex = 0
    end
    return self
end

--- Clear modal state on destroy (overlay + dispatcher stack).
function Window:_onDestroy()
    if self._modal then
        self:setModal(false)
    end
end

--- Builder: ui:window({ title=, closable=, draggable=, modal=, onClose=,
-- x=, y=, width=, height=, color=, children=, ... }).
function Window.build(context, props)
    props = props or {}
    local node = Window:new(props)
    -- composite parts (setModal) need the context before mounting
    rawset(node, "_context", context)
    if props.width == nil then node.width = 320 end
    if props.height == nil then node.height = 240 end
    if props.onClose then node:on("close", props.onClose) end

    -- close button: a separate interactive child anchored to the top-right
    -- corner via relative layout + anchor TR (follows the size).
    if props.closable then
        node:_ensureCloseButton()
    end

    -- drag via the title bar (Stage 7)
    if props.draggable then
        node.draggable = true
        node:on("mousedown", function(e)
            if e.button ~= "left" then return end
            if not node:isAlive() or not node.draggable then return end
            -- drag only on the title bar (the top strip)
            local localY = e.y - node.worldY
            if localY > BAR_H then return end
            local grabDX = e.x - node.worldX
            local grabDY = e.y - node.worldY
            context.dispatcher:beginDrag(function(px, py)
                if not node:isAlive() then return end
                node:setPosition(px - grabDX, py - grabDY)
            end)
            node:bringToFront()
        end)
    end

    if props.modal then node:setModal(props.modal) end

    DXUI.Widget.attachChildren(node, props)
    return node
end

DXUI.Window = Window
