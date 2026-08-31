--[[
    context.lua — DXUI V2

    Context: изолированный UI-контекст (§56/§57). Владеет:
      - своим корнем (root node);
      - своей dirty-очередью (узлы, ожидающие обработки в кадре);
      - своим focus manager (Stage 4);
      - своими layers.

    Глобальный coordinator (screen size, input bridge, frame lifecycle,
    resource manager) живёт в api/ui.lua и init.lua — не здесь.

    Контексты изолированы: дерево/фокус/слои одного не влияют на другой.
]]

DXUI = DXUI or {}

local Context = {}
Context.__index = Context

function Context.new(backend)
    local self = setmetatable({}, Context)

    self._dirtyList = {}   -- плоский список dirty-узлов (без дублей)
    self._dirtyCount = 0
    self.layoutDirty = false -- Stage 5: есть ли узлы с DIRTY_LAYOUT

    self.focusedNode = nil -- Stage 4: focus manager
    self.screenW = 0
    self.screenH = 0

    -- root: верх дерева. Его _context — сам контекст.
    self.root = DXUI.Node:new()
    rawset(self.root, "_context", self)

    -- Stage 3: render. backend — MTA-драйвер или мок (тесты).
    self.backend = backend or DXUI.MtaBackend
    self.renderList = DXUI.RenderList.new()
    self.renderer = DXUI.Renderer.new(self.renderList)
    self.stateCache = DXUI.StateCache.new(self.backend)

    -- Stage 4: input. Плоский список интерактивных узлов (derived cache).
    self.interactiveList = {}
    self.interactiveCount = 0
    self.dispatcher = DXUI.Dispatcher.new(self)

    -- Stage 7: виртуальный clipboard (copy/paste между полями контекста).
    self.clipboard = ""

    -- Stage 7b: clock (мс) — единый источник времени для animation/schedule.
    -- MTA: getTickCount(); тесты: подменяется через setClock.
    if getTickCount then
        self.clock = function() return getTickCount() end
    else
        self.clock = function() return os.clock() * 1000 end
    end

    -- Stage 7b: animation manager (единый тик в renderFrame, §51).
    self.animation = DXUI.AnimationManager.new(self)

    return self
end

-- ---------------------------------------------------------------------
-- Создание / монтирование
-- ---------------------------------------------------------------------

--- Создаёт узел (или виджет) и опционально монтирует в корень.
-- Stage 6 добавит context:panel/button/... поверх этого.
function Context:createNode(props)
    return DXUI.Node:new(props)
end

--- Монтирует узел в корень контекста (parent = root).
function Context:mount(node)
    node:setParent(self.root)
    return node
end

--- Уничтожает узел (и его поддерево).
function Context:destroy(node)
    if node then node:destroy() end
end

