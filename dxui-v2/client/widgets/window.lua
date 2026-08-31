--[[
    window.lua — DXUI V2

    Window: composite-виджет (§16/§17). Один логический объект для
    пользователя; внутри — frame (сам узел) + title bar + title text
    (рисуются в render) + close button (отдельный интерактивный child).

    Публичный API: setTitle/getTitle/setClosable/close/setModal/setDraggable.
    Событие "close" preventable (e:preventDefault() отменяет destroy).

    Stage 7: drag (по title bar через dispatcher capture), modal (overlay +
    focus lock + input trap, §60).
]]

DXUI = DXUI or {}

local BAR_H = 24      -- высота title bar
local CLOSE_W = 16
local CLOSE_H = 16
local MODAL_OVERLAY_COLOR = 0x80000000

local Window = DXUI.Widget:extend("Window", {
    title = { default = "", invalidates = { DXUI.DIRTY.RENDER } },
    titleBarColor = { default = 0xFF334455, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    titleTextColor = { default = 0xFFFFFFFF, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    closable = { default = false, invalidates = { DXUI.DIRTY.RENDER } },
    draggable = { default = false, invalidates = {} },
    radius = { default = 0, invalidates = { DXUI.DIRTY.RENDER } }, -- Stage 9 (§37)
})

function Window:render(renderer)
    -- frame
    if self.radius > 0 then
        renderer:roundedRect(self.worldX, self.worldY, self.width, self.height, self.radius, self.color)
    else
        renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
    end
    -- title bar + title text (рисуются здесь, не отдельными узлами)
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
    self.closable = v
    if self._closeButton then
        self._closeButton.visible = v
    end
    return self
end

function Window:setDraggable(v)
    self.draggable = v == true
    return self
end

--- Запрос закрытия. Событие "close" бабблится; слушатель может отменить
-- destroy через event:preventDefault(). По умолчанию — destroy.
function Window:close()
    if self._destroyed then return self end
    local event = self:emit("close", {})
    if not event.defaultPrevented and not self.destroyed then
        self:destroy()
    end
    return self
end

-- ---------------------------------------------------------------------
-- Modal (§60): overlay + focus lock + input trap
-- ---------------------------------------------------------------------

function Window:setModal(v)
    local k = self._context
    if not k then return self end
    local enable = (v ~= false and v ~= nil)

    if enable then
        if self._modal then return self end

        -- окно + поддерево в LAYER_MODAL (дети наследуют слой через setParent)
        self.layer = DXUI.LAYER.MODAL

        -- overlay (затемнение фона), root-узел. stretch-layout: размер
        -- следует за layout-пространством (design resolution / экран,
        -- §31–§33) — при смене разрешения восстанавливается layout-проходом
        local overlay = k:panel({
            layoutMode = "stretch",
            color = MODAL_OVERLAY_COLOR,
            layer = DXUI.LAYER.MODAL,
            zIndex = 0,
        })
        overlay:setParent(k.root)
        self.zIndex = 1 -- окно выше overlay (внутри MODAL-слоя)

        -- регистрация в dispatcher (focus lock + input trap)
        k.dispatcher:pushModal(self, overlay)
        self._modal = { overlay = overlay, dismissOnClickOutside = (type(v) == "table" and v.dismissOnClickOutside == true) }

        if self._modal.dismissOnClickOutside then
            overlay:on("click", function() self:close() end)
        end

        -- авто-фокус на окно
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

--- Очистка modal-состояния при destroy (overlay + dispatcher-стек).
function Window:_onDestroy()
    if self._modal then
        self:setModal(false)
    end
end

--- Билдер: ui:window({ title=, closable=, draggable=, modal=, onClose=,
-- x=, y=, width=, height=, color=, children=, ... }).
function Window.build(context, props)
    props = props or {}
    local node = Window:new(props)
    -- composite-частям (setModal) нужен контекст ещё до монтирования
    rawset(node, "_context", context)
    if props.width == nil then node.width = 320 end
    if props.height == nil then node.height = 240 end
    if props.onClose then node:on("close", props.onClose) end

    -- close button: отдельный интерактивный child, привязан к правому
    -- верхнему углу через relative layout + anchor TR (следует за размером).
    if props.closable then
        local closeBtn = DXUI.Button.build(context, {
            layoutMode = "relative",
            x = 1, y = 0,
            anchor = "tr",
            width = CLOSE_W, height = CLOSE_H,
            text = "x",
            color = 0xFFFF6060,
        })
        closeBtn:setParent(node)
        closeBtn:on("click", function() node:close() end)
        node._closeButton = closeBtn
    end

    -- drag по title bar (Stage 7)
    if props.draggable then
        node.draggable = true
        node:on("mousedown", function(e)
            if e.button ~= "left" then return end
            if not node:isAlive() or not node.draggable then return end
            -- drag только по title bar (верхняя полоса)
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
