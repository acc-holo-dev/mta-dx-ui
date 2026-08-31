--[[
    scrollpanel.lua — DXUI V2

    ScrollPanel: прокручиваемый контейнер (§61 — virtualization позже).

    Composite (один объект для пользователя):
      * viewport — сам узел (clip=true, визуальная граница);
      * content  — невидимый контейнер (plain Node без render), позиционируется
                   на (-scrollX, -scrollY); пользовательские дети — сюда;
      * track/thumb — полосы прокрутки (опционально).

    Скроллинг смещает content; дети «выезжают» через clip-регион viewport'а
    (geometric clip, Stage 7). Не пересчитываем дерево.

    props: axis ("v"|"h"|"both", default "v"), scrollbar (bool), wheelStep,
           contentW/contentH (явный размер), children (в content).
]]

DXUI = DXUI or {}

local TRACK_W = 8    -- толщина вертикальной / высота горизонтальной полосы
local THUMB_MIN = 20 -- минимальный размер thumb
local WHEEL_STEP = 40

local ScrollPanel = DXUI.Widget:extend("ScrollPanel", {
    axis = { default = "v", invalidates = {} },
    scrollX = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    scrollY = { default = 0, invalidates = { DXUI.DIRTY.RENDER } },
    scrollbarTrackColor = { default = 0xFF303040, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    scrollbarThumbColor = { default = 0xFF808090, invalidates = { DXUI.DIRTY.RENDER }, transform = DXUI.resolveColor },
    clip = { default = true, invalidates = { DXUI.DIRTY.RENDER, DXUI.DIRTY.INPUT } },
})

function ScrollPanel:render(renderer)
    renderer:rect(self.worldX, self.worldY, self.width, self.height, self.color)
end

-- ---------------------------------------------------------------------
-- Внутренние: content size / scrollbar layout
-- ---------------------------------------------------------------------

function ScrollPanel:_contentSize()
    if self._contentW and self._contentH then
        return self._contentW, self._contentH
    end
    local content = self._content
    if not content then return self.width, self.height end
    local mx, my = 0, 0
    local children = content._children
    for i = 1, #children do
        local c = children[i]
        local cx2 = c.x + c.width
        local cy2 = c.y + c.height
        if cx2 > mx then mx = cx2 end
        if cy2 > my then my = cy2 end
    end
    return (mx > 0 and mx or self.width), (my > 0 and my or self.height)
end

function ScrollPanel:_layoutScrollbars()
    local vw, vh = self.width, self.height
    local cw, ch = self:_contentSize()
    local maxX, maxY = cw - vw, ch - vh
    if maxX < 0 then maxX = 0 end
    if maxY < 0 then maxY = 0 end
    self._maxX, self._maxY = maxX, maxY

    local axis = self.axis
    if self._trackV then
        local showV = maxY > 0 and (axis == "v" or axis == "both")
        self._trackV.visible = showV
        self._thumbV.visible = showV
        if showV then
            self._trackV:setPosition(vw - TRACK_W, 0)
            self._trackV:setSize(TRACK_W, vh)
            local thumbH = math.max(THUMB_MIN, math.floor(vh * vh / ch))
            local t = maxY > 0 and (self.scrollY / maxY) or 0
            self._thumbV:setSize(TRACK_W - 2, thumbH)
            self._thumbV:setPosition(1, math.floor(t * (vh - thumbH)))
        end
    end
    if self._trackH then
        local showH = maxX > 0 and (axis == "h" or axis == "both")
        self._trackH.visible = showH
        self._thumbH.visible = showH
        if showH then
            self._trackH:setPosition(0, vh - TRACK_W)
            self._trackH:setSize(vw, TRACK_W)
            local thumbW = math.max(THUMB_MIN, math.floor(vw * vw / cw))
            local t = maxX > 0 and (self.scrollX / maxX) or 0
            self._thumbH:setSize(thumbW, TRACK_W - 2)
            self._thumbH:setPosition(math.floor(t * (vw - thumbW)), 1)
        end
    end
end

-- ---------------------------------------------------------------------
-- Публичный API
-- ---------------------------------------------------------------------

function ScrollPanel:setScroll(x, y)
    self:_layoutScrollbars()
    if x < 0 then x = 0 elseif x > self._maxX then x = self._maxX end
    if y < 0 then y = 0 elseif y > self._maxY then y = self._maxY end
    self.scrollX = x
    self.scrollY = y
    if self._content then
        self._content:setPosition(-x, -y)
    end
    self:_layoutScrollbars()
    self:emit("scroll", { x = x, y = y })
    return self
end

function ScrollPanel:getScroll()
    return self.scrollX, self.scrollY
end

function ScrollPanel:getScrollMax()
    return self._maxX, self._maxY
end

function ScrollPanel:scrollBy(dx, dy)
    return self:setScroll(self.scrollX + dx, self.scrollY + dy)
end

function ScrollPanel:scrollToPercent(px, py)
    return self:setScroll(px * self._maxX, py * self._maxY)
end

--- Явный размер контента (nil = auto-measure по детям).
function ScrollPanel:setContentSize(w, h)
    self._contentW = w
    self._contentH = h
    return self:refresh()
end

--- Контент-узел (для ручного прикрепления детей).
function ScrollPanel:getContent()
    return self._content
end

function ScrollPanel:refresh()
    return self:setScroll(self.scrollX, self.scrollY)
end

--- Override setSize: переразложить полосы + clamp scroll.
function ScrollPanel:setSize(w, h)
    DXUI.Node.setSize(self, w, h)
    return self:refresh()
end

-- ---------------------------------------------------------------------
-- Билдер
-- ---------------------------------------------------------------------

local function buildScrollbar(context, parent, axis)
    local track = context:panel({})
    track:setParent(parent)
    track.color = 0xFF303040
    track.zIndex = 10
    track.visible = false
    local thumb = context:panel({})
    thumb:setParent(track)
    thumb.color = 0xFF808090
    thumb.zIndex = 11
    return track, thumb
end

local function wireThumbDrag(context, sp, thumb, isVertical)
    thumb:on("mousedown", function(e)
        if e.button ~= "left" then return end
        if not sp:isAlive() then return end
        local startScroll = isVertical and sp.scrollY or sp.scrollX
        local startPos = isVertical and e.y or e.x
        context.dispatcher:beginDrag(function(px, py)
            if not sp:isAlive() then return end
            local nowPos = isVertical and py or px
            local delta = nowPos - startPos
            local trackLen = isVertical and sp.height or sp.width
            local thumbLen = isVertical and sp._thumbV.height or sp._thumbH.width
            local denom = trackLen - thumbLen
            if denom <= 0 then return end
            local maxScroll = isVertical and sp._maxY or sp._maxX
            local frac = (delta / denom)
            local newScroll = startScroll + frac * maxScroll
            if isVertical then sp:setScroll(sp.scrollX, newScroll)
            else sp:setScroll(newScroll, sp.scrollY) end
        end)
    end)
end

--- Билдер: ui:scrollpanel({ axis=, scrollbar=, wheelStep=, contentW=,
-- contentH=, children=, ... }).
function ScrollPanel.build(context, props)
    props = props or {}
    local node = ScrollPanel:new(props)
    if props.width == nil then node.width = 200 end
    if props.height == nil then node.height = 200 end
    node._contentW = props.contentW
    node._contentH = props.contentH

    -- content: невидимый контейнер (plain Node без render)
    local content = context:createNode({})
    content:setParent(node)
    content.enabled = false
    node._content = content

    -- полосы прокрутки (опционально)
    local axis = node.axis
    if props.scrollbar ~= false then
        if axis == "v" or axis == "both" then
            node._trackV, node._thumbV = buildScrollbar(context, node, axis)
            wireThumbDrag(context, node, node._thumbV, true)
        end
        if axis == "h" or axis == "both" then
            node._trackH, node._thumbH = buildScrollbar(context, node, axis)
            wireThumbDrag(context, node, node._thumbH, false)
        end
    end

    -- wheel (бабблит от детей content к viewport)
    local wheelStep = props.wheelStep or WHEEL_STEP
    node:on("wheel", function(e)
        if not node:isAlive() then return end
        local dz = e.dz or 0
        if node.axis == "h" then
            node:scrollBy(-dz * wheelStep, 0)
        else
            node:scrollBy(0, -dz * wheelStep)
        end
    end)

    -- дети — в content
    DXUI.Widget.attachChildren(content, props)

    -- первичный layout
    node:refresh()

    return node
end

DXUI.ScrollPanel = ScrollPanel