-- ---------------------------------------------------------------------
-- Widget builders (Stage 6) — тонкие делегаты к widgets/*.lua.
-- Билдеры авто-монтируют результат в root (mounted-фаза при создании).
-- ---------------------------------------------------------------------

function Context:panel(props)
    local node = DXUI.Panel.build(self, props)
    self:mount(node)
    return node
end

function Context:label(props)
    local node = DXUI.Label.build(self, props)
    self:mount(node)
    return node
end

function Context:button(props)
    local node = DXUI.Button.build(self, props)
    self:mount(node)
    return node
end

function Context:image(props)
    local node = DXUI.Image.build(self, props)
    self:mount(node)
    return node
end

function Context:window(props)
    local node = DXUI.Window.build(self, props)
    self:mount(node)
    return node
end

-- Stage 7: advanced widgets
function Context:checkbox(props)
    local node = DXUI.CheckBox.build(self, props)
    self:mount(node)
    return node
end

function Context:radiobutton(props)
    local node = DXUI.RadioButton.build(self, props)
    self:mount(node)
    return node
end

function Context:slider(props)
    local node = DXUI.Slider.build(self, props)
    self:mount(node)
    return node
end

function Context:progressbar(props)
    local node = DXUI.ProgressBar.build(self, props)
    self:mount(node)
    return node
end

function Context:scrollpanel(props)
    local node = DXUI.ScrollPanel.build(self, props)
    self:mount(node)
    return node
end

function Context:edit(props)
    local node = DXUI.Edit.build(self, props)
    self:mount(node)
    return node
end

function Context:popup(props)
    local node = DXUI.Popup.build(self, props)
    self:mount(node)
    return node
end

function Context:contextmenu(props)
    local node = DXUI.ContextMenu.build(self, props)
    self:mount(node)
    return node
end

function Context:combobox(props)
    local node = DXUI.ComboBox.build(self, props)
    self:mount(node)
    return node
end

function Context:tabpanel(props)
    local node = DXUI.TabPanel.build(self, props)
    self:mount(node)
    return node
end

function Context:gridlist(props)
    local node = DXUI.GridList.build(self, props)
    self:mount(node)
    return node
end

-- ---------------------------------------------------------------------
-- Dirty-очередь (internal)
-- ---------------------------------------------------------------------

--- Добавляет узел в очередь кадра (дедуп через node._queued).
function Context:_queueDirty(node)
    if node._queued then return end
    node._queued = true
    self._dirtyCount = self._dirtyCount + 1
    self._dirtyList[self._dirtyCount] = node
    if node._dirty[DXUI.DIRTY.LAYOUT] then
        self.layoutDirty = true
    end
end

--- Узел уничтожен: снимаем флаг очереди (сам список чистится в processDirty)
-- и чистим input-ссылки (hover/pressed/focus) на него.
function Context:_onNodeDestroyed(node)
    node._queued = false
    self.dispatcher:_onNodeDestroyed(node)
    -- Уничтожение узла меняет hit-геометрию (§93): немедленная
    -- перестройка interactiveList, иначе мёртвые узлы застрянут в кэше.
    self:_rebuildInteractiveList()
end

-- ---------------------------------------------------------------------
-- Обработка кадра
-- ---------------------------------------------------------------------

--- Обрабатывает dirty-узлы за кадр. Stage 3/5 вставят сюда layout/render/
-- input-проходы, читающие node._dirty. В Stage 2 — только очистка очереди.
function Context:processDirty()
    self:_clearDirty()
end

function Context:_clearDirty()
    for i = 1, self._dirtyCount do
        local node = self._dirtyList[i]
        self._dirtyList[i] = nil
        if node and not node._destroyed then
            node._queued = false
            node._dirty = {}
        end
    end
    self._dirtyCount = 0
end

-- ---------------------------------------------------------------------
-- Render (Stage 3)
-- ---------------------------------------------------------------------

--- Полный кадр: design-mapping → animations → layout (если DIRTY_LAYOUT) →
-- пересборка render list + interactive list (если есть dirty) + отрисовка.
-- Idle = только отрисовка.
function Context:renderFrame()
    self:_updateDesignMapping()
    self.animation:update() -- §89: animations первыми (могут добавить dirty)
    if self._dirtyCount > 0 then
        if self.layoutDirty then
            self:_updateLayout()
            self.layoutDirty = false
        end
        self:_rebuildRenderList()
        self:_rebuildInteractiveList()
        self:_clearDirty()
    end
    self:_draw()
end

--- Stage 8 (§31–§33): design → screen mapping. Layout-пространство =
-- design resolution (если задана), иначе экран. Renderer масштабирует
-- примитивы; события конвертируются обратно через toLocal.
-- Если размер неизвестен (setScreenSize не вызван) — identity (scale 1).
function Context:_updateDesignMapping()
    local dw = DXUI.designW or self.screenW
    local dh = DXUI.designH or self.screenH
    local sw, sh = self.screenW or 0, self.screenH or 0
    if not dw or not dh or dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0 then
        -- identity: без размеров ничего не масштабируем (не 0/0 = nan!)
        self.layoutW, self.layoutH = sw, sh
        self._mapScaleX, self._mapScaleY = 1, 1
        self._mapOffX, self._mapOffY = 0, 0
        local r = self.renderer
        r.scaleX, r.scaleY, r.offsetX, r.offsetY = 1, 1, 0, 0
        return
    end
    local sx = sw / dw
    local sy = sh / dh
    local offX, offY = 0, 0
    if DXUI.designScaleMode == "fit" then
        local s = math.min(sx, sy)
        offX = (sw - dw * s) / 2
        offY = (sh - dh * s) / 2
        sx, sy = s, s
    end
    self.layoutW, self.layoutH = dw, dh
    self._mapScaleX, self._mapScaleY = sx, sy
    self._mapOffX, self._mapOffY = offX, offY
    local r = self.renderer
    r.scaleX, r.scaleY, r.offsetX, r.offsetY = sx, sy, offX, offY
end

--- Экранные координаты → design-координаты (для dispatcher/hit-test).
-- Без design resolution — identity.
function Context:toLocal(x, y)
    if self._mapScaleX and self._mapScaleX ~= 0 then
        return (x - self._mapOffX) / self._mapScaleX,
               (y - self._mapOffY) / self._mapScaleY
    end
    return x, y
end

--- Подменяет источник времени (мс) — для тестов.
function Context:setClock(fn)
    self.clock = fn
end

--- Stage 5: layout-проход (вычисление world-координат).
function Context:_updateLayout()
    DXUI.Layout.update(self)
end

--- Порядок отрисовки узлов: (layer, zIndex, id) — hit-test использует
--- тот же порядок, поэтому «визуально сверху» = «получает клик».
local function nodeLess(a, b)
    local la = a._effLayer or a.layer
    local lb = b._effLayer or b.layer
    if la ~= lb then return la < lb end
    if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
    return a.id < b.id
end

--- Пересобирает render list: сбор видимых renderable-узлов → рендер.
function Context:_rebuildRenderList()
    self.renderList:clear()

    local nodes = {}
    self:_collectRenderable(self.root, true, nil, 1, DXUI.LAYER.BASE, nodes)

    self:_renderNodes(nodes, self.renderList)
end

--- Сортирует узлы и рендерит их в list (§89 render preparation).
-- Рекурсивно: узлы с clipMode="rt" рендерят поддерево в RT-группу.
function Context:_renderNodes(nodes, list)
    table.sort(nodes, nodeLess)

    local r = DXUI.Renderer.new(list)
    r.scaleX, r.scaleY = self.renderer.scaleX, self.renderer.scaleY
    r.offsetX, r.offsetY = self.renderer.offsetX, self.renderer.offsetY

    for i = 1, #nodes do
        local node = nodes[i]
        r.node = node
        r:_loadClip(node)

        -- Stage 11 (§35 expensive path): pixel-perfect RT-clip + group-opacity
        if node._rtClip then
            self:_renderRtGroup(node, list, r)

        -- Stage 10 (§35/§39): node-level blur/mask на НЕ-Image виджетах →
        -- собственные items узла через RT-группу (effect layer).
        elseif (node.blur and node.blur > 0 or node.mask ~= nil)
            and DXUI.Effects and DXUI.Effects.canGroup()
            and node._class._name ~= "Image" then
            local effect
            if node.mask then
                effect = DXUI.Effects.mask(node.mask)
            else
                effect = DXUI.Effects.blur(node.width, node.height, node.blur)
            end
            if effect then
                local own = DXUI.RenderList.new()
                local gr = DXUI.Renderer.new(own)
                gr.node = node
                gr:_loadClip(node)
                gr.scaleX, gr.scaleY = r.scaleX, r.scaleY
                gr.offsetX, gr.offsetY = r.offsetX, r.offsetY
                node:render(gr)
                if own.count > 0 then
                    local sx, ox = r.scaleX, r.offsetX
                    local sy, oy = r.scaleY, r.offsetY
                    list:add({
                        kind = "rtgroup",
                        x = node.worldX * sx + ox, y = node.worldY * sy + oy,
                        w = node.width * sx, h = node.height * sy,
                        items = own.items, count = own.count,
                        effect = effect,
                    })
                end
            else
                node:render(r) -- шейдер недоступен — без эффекта
            end
        else
            node:render(r)
        end
    end
end

--- Stage 11 (§35 expensive path): поддерево узла → offscreen RT → один квад.
-- Pixel-perfect clip (RT-границы режут аппаратно) + TRUE group-opacity
-- (alpha на квад — пересечения внутри не блендятся дважды) + blur/mask
-- на ВСЁ поддерево (контейнерная семантика — в отличие от Stage 10, где
-- blur применяется только к собственным items узла).
function Context:_renderRtGroup(node, list, r)
    local sx, ox = r.scaleX, r.offsetX
    local sy, oy = r.scaleY, r.offsetY

    -- clip-регион узла (родительская geometric-цепочка) — детям ВНУТРИ RT
    local parentClip
    if node._clipX ~= nil then
        parentClip = { node._clipX, node._clipY, node._clipW, node._clipH }
    end

    -- собственные items узла — фоном (opacity узла на квад, не в items)
    local subList = DXUI.RenderList.new()
    if node.render then
        local orr = DXUI.Renderer.new(subList)
        orr.node = node
        orr:_loadClip(node)
        orr.effOpacity = 1
        orr.scaleX, orr.scaleY = r.scaleX, r.scaleY
        orr.offsetX, orr.offsetY = r.offsetX, r.offsetY
        node:render(orr)
    end

    -- поддерево: собираем с opacity ОТНОСИТЕЛЬНО группы (узел's opacity на кв.)
    local sub = {}
    local children = node._children
    for i = 1, #children do
        self:_collectRenderable(children[i], true, parentClip, 1,
            node._effLayer or node.layer, sub)
    end
    self:_renderNodes(sub, subList) -- рекурсия (вложенные RT-группы)

    if subList.count == 0 then return end

    -- эффект на весь композит (контейнер): mask приоритетнее blur
    local effect
    if node.mask then
        effect = DXUI.Effects.mask(node.mask)
    elseif node.blur and node.blur > 0 then
        effect = DXUI.Effects.blur(node.width, node.height, node.blur)
    end

    list:add({
        kind = "rtgroup",
        x = node.worldX * sx + ox, y = node.worldY * sy + oy,
        w = node.width * sx, h = node.height * sy,
        items = subList.items, count = subList.count,
        effect = effect,
        alpha = node._effOpacity or 1, -- true group-opacity (§34)
    })
end

--- Пересечение clip-региона (таблица {x,y,w,h} или nil) с прямоугольником.
-- Возвращает {nx,ny,nw,nh} или nil (целиком вне).
local function intersectClip(clip, x, y, w, h)
    local cx, cy, cw, ch
    if clip then
        cx, cy, cw, ch = clip[1], clip[2], clip[3], clip[4]
    else
        cx, cy, cw, ch = x, y, w, h
    end
    local x2, y2 = x + w, y + h
    local cx2, cy2 = cx + cw, cy + ch
    local nx = (x > cx) and x or cx
    local ny = (y > cy) and y or cy
    local nx2 = (x2 < cx2) and x2 or cx2
    local ny2 = (y2 < cy2) and y2 or cy2
    if nx2 <= nx or ny2 <= ny then return nil end
    return { nx, ny, nx2 - nx, ny2 - ny }
end

--- Рекурсивный сбор видимых renderable-узлов (basic culling: visible AND
-- все предки visible). parentVisible — эффективная видимость родителя;
-- clip — накопленный clip-регион (nil если нет); parentOpacity —
-- наследуемая opacity (§34: эффективная = node.opacity × родительская).
-- Узел с clip=true создаёт свой регион (пересечение с родительским);
-- целиком вне — поддерево сносится.
function Context:_collectRenderable(node, parentVisible, parentClip, parentOpacity, parentLayer, out)
    local visible = parentVisible and node.visible

    -- эффективный слой (§58): собственный не-BASE слой узла, иначе —
    -- ближайшего предка с не-BASE слоем (modal-поддерево выше overlay)
    local effLayer = node.layer
    if effLayer == DXUI.LAYER.BASE then
        effLayer = parentLayer or DXUI.LAYER.BASE
    end
    rawset(node, "_effLayer", effLayer)

    local clip = parentClip
    if node.clip then
        clip = intersectClip(parentClip, node.worldX, node.worldY, node.width, node.height)
        if not clip then return end -- целиком вне clip — сносим поддерево
    end

    -- эффективная opacity (§34): наследуется вниз мультипликативно.
    -- Дешёвый путь — alpha-модуляция в renderer; true group-opacity — RT.
    local op = node.opacity
    if op == nil or op > 1 then op = 1 elseif op < 0 then op = 0 end
    local effOpacity = parentOpacity * op
    rawset(node, "_effOpacity", effOpacity)

    -- сохраняем clip-регион на узле (renderer читает его в _loadClip)
    if clip then
        rawset(node, "_clipX", clip[1]); rawset(node, "_clipY", clip[2])
        rawset(node, "_clipW", clip[3]); rawset(node, "_clipH", clip[4])
    else
        rawset(node, "_clipX", nil); rawset(node, "_clipY", nil)
        rawset(node, "_clipW", nil); rawset(node, "_clipH", nil)
    end

    -- Stage 11 (§35): clipMode="rt" — поддерево рендерится в RT-группу
    -- (pixel-perfect clip + group-opacity). Дети НЕ идут в основной список.
    local rtClip = visible and node.clipMode == "rt"
        and DXUI.Effects and DXUI.Effects.canGroup()
    rawset(node, "_rtClip", rtClip or nil)

    if visible and (node.render or rtClip) then
        out[#out + 1] = node
    end
    if rtClip then return end -- поддерево — через _renderRtGroup

    local children = node._children
    for i = 1, #children do
        self:_collectRenderable(children[i], visible, clip, effOpacity, effLayer, out)
    end
end

--- Пересобирает плоский список интерактивных узлов (derived cache, §93).
-- Интерактивный = enabled AND visible (и все предки visible). Сортировка —
-- тот же порядок (layer, zIndex, id), что и render, поэтому «визуально
-- сверху» = «получает клик».
function Context:_rebuildInteractiveList()
    local nodes = {}
    self:_collectInteractive(self.root, true, DXUI.LAYER.BASE, nodes)

    table.sort(nodes, function(a, b)
        local la = a._effLayer or a.layer
        local lb = b._effLayer or b.layer
        if la ~= lb then return la < lb end
        if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
        return a.id < b.id
    end)

    self.interactiveList = {}
    self.interactiveCount = 0
    for i = 1, #nodes do
        self.interactiveCount = self.interactiveCount + 1
        self.interactiveList[self.interactiveCount] = nodes[i]
    end
end

function Context:_collectInteractive(node, parentVisible, parentLayer, out)
    local visible = parentVisible and node.visible
    local effLayer = node.layer
    if effLayer == DXUI.LAYER.BASE then
        effLayer = parentLayer or DXUI.LAYER.BASE
    end
    rawset(node, "_effLayer", effLayer)
    if visible and node.enabled then
        out[#out + 1] = node
    end
    local children = node._children
    for i = 1, #children do
        self:_collectInteractive(children[i], visible, effLayer, out)
    end
end

--- Отрисовывает закэшированный render list через state cache.
function Context:_draw()
    local items = self.renderList.items
    for i = 1, self.renderList.count do
        self.stateCache:draw(items[i])
    end
end

-- ---------------------------------------------------------------------
-- Input (Stage 4) — тонкие пробросы к Dispatcher
-- ---------------------------------------------------------------------

function Context:onCursorMove(x, y)
    self.dispatcher:onCursorMove(x, y)
end

function Context:onMouseDown(x, y, button)
    self.dispatcher:onMouseDown(x, y, button)
end

function Context:onMouseUp(x, y, button)
    self.dispatcher:onMouseUp(x, y, button)
end

function Context:onMouseWheel(x, y, dz)
    self.dispatcher:onMouseWheel(x, y, dz)
end

function Context:onKeyDown(key, state, mods, text)
    self.dispatcher:onKeyDown(key, state, mods, text)
end

function Context:setFocus(node)
    self.dispatcher:setFocus(node)
end

function Context:getFocus()
    return self.dispatcher:getFocus()
end

-- ---------------------------------------------------------------------
-- Размер экрана (для layout, Stage 5)
-- ---------------------------------------------------------------------

function Context:setScreenSize(w, h)
    self.screenW = w
    self.screenH = h
    -- Stage 5: смена размера экрана → пересчитать layout (root dirty каскадит).
    self.root:_invalidate({ DXUI.DIRTY.LAYOUT })
end

-- ---------------------------------------------------------------------
-- Публикация
-- ---------------------------------------------------------------------
DXUI.Context = Context
