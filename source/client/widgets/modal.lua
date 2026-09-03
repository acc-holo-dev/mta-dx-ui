---Modal — dimmed full-screen overlay + centered dialog surface. Opening
---blocks input outside via the dispatcher modal stack.
---
---    local m = ui:modal({ width=300, height=200, children = { ... } })
---    m:open()          -- centered
---    m:on("close", function() afterClose() end)


DXUI = DXUI or {}

local Modal = DXUI.Widget:extend("Modal", {
    overlay = { default = 0x66000000, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    radius = { default = 12, invalidates = { DXUI.DIRTY.RENDER } },
    -- frosted backdrop (E5): strength > 0 blurs the world BEHIND the
    -- dialog rect before the surface (see render/effects.lua)
    backdropBlur = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    interactive = { default = true, invalidates = { DXUI.DIRTY.INPUT } },
})

DXUI.Part.declare(Modal, { "content" })

--- Creates the centered content part and hides the modal until opened.
Modal._build = function(node)
    node.visible = false
    -- overlay fills the screen
    node.layoutMode = "relative"
    node.layoutWidth = DXUI.percent(100)
    node.layoutHeight = DXUI.percent(100)
    local content = DXUI.Widget:new({})
    content.layoutMode = "center"
    content.layoutWidth = DXUI.percent(80)
    content.layoutHeight = DXUI.auto()
    content.padding = { left = 12, right = 12, top = 12, bottom = 12 }
    node:setPart("content", content)
end

--- Returns the content part.
function Modal:container()
    return self:getPart("content")
end

--- Shows the modal and pushes it onto the dispatcher modal stack.
function Modal:open()
    self.visible = true
    if self._context then
        self._context.layoutDirty = true
        self._context.interactiveDirty = true
        if self._context.dispatcher then
            self._context.dispatcher:openModal(self)
        end
    end
    return self
end

--- Hides the modal, removes it from the dispatcher modal stack, and emits
--- "close". Only THIS modal leaves the stack — other open modals survive.
function Modal:close()
    self.visible = false
    if self._context then
        self._context.layoutDirty = true
        self._context.renderDirty = true
        if self._context.dispatcher then
            self._context.dispatcher:closeModal(self)
        end
    end
    if self.emit then self:emit("close") end
    return self
end

--- Draws the dimmed overlay and the dialog surface.
function Modal:render(renderer)
    if not self.visible then return end
    local ui = self._context
    -- the overlay must cover the FULL screen, even in "fit" (letterbox)
    -- mode: convert screen-space extents back through the renderer mapping
    local sx = renderer.scaleX or 1
    local sy = renderer.scaleY or 1
    local ox = renderer.offsetX or 0
    local oy = renderer.offsetY or 0
    local sw = (ui and ui.screenW) or 0
    local sh = (ui and ui.screenH) or 0
    if sw > 0 and sh > 0 then
        renderer:rect(-ox / sx, -oy / sy, sw / sx, sh / sy, self.overlay)
    else
        -- fallback: design-space overlay (viewport not known yet)
        local lw = ui and (ui.layoutW or 800) or 800
        local lh = ui and (ui.layoutH or 600) or 600
        renderer:rect(0, 0, lw, lh, self.overlay)
    end
    -- frosted backdrop (E5) between the dim and the surface
    if self.backdropBlur and self.backdropBlur > 0 and DXUI.Effects
        and DXUI.Effects.renderBackdrop then
        DXUI.Effects.renderBackdrop(renderer, self, self.backdropBlur)
    end
    renderer:roundedRect(self.worldX, self.worldY, self.width, self.height,
        self.radius or 12, self.color)
end

DXUI.Builders.register("Modal", Modal)