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
-- Dirty-очередь (internal)
-- ---------------------------------------------------------------------

--- Добавляет узел в очередь кадра (дедуп через node._queued).
function Context:_queueDirty(node)
    if node._queued then return end
    node._queued = true
    self._dirtyCount = self._dirtyCount + 1
    self._dirtyList[self._dirtyCount] = node
end

--- Узел уничтожен: снимаем флаг очереди (сам список чистится в processDirty)
-- и чистим input-ссылки (hover/pressed/focus) на него.
function Context:_onNodeDestroyed(node)
    node._queued = false
    self.dispatcher:_onNodeDestroyed(node)
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

--- Полный кадр: пересборка render list + interactive list (если есть dirty)
-- + отрисовка. Idle-кадр без изменений = только отрисовка закэшированного.
function Context:renderFrame()
    if self._dirtyCount > 0 then
        self:_rebuildRenderList()
        self:_rebuildInteractiveList()
        self:_clearDirty()
    end
    self:_draw()
end

--- Пересобирает render list: обход дерева, сбор видимых renderable-узлов,
-- сортировка по (layer, zIndex, id), вызов render(renderer) каждого.
function Context:_rebuildRenderList()
    self.renderList:clear()

    local nodes = {}
    self:_collectRenderable(self.root, true, nodes)

    table.sort(nodes, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
        return a.id < b.id
    end)

    for i = 1, #nodes do
        local node = nodes[i]
        self.renderer.node = node
        node:render(self.renderer)
    end
end

--- Рекурсивный сбор видимых renderable-узлов (basic culling: visible AND
-- все предки visible). parentVisible — эффективная видимость родителя.
function Context:_collectRenderable(node, parentVisible, out)
    local visible = parentVisible and node.visible
    if visible and node.render then
        out[#out + 1] = node
    end
    local children = node._children
    for i = 1, #children do
        self:_collectRenderable(children[i], visible, out)
    end
end

--- Пересобирает плоский список интерактивных узлов (derived cache, §93).
-- Интерактивный = enabled AND visible (и все предки visible). Сортировка —
-- тот же порядок (layer, zIndex, id), что и render, поэтому «визуально
-- сверху» = «получает клик».
function Context:_rebuildInteractiveList()
    local nodes = {}
    self:_collectInteractive(self.root, true, nodes)

    table.sort(nodes, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
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

function Context:_collectInteractive(node, parentVisible, out)
    local visible = parentVisible and node.visible
    if visible and node.enabled then
        out[#out + 1] = node
    end
    local children = node._children
    for i = 1, #children do
        self:_collectInteractive(children[i], visible, out)
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
end

-- ---------------------------------------------------------------------
-- Публикация
-- ---------------------------------------------------------------------
DXUI.Context = Context
