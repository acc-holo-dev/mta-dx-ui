--[[
    ui.lua (M7)

    Declarative widget API: "simple outside, complex inside" (§42 ТЗ).

        local ui = DXUI.UI.new(kernel)
        local w = ui.window({
            title = "Settings",
            x = 100, y = 80, w = 320, h = 240,
            children = {
                ui.button({ text = "OK",   x = 10,  y = 10, onClick = fn }),
                ui.label({ text = "Hi", x = 10, y = 60 }),
            },
        })

    Ключевые решения:
      - Виджет = УЗЕЛ ядра + свойства. Нет классов-обёрток, нет состояния
        вне Storage (ADR-002): весь "виджет" — это строки SoA.
      - Строки/таблицы разрешены здесь (cold path — событие пользователя);
        в кадр ничего из этого не утекает.
      - Цвет: 0xRRGGBBAA (packed, MTA-совместимый pass-through в
        dxDraw* — ноль конверсий в hot path).
      - Button c текстом = NODE_BUTTON (фон) + auto-child NODE_TEXT
        (подпись, весь размер родителя) — т.к. ядро рисует узел с text
        как CMD_TEXT (только текст).
      - Window c title = NODE_WINDOW (фон) + title bar (panel) + label.
      - children: массив proxy-объектов (из ui.* builders) — setParent.

    Всё создание — через kernel:create (id freelist, proxy pool) — т.е.
    виджеты полностью совместимы с M6 (animateTo), M5 (clip/opacity),
    M3 (on()), destroy-каскадом.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local UI = {}
UI.__index = UI
DXUI.UI = UI

-- Дефолтные размеры/цвета (cold path, константы модуля).
local DEFAULTS = {
    window = { w = 320, h = 240 },
    panel  = { w = 100, h = 100 },
    button = { w = 100, h = 30 },
    label  = { w = 100, h = 20 },
    image  = { w = 64, h = 64 },
    checkbox    = { w = 120, h = 24 },
    radio       = { w = 120, h = 24 },
    slider      = { w = 200, h = 16 },
    progressbar = { w = 200, h = 16 },
    combobox    = { w = 150, h = 26 },
    tabpanel    = { w = 300, h = 200 },
    gridlist    = { w = 300, h = 200 },
}

local COLOR_DEFAULT   = 0xFFFFFFFF
local COLOR_TITLEBAR  = 0x334455FF -- тёмный title bar окна
local COLOR_TEXT      = 0xFFFFFFFF

--- Разрешает цвет: number (packed) | "#RRGGBB[AA]" | {r,g,b,a}.
-- Cold path: строки и аллокации допустимы.
local function resolveColor(c)
    if c == nil then return nil end
    if type(c) == "number" then return c end
    if type(c) == "string" then
        -- c:match("^#?") возвращает "" (truthy) и без "#", поэтому sub(2) всегда срабатывал.
        -- Правильно: захватить всё после "#", если есть; иначе вернуть исходную строку.
        local hex = c:match("^#(.*)$") or c
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    if type(c) == "table" then
        local r, g, b = c.r or 0, c.g or 0, c.b or 0
        local a = c.a or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    error("ui.color: unsupported color type: " .. type(c))
end

--- ui.color(r, g, b, a) -> packed 0xAARRGGBB (MTA tocolor).
local function uiColor(r, g, b, a)
    return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- Применяет общие свойства к созданному узлу. Порядок не важен
-- (все независимые set* с dirty-марками).
local function applyCommon(node, props)
    if props.x ~= nil or props.y ~= nil then
        node:setPosition(props.x or 0, props.y or 0)
    end
    if props.w ~= nil or props.h ~= nil then
        node:setSize(props.w or 0, props.h or 0)
    end
    local col = resolveColor(props.color)
    if col then node:setColor(col) end
    if props.layer ~= nil then node:setLayer(props.layer) end
    if props.anchor ~= nil then node:setAnchor(props.anchor) end
    if props.layoutMode ~= nil then node:setLayoutMode(props.layoutMode) end
    if props.margin then node:setMargin(props.margin[1] or 0, props.margin[2] or 0, props.margin[3] or 0, props.margin[4] or 0) end
    if props.padding then node:setPadding(props.padding[1] or 0, props.padding[2] or 0, props.padding[3] or 0, props.padding[4] or 0) end
    if props.clip ~= nil then node:setClip(props.clip) end
    if props.opacity ~= nil then node:setOpacity(props.opacity) end
    if props.blur ~= nil then node:setBlur(props.blur) end
    if props.visible ~= nil then node:setVisible(props.visible) end
    if props.enabled ~= nil then node:setEnabled(props.enabled) end
    if props.static ~= nil then node:setStatic(props.static) end
end

-- Рекурсивный приём children: массив proxy (виджетов).
local function attachChildren(kernel, node, props)
    local children = props.children
    if not children then return end
    for i = 1, #children do
        children[i]:setParent(node)
    end
end

function UI.new(kernel)
    local self = setmetatable({}, UI)
    self.kernel = kernel
    return self
end

function UI:color(r, g, b, a)
    return uiColor(r, g, b, a)
end

-- ======================= M12: Window 2.0 (ADR-016) ======================
-- Composite-proxy (§4.1 master prompt): один публичный handle -> несколько
-- узлов Storage. Внутренние узлы -- обычные дети (destroy-каскад M1 сносит
-- их сам), proxy хранит ссылки в _parts, widget-методы -- отдельная
-- metatable ПОВЕРХ базовых методов proxy (kernel.proxy.methods).

local BAR_H                 = 24  -- высота title bar
local CLOSE_W, CLOSE_H      = 16, 16
local GRIP_W, GRIP_H        = 14, 14
local WIN_MIN_W, WIN_MIN_H  = 80, 60
local MODAL_OVERLAY_COLOR   = 0x80000000 -- M16: полупрозрачный чёрный (50%)

-- M16 (ADR-020): рекурсивно выставить layer всему поддереву (окно + дети).
-- Нужно, т.к. layer не наследуется задним числом: дети, созданные ДО
-- setModal(true), остались бы LAYER_BASE и рендерились бы ПОД overlay.
-- Новые дети наследуют слой через Storage:setParent (см. storage.lua M16).
local function setSubtreeLayer(k, nodeId, layer)
    local s = k.storage
    local slot = s.idToSlot[nodeId]
    if not slot then return end
    s.layer[slot] = layer
    s.orderDirty = true
    s:markDirty(nodeId, C.DIRTY_RENDER)
    local childId = s.firstChild[slot]
    while childId ~= C.NIL_ID do
        setSubtreeLayer(k, childId, layer)
        childId = s.nextSibling[s.idToSlot[childId]]
    end
end

-- M20 (ADR-024):
local MODAL_FADE_MS = 150 -- fade-in overlay
local POPUP_FADE_MS = 100 -- fade-in popup (поддерево)

--- M20: первый фокусируемый потомок поддерева (DFS, порядок создания).
-- Реестр kernel.focusables заполняют ввод-виджеты (Edit и т.п.).
-- Возвращает id или nil. Используется modal auto-focus'ом.
local function findFirstFocusable(k, rootId)
    local s = k.storage
    local focusables = k.focusables
    if not focusables then return nil end
    local function walk(id)
        local slot = s.idToSlot[id]
        if not slot then return nil end
        local childId = s.firstChild[slot]
        while childId ~= C.NIL_ID do
            if focusables[childId] then return childId end
            local found = walk(childId)
            if found then return found end
            local cs = s.idToSlot[childId]
            childId = cs and s.nextSibling[cs] or C.NIL_ID
        end
        return nil
    end
    return walk(rootId)
end

--- M20: fade поддерева. opacity НЕ каскадится (builder.lua: per-node
-- pool.opacity[cmdSlot]); поэтому анимируем КАЖДЫЙ узел отдельно —
-- напрямую через animPool:start по raw id (без proxy).
local function fadeSubtree(k, rootId, from, to, ms, ease)
    local s = k.storage
    local pool = k.animPool
    local function walk(id)
        local slot = s.idToSlot[id]
        if not slot then return end
        s.opacity[slot] = from
        local isFlag = from ~= 255
        if s:hasFlag(id, C.FLAG_OPACITY) ~= isFlag then
            s:setFlag(id, C.FLAG_OPACITY, isFlag)
        end
        s:markDirty(id, C.DIRTY_RENDER)
        if to ~= from then
            pool:start(id, C.ANIM_OPACITY, to, ms, ease)
        end
        local childId = s.firstChild[slot]
        while childId ~= C.NIL_ID do
            walk(childId)
            local cs = s.idToSlot[childId]
            childId = cs and s.nextSibling[cs] or C.NIL_ID
        end
    end
    walk(rootId)
end

local WindowMethods = {}

function WindowMethods:setTitle(text)
    local parts = self._parts
    if parts and parts.title then parts.title:setText(text) end
    return self
end

function WindowMethods:getTitle()
    local parts = self._parts
    if parts and parts.title then
        local s = self._kernel.storage
        local slot = s.idToSlot[parts.title.id]
        return slot and s.text[slot] or nil
    end
end

function WindowMethods:setDraggable(v)
    self._win.draggable = v and true or false
    return self
end

function WindowMethods:setResizable(v)
    local parts = self._parts
    self._win.resizable = v and true or false
    if parts and parts.grip then parts.grip:setVisible(self._win.resizable) end
    return self
end

function WindowMethods:setClosable(v)
    local parts = self._parts
    self._win.closable = v and true or false
    if parts and parts.close then parts.close:setVisible(self._win.closable) end
    return self
end

--- M12: окно поверх соседей (zIndex = max(siblings)+1; no-op если уже сверху).
-- Для корневых окон (без родителя) сравнивает по всем корням -- они "соседи"
-- в порядке отрисовки в рамках одного layer.
function WindowMethods:bringToFront()
    local k = self._kernel
    if not k then return self end
    local s = k.storage
    local slot = s.idToSlot[self.id]
    if not slot then return self end
    local maxZ, ownZ = -1, s.zIndex[slot] or 0
    local parentId = s.parent[slot]
    if parentId ~= C.NIL_ID then
        local childId = s.firstChild[s.idToSlot[parentId]]
        while childId ~= C.NIL_ID do
            if childId ~= self.id then
                local z = s.zIndex[s.idToSlot[childId]] or 0
                if z > maxZ then maxZ = z end
            end
            childId = s.nextSibling[s.idToSlot[childId]]
        end
    else
        -- корневые окна: перебор живых корней (cold path, O(n) на клик)
        for i = 1, s.count do
            if s.parent[i] == C.NIL_ID and s.slotToId[i] ~= self.id then
                local z = s.zIndex[i] or 0
                if z > maxZ then maxZ = z end
            end
        end
    end
    if maxZ >= ownZ then self:setZIndex(maxZ + 1) end
    return self
end

--- M16 (ADR-020): полный modal — overlay + focus lock + input trap.
-- v: true/false, либо таблица { overlay=bool, dismissOnClickOutside=bool,
-- overlayColor=0xAARRGGBB }. overlay по умолчанию true (затемнение фона).
-- Пока modal активен: фокус и ввод заперты внутри окна (Dispatcher M16),
-- клики/колесо/наведение вне окна блокируются, фон затемнён overlay'ем.
function WindowMethods:setModal(v)
    local k = self._kernel
    local win = self._win
    if not k or not win then return self end

    local opts = type(v) == "table" and v or {}
    local enable = (v ~= false and v ~= nil)

    if enable then
        if win.modal and win.modal.active then return self end -- уже modal

        -- 1) окно + всё поддерево в LAYER_MODAL (дети, созданные до этого,
        --    остались бы LAYER_BASE — см. setSubtreeLayer)
        setSubtreeLayer(k, self.id, C.LAYER_MODAL)

        -- 2) overlay (затемнение фона), если не отключён
        local overlay = nil
        if opts.overlay ~= false then
            overlay = k:create(C.NODE_PANEL, nil)
            overlay:setLayoutMode(C.LAY_REL)
            overlay:setPosition(0, 0)
            overlay:setSize(k.screenW or 0, k.screenH or 0)
            overlay:setColor(opts.overlayColor or MODAL_OVERLAY_COLOR)
            overlay:setLayer(C.LAYER_MODAL)
            overlay:setEnabled(true)
        end

        -- 3) регистрация в dispatcher (focus lock + input trap)
        local depth = k.dispatcher:pushModal(self.id, overlay and overlay.id or C.NIL_ID)

        -- 4) z-порядок: overlay ниже окна; вложенные modal — выше предыдущих
        if overlay then overlay:setZIndex((depth - 1) * 2) end
        self:setZIndex((depth - 1) * 2 + 1)

        win.modal = {
            active = true,
            overlay = overlay,
            dismissOnClickOutside = opts.dismissOnClickOutside == true,
        }

        -- 5) клик вне окна (по overlay) — закрыть, если разрешено
        if overlay and win.modal.dismissOnClickOutside then
            overlay:on("click", function() self:close() end)
        end

        -- 6) M20 (ADR-024): авто-фокус первого фокусируемого потомка
        --    (Edit и т.п.); иначе — фокус на само окно (keyboard в modal).
        local fid = findFirstFocusable(k, self.id)
        k.dispatcher:setFocus(fid or self.id)

        -- 7) M20 (ADR-024): fade-in overlay (ANIM_OPACITY). Цвет overlay
        --    несёт альфу 0x80, opacity узла — отдельный множитель 0->255.
        if overlay then
            overlay:setOpacity(0)
            overlay:animateTo({ opacity = 255 }, MODAL_FADE_MS, C.EASE_OUT)
        end
    else
        if not (win.modal and win.modal.active) then return self end
        k.dispatcher:popModal(self.id)
        if win.modal.overlay and win.modal.overlay:isAlive() then
            win.modal.overlay:destroy()
            k.proxy:release(win.modal.overlay)
        end
        win.modal = nil
        setSubtreeLayer(k, self.id, C.LAYER_BASE)
    end
    return self
end

--- M12: запрос закрытия. Событие "close" бабблится от узла окна; слушатель
-- может отменить destroy через event.preventDefault(). По умолчанию -- destroy.
function WindowMethods:close()
    local k = self._kernel
    if not k then return self end
    local ev = {}
    k.eventBus:emit(self.id, C.EVENT_CLOSE, ev)
    if not ev.defaultPrevented and self:isAlive() then
        self:destroy()
    end
    return self
end

--- Override: базовый setSize + пересчёт составных частей (bar/title).
-- Grip прикреплён LAY_REL(1,1)+ANCHOR_BR и следует за размером сам.
-- Известное ограничение (ADR-016): animateTo({w=..}) пишет storage напрямую
-- и НЕ синхронизирует части -- размер окна нельзя анимировать.
function WindowMethods:setSize(w, h)
    local win = self._win
    if not win then return self end -- composite уже destroyed
    if w < win.minW then w = win.minW end
    if h < win.minH then h = win.minH end
    win.baseSetSize(self, w, h)
    local parts = self._parts
    if parts then
        if parts.bar then parts.bar:setSize(w, BAR_H) end
        if parts.title then
            local closeW = (parts.close and win.closable) and CLOSE_W or 0
            parts.title:setSize(w - 8 - closeW, BAR_H - 4)
        end
    end
    return self
end

--- Override: composite destroy -- отпустить внутренние proxy в пул, затем
-- базовый destroy (каскад снесёт узлы частей).
-- M16: если окно было modal — снять overlay + dispatcher перед уничтожением.
function WindowMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    if win and win.modal and win.modal.active and k then
        k.dispatcher:popModal(self.id)
        if win.modal.overlay and win.modal.overlay:isAlive() then
            win.modal.overlay:destroy()
            k.proxy:release(win.modal.overlay)
        end
        win.modal = nil
    end
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

--- Metatable window: widget-методы поверх базовых методов proxy.
local function makeWindowMt(baseMethods)
    return { __index = function(_, k)
        local m = WindowMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.window(props) -- Window 2.0 (M12): NODE_WINDOW + composite parts.
-- props: title, titleBar, draggable (default true при наличии bar),
-- resizable, closable, modal, minW, minH, onClose, titleColor,
-- titleTextColor + общие (x/y/w/h/color/layer/children/...).
function UI:window(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_WINDOW, nil)
    applyCommon(node, props)

    -- M12: composite metatable поверх базовых методов (ADR-016)
    if not self._windowMt then
        self._windowMt = makeWindowMt(k.proxy.methods)
    end
    setmetatable(node, self._windowMt)
    node._kernel = k
    local base = k.proxy.methods
    node._win = {
        baseSetSize = base.setSize,
        baseDestroy = base.destroy,
        draggable = props.draggable ~= false,
        resizable = props.resizable == true,
        closable  = props.closable == true,
        minW = props.minW or WIN_MIN_W,
        minH = props.minH or WIN_MIN_H,
    }
    local parts = {}
    node._parts = parts

    local w = props.w or DEFAULTS.window.w
    local h = props.h or DEFAULTS.window.h

    -- Title bar: есть при title; titleBar=true -- bar без подписи (drag-хвост).
    -- Bare window (M7-совместимость) -- без bar, не draggable.
    local showBar = props.title ~= nil or props.titleBar == true
    if showBar then
        local bar = k:create(C.NODE_PANEL, node)
        bar:setPosition(0, 0)
        bar:setColor(resolveColor(props.titleColor) or COLOR_TITLEBAR)
        bar:setZIndex(10) -- выше пользовательского контента (z=0)
        parts.bar = bar

        if props.title then
            local t = k:create(C.NODE_TEXT, bar)
            t:setPosition(4, 2)
            t:setColor(resolveColor(props.titleTextColor) or COLOR_TEXT)
            t:setText(props.title)
            parts.title = t
        end

        if node._win.closable then
            local cbtn = k:create(C.NODE_TEXT, bar)
            cbtn:setLayoutMode(C.LAY_REL)
            cbtn:setPosition(1, 0.5)     -- правый край bar, вертикальный центр
            cbtn:setAnchor(C.ANCHOR_MR)
            cbtn:setSize(CLOSE_W, CLOSE_H)
            cbtn:setColor(0xFFFF6060)
            cbtn:setText("x")
            cbtn:setZIndex(11)
            parts.close = cbtn
            cbtn:on("click", function() node:close() end)
        end

        -- M12: drag через dispatcher capture (ADR-016). Клик по close
        -- drag не стартует (target == close).
        if node._win.draggable then
            local closeId = parts.close and parts.close.id or nil
            bar:on("mousedown", function(e)
                if e.button ~= "left" then return end
                if not node._win or not node._win.draggable then return end
                if closeId ~= nil and e.target == closeId then return end
                local wx, wy = node:getPosition()
                local grabDX = (e.x or 0) - wx
                local grabDY = (e.y or 0) - wy
                k.dispatcher:beginDrag(function(px, py)
                    if not node:isAlive() then return end
                    node:setPosition(px - grabDX, py - grabDY)
                end)
                node:bringToFront()
            end)
        end
    end

    -- M12: resize grip -- LAY_REL(1,1)+ANCHOR_BR, следует за окном сам.
    if node._win.resizable then
        local grip = k:create(C.NODE_PANEL, node)
        grip:setLayoutMode(C.LAY_REL)
        grip:setPosition(1, 1)
        grip:setAnchor(C.ANCHOR_BR)
        grip:setSize(GRIP_W, GRIP_H)
        grip:setColor(0x80FFFFFF)
        grip:setZIndex(10)
        parts.grip = grip
        grip:on("mousedown", function(e)
            if e.button ~= "left" then return end
            if not node._win or not node._win.resizable then return end
            local startW, startH = node:getSize()
            local startPX, startPY = e.x or 0, e.y or 0
            k.dispatcher:beginDrag(function(px, py)
                if not node:isAlive() then return end
                node:setSize(startW + (px - startPX), startH + (py - startPY))
            end)
            node:bringToFront()
        end)
    end

    -- M12: любой mousedown по окну (бабблинг от любой части) -- наверх
    node:on("mousedown", function() node:bringToFront() end)

    if props.modal then node:setModal(props.modal) end
    if props.onClose then node:on("close", props.onClose) end

    -- Единая точка применения размера (override обновит части)
    node:setSize(w, h)

    attachChildren(k, node, props)
    return node
end

--- ui.panel(props) — NODE_PANEL.
function UI:panel(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_PANEL, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.panel.w, props.h or DEFAULTS.panel.h)
    end
    attachChildren(self.kernel, node, props)
    return node
end

--- ui.button(props) — NODE_BUTTON (фон) + auto-child NODE_TEXT при props.text.
-- props: text, onClick, color, x, y, w, h, ...
function UI:button(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_BUTTON, nil)
    applyCommon(node, props)
    local w = props.w or DEFAULTS.button.w
    local h = props.h or DEFAULTS.button.h
    if props.w == nil or props.h == nil then
        node:setSize(w, h)
    end
    if props.text then
        -- Ядро рисует узел с text как CMD_TEXT (без фона), поэтому подпись —
        -- отдельный auto-child на весь размер кнопки (M7-решение, см. header).
        local t = k:create(C.NODE_TEXT, node)
        t:setPosition(0, 0):setSize(w, h)
        t:setColor(resolveColor(props.textColor) or COLOR_TEXT)
        t:setText(props.text)
    end
    if props.onClick then
        node:on("click", props.onClick)
    end
    attachChildren(k, node, props)
    return node
end

--- ui.label(props) — NODE_TEXT: только подпись.
function UI:label(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_TEXT, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.label.w, props.h or DEFAULTS.label.h)
    end
    if props.text then
        node:setColor(resolveColor(props.color) or COLOR_TEXT)
        node:setText(props.text)
    end
    attachChildren(self.kernel, node, props)
    return node
end

--- ui.image(props) — NODE_IMAGE: props.texture — handle dxImage (pass-through).
function UI:image(props)
    props = props or {}
    local node = self.kernel:create(C.NODE_IMAGE, nil)
    applyCommon(node, props)
    if props.w == nil or props.h == nil then
        node:setSize(props.w or DEFAULTS.image.w, props.h or DEFAULTS.image.h)
    end
    if props.texture then
        node:setTexture(props.texture)
    end
    attachChildren(self.kernel, node, props)
    return node
end

-- ======================= M13: ScrollPanel (ADR-017) =====================
-- Composite-proxy (тот же паттерн, что Window M12): один handle -> три
-- категории узлов:
--   * viewport  -- панель с clip=true (визуальная граница)
--   * content   -- невидимый контейнер (size 0x0, Builder M13 skip'ает
--                  нулевые RECT); пользовательские дети прикрепляются СЮДА
--                  через props.children ИЛИ вручную через scroll:getContent()
--   * track + thumb -- по одной паре на ось (v/h/both)
-- Скроллинг смещает content (setPosition -scrollX, -scrollY) -- дети
-- "выезжают" через clip-регион viewport'а. Не пересчитываем дерево;
-- существующий clip/builder/batcher M2/M5/M8 справляются.

local TRACK_W    = 8   -- толщина вертикальной / высота горизонтальной полосы
local THUMB_MIN  = 20  -- минимальный размер thumb
local WHEEL_STEP = 40  -- px за один "щелчок" колеса по умолчанию
local SMOOTH_MS  = 120 -- длительность smooth scroll
local OVERSCAN   = 2   -- строки запаса сверху/снизу при виртуализации

local ScrollMethods = {}

--- Внутренний: пересчёт scroll max + геометрия полос прокрутки + thumb.
-- Вызывается на setScroll/setSize/refresh. Стоит дешево (несколько setSize).
function ScrollMethods:_layoutScrollbar()
    local sp = self._sp
    local parts = self._parts
    local s = self._kernel.storage
    local slot = s.idToSlot[self.id]
    local vw, vh = s.w[slot], s.h[slot]
    local cw, ch = self:_contentSize()
    local maxX, maxY = cw - vw, ch - vh
    if maxX < 0 then maxX = 0 end
    if maxY < 0 then maxY = 0 end
    sp.maxX, sp.maxY = maxX, maxY
    sp.contentW, sp.contentH = cw, ch

    -- vertical
    if parts.trackV then
        local showV = maxY > 0 and (sp.axis == "v" or sp.axis == "both")
        if showV then
            parts.trackV:setVisible(true)
            parts.trackV:setPosition(vw - TRACK_W, 0)
            parts.trackV:setSize(TRACK_W, vh)
            local thumbH = math.max(THUMB_MIN, math.floor(vh * vh / ch))
            local t = maxY > 0 and (sp.scrollY / maxY) or 0
            local trackLen = vh
            parts.thumbV:setSize(TRACK_W - 2, thumbH)
            parts.thumbV:setPosition(vw - TRACK_W + 1, math.floor(t * (trackLen - thumbH)))
            parts.thumbV:setVisible(true)
        else
            parts.trackV:setVisible(false)
            parts.thumbV:setVisible(false)
        end
    end

    -- horizontal
    if parts.trackH then
        -- горизонтальная полоса укорачивается, если есть вертикальная
        local vReserve = parts.trackV and parts.trackV:isVisible() and TRACK_W or 0
        local showH = maxX > 0 and (sp.axis == "h" or sp.axis == "both")
        if showH then
            parts.trackH:setVisible(true)
            parts.trackH:setPosition(0, vh - TRACK_W)
            parts.trackH:setSize(vw - vReserve, TRACK_W)
            local thumbW = math.max(THUMB_MIN, math.floor(vw * vw / cw))
            local t = maxX > 0 and (sp.scrollX / maxX) or 0
            local trackLen = vw - vReserve
            parts.thumbH:setSize(thumbW, TRACK_W - 2)
            parts.thumbH:setPosition(math.floor(t * (trackLen - thumbW)), vh - TRACK_W + 1)
            parts.thumbH:setVisible(true)
        else
            parts.trackH:setVisible(false)
            parts.thumbH:setVisible(false)
        end
    end
end

--- Внутренний: вычислить размер контента (явный, виртуальный или auto).
function ScrollMethods:_contentSize()
    local sp = self._sp
    local s = self._kernel.storage
    local slot = s.idToSlot[self.id]
    local vw, vh = s.w[slot], s.h[slot]

    if sp.provider then
        local n = sp.provider.count() or 0
        local ih = sp.provider.itemHeight or 1
        -- itemWidth: опционально (горизонтальная виртуализация -- позже);
        -- по умолчанию ширина контента равна ширине viewport.
        local iw = sp.provider.itemWidth or vw
        return iw, n * ih
    end

    -- auto-measure по прямым детям content
    local mx, my = 0, 0
    local cSlot = s.idToSlot[self._parts.content.id]
    if cSlot then
        local childId = s.firstChild[cSlot]
        while childId ~= C.NIL_ID do
            local cs = s.idToSlot[childId]
            if cs then
                local cx2 = (s.x[cs] or 0) + (s.w[cs] or 0)
                local cy2 = (s.y[cs] or 0) + (s.h[cs] or 0)
                if cx2 > mx then mx = cx2 end
                if cy2 > my then my = cy2 end
            end
            childId = s.nextSibling[cs]
        end
    end

    local cw = sp.contentW or (mx > 0 and mx or vw)
    local ch = sp.contentH or (my > 0 and my or vh)
    return cw, ch
end

--- Установить позицию скролла (логические координаты; clamped + emit).
function ScrollMethods:setScroll(x, y)
    local sp = self._sp
    if not sp then return self end -- composite уже уничтожен
    self:_layoutScrollbar()         -- пересчитать max по актуальному contentSize
    if x < 0 then x = 0 elseif x > sp.maxX then x = sp.maxX end
    if y < 0 then y = 0 elseif y > sp.maxY then y = sp.maxY end
    sp.scrollX, sp.scrollY = x, y
    local parts = self._parts
    if sp.smooth then
        parts.content:animateTo({ x = -x, y = -y }, SMOOTH_MS, C.EASE_OUT)
    else
        parts.content:setPosition(-x, -y)
    end
    self:_layoutScrollbar()         -- пересчитать thumb по новой позиции
    if sp.provider then self:_virtualApply() end
    self._kernel.eventBus:emit(self.id, C.EVENT_SCROLL, { x = x, y = y })
    return self
end

function ScrollMethods:getScroll()
    local sp = self._sp
    if not sp then return 0, 0 end
    return sp.scrollX, sp.scrollY
end

function ScrollMethods:getScrollMax()
    local sp = self._sp
    if not sp then return 0, 0 end
    return sp.maxX, sp.maxY
end

--- Дельта скролла (используется обработчиком wheel, drag thumb и т.п.).
function ScrollMethods:scrollBy(dx, dy)
    local sp = self._sp
    return self:setScroll(sp.scrollX + dx, sp.scrollY + dy)
end

function ScrollMethods:scrollToPercent(px, py)
    local sp = self._sp
    return self:setScroll(px * sp.maxX, py * sp.maxY)
end

--- Явный размер контента (сбрасывает auto-measure). nil = авто.
function ScrollMethods:setContentSize(w, h)
    local sp = self._sp
    sp.contentW, sp.contentH = w, h
    return self:refresh()
end

--- Получить content-узел (для ручного прикрепления детей и child-менеджмента).
function ScrollMethods:getContent()
    return self._parts and self._parts.content or nil
end

--- Пересчитать content size, clamp скролл, переразложить полосы и
-- (если виртуально) пересобрать видимый диапазон. Вызывайте после
-- добавления/удаления/изменения размера реальных детей контента.
function ScrollMethods:refresh()
    local sp = self._sp
    if not sp then return self end
    -- setScroll с текущей позицией пересчитает max и заново разложит полосы
    self:setScroll(sp.scrollX, sp.scrollY)
    return self
end

--- Внутренний: виртуальный пул строк. Видимый диапазон -- first..last
-- (1-based индексы для пользователя); реальные узлы-строки переиспользуются,
-- "окно" едет по списку (тот же freelist-принцип, что Storage/ProxyPool).
function ScrollMethods:_virtualApply()
    local sp = self._sp
    local prov = sp.provider
    if not prov then return end
    local s = self._kernel.storage
    local slot = s.idToSlot[self.id]
    local vw, vh = s.w[slot], s.h[slot]
    local ih = prov.itemHeight or 1
    local n = prov.count() or 0
    local first = math.floor(sp.scrollY / ih)
    if first < 0 then first = 0 end
    local visible = math.ceil(vh / ih) + OVERSCAN
    local last = first + visible - 1
    if last > n - 1 then last = n - 1 end
    if last < first then first, last = 0, -1 end

    if first ~= sp.rangeFirst or last ~= sp.rangeLast then
        sp.rangeFirst, sp.rangeLast = first, last
        local need = last - first + 1
        if need < 0 then need = 0 end
        local k = self._kernel
        local parts = self._parts
        local rows = sp.rows

        -- создать недостающие строки пула
        while #rows < need do
            local row
            if prov.create then
                row = prov.create(self, #rows + 1)
            else
                row = k:create(C.NODE_PANEL, parts.content)
                row:setSize(vw, ih)
            end
            rows[#rows + 1] = row
        end

        -- bind видимых
        for i = 1, need do
            local row = rows[i]
            local index = first + i                 -- 1-based для пользователя
            row:setVisible(true)
            row:setPosition(0, (index - 1) * ih)
            if prov.bind then prov.bind(row, index) end
        end

        -- лишние строки пула скрыть (остаются в пуле)
        for i = need + 1, #rows do
            rows[i]:setVisible(false)
        end
    end
end

--- Подключить провайдер виртуальных строк. provider = {
--   count() -> n,
--   itemHeight = h,
--   [itemWidth = w],
--   [bind(rowProxy, index)]     -- заполнить строку данными index
--   [create(scroll, slot)]      -- создать свою строку; default = panel
-- }
function ScrollMethods:setVirtualProvider(provider)
    local sp = self._sp
    if sp.provider == provider then return self end
    -- освободить старый пул строк
    if sp.rows and #sp.rows > 0 then
        local k = self._kernel
        for i = 1, #sp.rows do
            local r = sp.rows[i]
            if r then k:destroy(r) end
        end
        sp.rows = {}
    end
    sp.provider = provider
    sp.rangeFirst, sp.rangeLast = 0, -1
    return self:refresh()
end

--- Override setSize: viewport resize -- переразложить полосы + clamp scroll
-- + виртуальный пересчёт. Геометрия полос/треков зависит от vw/vh.
function ScrollMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    -- setScroll(current) пересчитает max по новому viewport и разложит полосы
    local sp = self._sp
    return self:setScroll(sp.scrollX, sp.scrollY)
end

--- Override destroy: освободить пул строк + parts + базовый destroy.
function ScrollMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    local sp = self._sp
    if sp and sp.rows then
        for i = 1, #sp.rows do
            local r = sp.rows[i]
            if r then k.proxy:release(r) end
        end
        sp.rows = nil
    end
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._sp = nil
    self._kernel = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

--- Metatable для ScrollPanel: методы виджета поверх базовых методов proxy.
local function makeScrollMt(baseMethods)
    return { __index = function(_, k)
        local m = ScrollMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- Локальный хелпер: построить полосу прокрутки (track + thumb) на нужной оси.
-- isVertical = true: вертикальная справа; false: горизонтальная снизу.
-- Возвращает (track, thumb). track и thumb дети viewport (node).
local function buildScrollbar(k, node, axis, isVertical)
    local track = k:create(C.NODE_PANEL, node)
    track:setColor(0xFF303040)
    track:setZIndex(10)
    track:setVisible(false)
    local thumb = k:create(C.NODE_PANEL, track)
    thumb:setColor(0xFF808090)
    thumb:setZIndex(11)
    return track, thumb
end

--- Локальный хелпер: навесить drag thumb через dispatcher capture.
-- 'self' -- proxy ScrollPanel (нужен для setScroll + isAlive guard).
local function wireThumbDrag(self, thumb, isVertical)
    local k = self._kernel
    thumb:on("mousedown", function(e)
        if e.button ~= "left" then return end
        if not self._win then return end
        local s = k.storage
        local tSlot = s.idToSlot[thumb.id]
        if not tSlot then return end
        -- parent (track) id живёт в storage, не в proxy
        local trackId = s.parent[tSlot]
        if not trackId or trackId == C.NIL_ID then return end
        local trSlot = s.idToSlot[trackId]
        if not trSlot then return end

        local thumbWorld = (isVertical and s.worldY[tSlot]) or s.worldX[tSlot]
        local grab = ((isVertical and (e.y or 0)) or (e.x or 0)) - thumbWorld

        k.dispatcher:beginDrag(function(px, py)
            if not self:isAlive() then return end
            local t = (isVertical and (py - grab)) or (px - grab)
            local trackWorld = (isVertical and s.worldY[trSlot]) or s.worldX[trSlot]
            local localPos = t - trackWorld
            local trackLen = (isVertical and s.h[trSlot]) or s.w[trSlot]
            local thumbLen = (isVertical and s.h[tSlot]) or s.w[tSlot]
            local denom = trackLen - thumbLen
            if denom <= 0 then return end
            local frac = localPos / denom
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            local sp = self._sp
            local maxScroll = (isVertical and sp.maxY) or sp.maxX
            local newScroll = frac * maxScroll
            if isVertical then
                self:setScroll(sp.scrollX, newScroll)
            else
                self:setScroll(newScroll, sp.scrollY)
            end
        end)
    end)
end

--- ui.scrollpanel(props) -- M13 ScrollPanel (ADR-017).
-- props: axis ("v"|"h"|"both", default "v"), scrollbar (default true),
-- smooth (default false), wheelStep (px на щелчок), contentW, contentH,
-- children (прикрепляются к content), + общие (x/y/w/h/color/layer).
function UI:scrollpanel(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)
    node:setClip(true)                                -- M5 viewport с клипом

    -- composite metatable поверх базовых методов (тот же паттерн, что Window M12)
    if not self._scrollMt then
        self._scrollMt = makeScrollMt(k.proxy.methods)
    end
    setmetatable(node, self._scrollMt)
    node._kernel = k
    local base = k.proxy.methods
    node._win = {
        baseSetSize = base.setSize,
        baseDestroy = base.destroy,
    }
    node._sp = {
        axis      = props.axis or "v",
        smooth    = props.smooth == true,
        wheelStep = props.wheelStep,
        contentW  = props.contentW,
        contentH  = props.contentH,
        scrollX   = 0,
        scrollY   = 0,
        rows      = {},
        rangeFirst = 0,
        rangeLast  = -1,
    }
    local parts = {}
    node._parts = parts

    -- content: 0x0 PANEL, enabled=false (Builder M13 skip'ает команду; не
    -- участвует в hit-test; дети не задевают видимость родителя).
    local content = k:create(C.NODE_PANEL, node)
    content:setPosition(0, 0)
    content:setSize(0, 0)
    content:setEnabled(false)
    parts.content = content

    -- полосы прокрутки (опционально)
    local axis = node._sp.axis
    local hasV = (axis == "v" or axis == "both") and props.scrollbar ~= false
    local hasH = (axis == "h" or axis == "both") and props.scrollbar ~= false
    if hasV then
        parts.trackV, parts.thumbV = buildScrollbar(k, node, axis, true)
        wireThumbDrag(node, parts.thumbV, true)
    end
    if hasH then
        parts.trackH, parts.thumbH = buildScrollbar(k, node, axis, false)
        wireThumbDrag(node, parts.thumbH, false)
    end

    -- wheel: эмиссия EVENT_WHEEL на любой части viewport (через bubble
    -- ловим клик И над детьми контента). Бабблинг -- натуральный.
    node:on("wheel", function(e)
        local sp = node._sp
        if not sp then return end
        local step = node._sp.wheelStep or WHEEL_STEP
        local axis = node._sp.axis
        local dz = e.dz or 0
        if axis == "h" then
            node:scrollBy(-dz * step, 0)
        else
            -- "v" и "both": колесо скроллит по вертикали (DGS-конвенция)
            node:scrollBy(0, -dz * step)
        end
    end)

    -- дети -- в content (через attachChildren), не в viewport.
    attachChildren(k, parts.content, props)

    -- первичный layout полос + content (создаст default size для auto-measure).
    node:setSize(props.w or DEFAULTS.panel.w, props.h or DEFAULTS.panel.h)
    -- теперь, когда viewport имеет размер, рассчитать layout полос один раз
    node:_layoutScrollbar()

    return node
end

-- ==================== M15: Edit 2.0 (ADR-019) ========================
-- Composite-proxy (Window M12 / ScrollPanel M13 / Edit M14):
-- один handle -> узлы:
--   * base  -- PANEL (фон, border, hit-test)
--   * text  -- TEXT (введённый текст; \n = перенос строки, multiline)
--   * ph    -- TEXT (placeholder, виден только когда text == "")
--   * cursor-- PANEL (тонкий курсор, z=30)
--   * selN  -- PANEL из пула ed.selNodes (highlight выделения, z=5)
-- M15 (ADR-019) добавляет к M14:
--   * Selection: anchor/cursor модель, [selStart, selEnd), reuses pool
--   * Drag-select: mousedown -> beginDrag -> расширение выделения
--   * Clipboard: ctrl+a/c/v/x через kernel.clipboard (виртуальный буфер)
--   * Multiline: props.multiline, enter вставляет \n, UP/DOWN + goalCol
--   * Placeholder render: ph-узел, серый, виден при пустом text
-- Ключи -- СТРОКИ из MTA key map ("backspace", "arrow_l", ...), mods --
-- строка "ctrl"/"shift"/"" (см. Dispatcher.onKeyDown M15).

local EDIT_CURSOR_W = 2   -- ширина курсора в px
local EDIT_PAD_X    = 4   -- внутренний отступ текста слева/справа
local EDIT_PAD_Y    = 2   -- внутренний отступ текста сверху
local EDIT_CHAR_W   = 7   -- ширина символа (monospace assumption)
local EDIT_LINE_H   = 15  -- высота строки
local EDIT_SEL_COLOR = 0x663399FF -- выделение (полупрозрачный синий)
local EDIT_PH_COLOR  = 0xFF888888 -- placeholder (серый)

local EditMethods = {}

-- --- helpers: split по \n + lineStart (cold path - не hot frame)
local function splitLines(s)
    local lines = {}
    local start = 1
    while true do
        local nl = s:find("\n", start, true)
        if not nl then
            lines[#lines + 1] = s:sub(start)
            break
        end
        lines[#lines + 1] = s:sub(start, nl - 1)
        start = nl + 1
    end
    return lines
end

local function buildLines(ed)
    ed.lines = splitLines(ed.text)
    ed.lineStart = {}
    local acc = 1
    for i = 1, #ed.lines do
        ed.lineStart[i] = acc
        acc = acc + #ed.lines[i] + 1
    end
end

-- 1-based строка текста, в которой лежит 1-based позиция idx
local function rowOf(ed, idx)
    for i = 1, #ed.lines do
        if idx <= ed.lineStart[i] + #ed.lines[i] then return i end
    end
    return #ed.lines
end

-- курсор (0-based, chars before insertion) -> (row 1-based, col 0-based)
local function cursorToRowCol(ed, cursor)
    local row = rowOf(ed, cursor + 1)
    local col = (cursor + 1) - ed.lineStart[row]
    if col < 0 then col = 0 end
    return row, col
end

-- экранные коорд -> курсор (0-based). М30: worldX/worldY (не local —
-- getPosition() возвращает локальные, ADR-016; вложенные Edit работают).
local function screenToCursor(self, sx, sy)
    local ed = self._ed
    local parts = self._parts
    if not ed or not parts then return 0 end
    local slot = self._kernel.storage.idToSlot[self.id]
    if not slot then return 0 end
    local wx, wy = self._kernel.storage.worldX[slot], self._kernel.storage.worldY[slot]
    local lx = sx - wx - EDIT_PAD_X
    local ly = sy - wy - EDIT_PAD_Y
    if #ed.lines < 1 then return 0 end
    local row = math.floor(ly / EDIT_LINE_H) + 1
    if row < 1 then row = 1 end
    if row > #ed.lines then row = #ed.lines end
    local rowlen = #ed.lines[row]
    local col = math.floor(lx / EDIT_CHAR_W + 0.5)
    if col < 0 then col = 0 end
    if col > rowlen then col = rowlen end
    return (ed.lineStart[row] - 1) + col
end

-- --- внутренний: sync selection highlight (pool reuses, hide extras)
function EditMethods:_syncSel()
    local ed = self._ed
    local parts = self._parts
    if not ed or not parts or not parts.base then return end
    local a, b = ed.selAnchor, ed.cursor
    if a > b then a, b = b, a end
    ed.selStart, ed.selEnd = a, b
    local hasSel = (b - a) > 0 and ed.hasFocus and not ed.readonly
    local k = self._kernel
    local pool = ed.selNodes
    local used = 0

    if hasSel then
        -- для каждой строки: пересечение [a, b) (0-based) с [lineStart-1, lineStart-1+len)
        for i = 1, #ed.lines do
            local ls0 = ed.lineStart[i] - 1
            local len = #ed.lines[i]
            local from = math.max(a - ls0, 0)
            local to = math.min(b - ls0, len)
            if to > from then
                used = used + 1
                local p = pool[used]
                if not p then
                    p = k:create(C.NODE_PANEL, parts.base)
                    p:setColor(EDIT_SEL_COLOR)
                    p:setZIndex(5)
                    pool[used] = p
                end
                p:setPosition(EDIT_PAD_X + from * EDIT_CHAR_W, EDIT_PAD_Y + (i - 1) * EDIT_LINE_H)
                p:setSize((to - from) * EDIT_CHAR_W, EDIT_LINE_H)
                p:setVisible(true)
            end
        end
    end

    -- лишние - скрыть (не уничтожать, пул)
    for i = used + 1, #pool do
        if pool[i] then pool[i]:setVisible(false) end
    end
end

-- --- внутренний: полный рендер текста, курсора, placeholder, selection
function EditMethods:_renderText()
    local ed = self._ed
    if not ed then return end
    local parts = self._parts
    if not parts or not parts.text then return end

    local text = ed.text
    if ed.maxChars > 0 and #text > ed.maxChars then
        text = text:sub(1, ed.maxChars)
    end
    ed.text = text -- нормализация по maxChars

    buildLines(ed)
    parts.text:setText(text)

    -- высота текстового узла растёт с числом строк (multiline)
    local w = parts.text.w or 100
    parts.text:setSize(math.max(w, 10), math.max(EDIT_LINE_H, #ed.lines * EDIT_LINE_H))

    -- placeholder
    if parts.ph then
        local show = (ed.text == "") and (ed.placeholder ~= "") and not ed.hasFocus
        parts.ph:setVisible(show)
    end

    -- cursor
    local row, col = cursorToRowCol(ed, ed.cursor)
    if parts.cursor then
        parts.cursor:setPosition(EDIT_PAD_X + col * EDIT_CHAR_W,
                                 EDIT_PAD_Y + (row - 1) * EDIT_LINE_H)
        parts.cursor:setVisible(ed.hasFocus and not ed.readonly)
    end

    self:_syncSel()
end

-- --- внутренний: после изменения текста
function EditMethods:_emitChange()
    local ed = self._ed
    if not ed then return end
    for i = 1, #ed.changeCbs do
        ed.changeCbs[i](ed.text)
    end
end

-- --- внутренний: заменить выделение текстом, cursor встаёт в конец вставки
function EditMethods:_replaceSel(text)
    local ed = self._ed
    local a, b = ed.selStart, ed.selEnd
    ed.text = ed.text:sub(1, a) .. text .. ed.text:sub(b + 1)
    ed.cursor = a + #text
    ed.selAnchor = ed.cursor
    if ed.maxChars > 0 and #ed.text > ed.maxChars then
        ed.text = ed.text:sub(1, ed.maxChars)
        ed.cursor = math.min(ed.cursor, #ed.text)
        ed.selAnchor = ed.cursor
    end
end

-- --- внутренний: ctrl-шорткаты (возвращает true если обработан)
function EditMethods:_handleCtrlShortcut(key, mods)
    local ed = self._ed
    local isCtrl = mods and mods:find("ctrl") ~= nil
    if not isCtrl then return false end

    if key == "a" then
        ed.selAnchor = 0
        ed.cursor = #ed.text
        self:_syncSel()
        return true
    elseif key == "c" then
        if ed.selEnd > ed.selStart then
            self._kernel.clipboard = ed.text:sub(ed.selStart + 1, ed.selEnd)
        end
        return true
    elseif key == "v" then
        if self._kernel.clipboard ~= "" then
            self:_replaceSel(self._kernel.clipboard)
            self:_renderText()
            self:_emitChange()
        end
        return true
    elseif key == "x" then
        if ed.selEnd > ed.selStart then
            self._kernel.clipboard = ed.text:sub(ed.selStart + 1, ed.selEnd)
            self:_replaceSel("")
            self:_renderText()
            self:_emitChange()
        end
        return true
    end
    return false
end

-- --- внутренний: специальные клавиши (MTA key string names)
function EditMethods:_handleKey(key, state, mods)
    if state ~= "down" then return end
    local ed = self._ed
    if not ed or ed.readonly then return end

    if self:_handleCtrlShortcut(key, mods) then return end

    if key == "backspace" then
        if ed.selEnd > ed.selStart then
            self:_replaceSel("")
        elseif ed.cursor > 0 then
            ed.text = ed.text:sub(1, ed.cursor - 1) .. ed.text:sub(ed.cursor + 1)
            ed.cursor = ed.cursor - 1
            ed.selAnchor = ed.cursor
        end
        self:_renderText()
        self:_emitChange()
    elseif key == "delete" then
        if ed.selEnd > ed.selStart then
            self:_replaceSel("")
        elseif ed.cursor < #ed.text then
            ed.text = ed.text:sub(1, ed.cursor) .. ed.text:sub(ed.cursor + 2)
        end
        self:_renderText()
        self:_emitChange()
    elseif key == "arrow_l" then
        local shift = mods and mods:find("shift") ~= nil
        if not shift and ed.selEnd > ed.selStart then
            ed.cursor = ed.selStart -- collapse к началу
        elseif ed.cursor > 0 then
            ed.cursor = ed.cursor - 1
        end
        if not shift then ed.selAnchor = ed.cursor end
        self:_renderText()
    elseif key == "arrow_r" then
        local shift = mods and mods:find("shift") ~= nil
        if not shift and ed.selEnd > ed.selStart then
            ed.cursor = ed.selEnd -- collapse к концу
        elseif ed.cursor < #ed.text then
            ed.cursor = ed.cursor + 1
        end
        if not shift then ed.selAnchor = ed.cursor end
        self:_renderText()
    elseif key == "arrow_u" or key == "arrow_d" then
        if ed.multiline then
            local row, col = cursorToRowCol(ed, ed.cursor)
            if not ed.goalCol then ed.goalCol = col end
            local target = (key == "arrow_u") and (row - 1) or (row + 1)
            if target >= 1 and target <= #ed.lines then
                local col2 = math.min(ed.goalCol, #ed.lines[target])
                ed.cursor = (ed.lineStart[target] - 1) + col2
                local shift = mods and mods:find("shift") ~= nil
                if not shift then ed.selAnchor = ed.cursor end
            end
        end
        self:_renderText()
    elseif key == "home" then
        local shift = mods and mods:find("shift") ~= nil
        local row = rowOf(ed, ed.cursor + 1)
        ed.cursor = ed.lineStart[row] - 1
        if not shift then ed.selAnchor = ed.cursor end
        self:_renderText()
    elseif key == "end" then
        local shift = mods and mods:find("shift") ~= nil
        local row = rowOf(ed, ed.cursor + 1)
        ed.cursor = ed.lineStart[row] + #ed.lines[row] - 1
        if not shift then ed.selAnchor = ed.cursor end
        self:_renderText()
    elseif key == "enter" then
        if ed.multiline then
            self:_replaceSel("\n")
            self:_renderText()
            self:_emitChange()
        else
            for i = 1, #ed.enterCbs do
                ed.enterCbs[i]()
            end
        end
    elseif key == "tab" then
        -- tab: no-op (M14) — MTA focus — управляет Dispatcher
    end
end

-- ==================== Edit: публичный API (ADR-018/019 §6) ==============
-- Восстановление (M20): getText/setText/getSelection/setSelection/onChange/
-- onEnter отсутствовали — добавлены по ADR-019 §6.

function EditMethods:getText()
    local ed = self._ed
    if not ed then return "" end
    return ed.text
end

function EditMethods:setText(text)
    local ed = self._ed
    if not ed then return self end
    ed.text = tostring(text or "")
    ed.cursor = #ed.text
    ed.selAnchor = ed.cursor
    self:_renderText()
    self:_emitChange()
    return self
end

function EditMethods:getCursor()
    local ed = self._ed
    if not ed then return 0 end
    return ed.cursor
end

function EditMethods:setCursor(pos)
    local ed = self._ed
    if not ed then return self end
    ed.cursor = pos
    if ed.cursor < 0 then ed.cursor = 0 end
    if ed.cursor > #ed.text then ed.cursor = #ed.text end
    ed.selAnchor = ed.cursor
    self:_renderText()
    return self
end

function EditMethods:getSelection()
    local ed = self._ed
    if not ed then return 0, 0 end
    return ed.selStart or 0, ed.selEnd or 0
end

function EditMethods:setSelection(start, finish)
    local ed = self._ed
    if not ed then return self end
    ed.selAnchor = start or 0
    ed.cursor = finish or ed.selAnchor
    self:_syncSel()
    return self
end

function EditMethods:onChange(fn)
    local ed = self._ed
    if ed then ed.changeCbs[#ed.changeCbs + 1] = fn end
    return self
end

function EditMethods:onEnter(fn)
    local ed = self._ed
    if ed then ed.enterCbs[#ed.enterCbs + 1] = fn end
    return self
end

function EditMethods:setReadonly(v)
    local ed = self._ed
    if ed then
        ed.readonly = v == true
        self:_renderText()
    end
    return self
end

function EditMethods:setPlaceholder(text)
    local ed = self._ed
    if ed then
        ed.placeholder = text or ""
        self:_renderText()
    end
    return self
end


-- ==================== M15-tail: Edit builder (ADR-018/019) ==============
-- Восстановление (M20): билдер Edit потерялся в ранних сессиях — методы
-- EditMethods сохранились, билдер/метатаблица восстановлены по ADR-018/019.

--- Override destroy: release sel-пула + parts + baseDestroy.
function EditMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    local ed = self._ed
    if k and k.focusables then k.focusables[self.id] = nil end -- M20
    if ed and ed.selNodes then
        for i = 1, #ed.selNodes do
            if ed.selNodes[i] then k.proxy:release(ed.selNodes[i]) end
        end
    end
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._ed = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeEditMt(baseMethods)
    return { __index = function(_, k)
        local m = EditMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.edit(props) — M15 Edit 2.0 (ADR-019): text input composite.
-- props: text, placeholder, readonly, multiline, maxLength, onChange,
-- onEnter + общие. События: focus/blur (auto), text, key, mousedown
-- (focus + caret + drag-select). Ключи — MTA-строки (Dispatcher M15).
function UI:edit(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._editMt then
        self._editMt = makeEditMt(k.proxy.methods)
    end
    setmetatable(node, self._editMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._ed = {
        text = tostring(props.text or ""),
        placeholder = props.placeholder or "",
        readonly = props.readonly == true,
        multiline = props.multiline == true,
        maxChars = props.maxLength or 0, -- _renderText использует maxChars
        changeCbs = {},
        enterCbs = {},
        selNodes = {},  -- пул highlight-панелей (freelist, M15)
        selAnchor = 0,
        cursor = 0,
        hasFocus = false,
        lines = {},
        lineStart = {},
    }
    if props.onChange then node._ed.changeCbs[#node._ed.changeCbs + 1] = props.onChange end
    if props.onEnter then node._ed.enterCbs[#node._ed.enterCbs + 1] = props.onEnter end

    local parts = {}
    node._parts = parts
    parts.base = node -- _syncSel создаёт sel-узлы как детей base (ADR-019)
    local w = props.w or 160
    local h = props.h or (props.multiline and 64) or 24
    node:setSize(w, h)

    -- text (основной), ph (placeholder), cursor (курсор)
    local text = k:create(C.NODE_TEXT, node)
    text:setPosition(EDIT_PAD_X, EDIT_PAD_Y)
    text:setColor(COLOR_TEXT)
    text:setEnabled(false)
    text:setZIndex(2)
    text:setSize(w - EDIT_PAD_X * 2, h)
    parts.text = text

    local ph = k:create(C.NODE_TEXT, node)
    ph:setPosition(EDIT_PAD_X, EDIT_PAD_Y)
    ph:setColor(EDIT_PH_COLOR)
    ph:setEnabled(false)
    parts.ph = ph

    local cursor = k:create(C.NODE_PANEL, node)
    cursor:setColor(0xFFFFFFFF)
    cursor:setSize(EDIT_CURSOR_W, EDIT_LINE_H)
    cursor:setEnabled(false)
    cursor:setZIndex(30)
    parts.cursor = cursor

    -- M20 (ADR-024): реестр фокусируемых — modal auto-focus
    if k.focusables then k.focusables[node.id] = true end

    -- mousedown: focus + caret (Dispatcher уже фокусирует hit — дублируем
    -- для ясности; setFocus id == focusedId — no-op) + drag-select
    node:on("mousedown", function(e)
        k.dispatcher:setFocus(node.id)
        if not node:isAlive() then return end
        local ed = node._ed
        if not ed then return end
        ed.cursor = screenToCursor(node, e.x or 0, e.y or 0)
        ed.selAnchor = ed.cursor
        node:_renderText()
        if not ed.readonly then
            k.dispatcher:beginDrag(function(px, py)
                if not node:isAlive() then return end
                ed.cursor = screenToCursor(node, px, py)
                node:_syncSel()
            end)
        end
    end)

    -- ввод символов (EVENT_TEXT — текст из onClientKey)
    node:on("text", function(e)
        if not node._ed.hasFocus or node._ed.readonly then return end
        if not e.text or e.text == "" then return end
        node:_replaceSel(e.text)
        node:_renderText()
        node:_emitChange()
    end)

    -- специальные клавиши (EVENT_KEY — MTA-строки)
    node:on("key", function(e)
        if node._ed.hasFocus then
            node:_handleKey(e.key, e.state, e.mods)
        end
    end)

    node:on("focus", function()
        node._ed.hasFocus = true
        node:_renderText()
    end)
    node:on("blur", function()
        node._ed.hasFocus = false
        node:_renderText()
    end)

    node:_renderText()
    attachChildren(k, node, props)
    return node
end

-- ==================== M17: Popup + ContextMenu (ADR-021) ===============
-- Восстановление (M20): билдеры потерялись — дизайн по ADR-021, dispatcher
-- popupStack на месте (см. dispatcher.lua).

local PopupMethods = {}

--- Показать popup. x,y — экранные (по умолчанию текущая позиция).
function PopupMethods:show(x, y)
    if x ~= nil then self:setPosition(x, y) end
    self:setVisible(true)
    local k = self._kernel
    if k and not self._popupShown then
        k.dispatcher:pushPopup(self.id, function() self:hide() end)
        self._popupShown = true
    end
    -- M20 (ADR-024): fade-in поддерева (ANIM_OPACITY)
    if k then
        fadeSubtree(k, self.id, 0, 255, POPUP_FADE_MS, C.EASE_OUT)
    end
    return self
end

function PopupMethods:hide()
    self:setVisible(false)
    local k = self._kernel
    if k and self._popupShown then
        k.dispatcher:popPopup(self.id)
        self._popupShown = false
    end
    return self
end

function PopupMethods:isShown()
    return self:isVisible()
end

function PopupMethods:toggle(x, y)
    if self:isShown() then return self:hide() end
    return self:show(x, y)
end

local function makePopupMt(baseMethods)
    return { __index = function(_, k)
        local m = PopupMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.popup(props) — всплывающий PANEL на LAYER_POPUP (скрыт по умолчанию).
-- Dismiss по клику вне — бесплатный (Dispatcher.popupStack, M17).
function UI:popup(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._popupMt then
        self._popupMt = makePopupMt(k.proxy.methods)
    end
    setmetatable(node, self._popupMt)
    node._kernel = k
    node:setLayer(C.LAYER_POPUP)
    node:setVisible(false)
    local w = props.w or 160
    local h = props.h or 40
    node:setSize(w, h)
    attachChildren(k, node, props)
    return node
end

--- ui.contextmenu(props) — контекстное меню. props.items =
-- { { text=, onClick= }, ... }; itemHeight 24, w 160.
-- Наследует PopupMethods. Типовое: node:on("mousedown", function(e)
--   if e.button == "right" then menu:show(e.x, e.y) end end)
function UI:contextmenu(props)
    props = props or {}
    local k = self.kernel
    local node = self:popup({ w = props.w or 160, x = props.x, y = props.y })
    local items = props.items or {}
    local n = #items
    node:setSize(props.w or 160, n * 24)

    for i = 1, n do
        local it = items[i]
        local row = k:create(C.NODE_PANEL, node)
        row:setPosition(0, (i - 1) * 24)
        row:setSize(props.w or 160, 24)
        row:setColor(0xFF2A2A2A)
        local label = k:create(C.NODE_TEXT, row)
        label:setPosition(8, (24 - 14) / 2)
        label:setText(it.text or "")
        label:setColor(COLOR_TEXT)
        label:setEnabled(false)
        local cb = it.onClick
        row:on("mouseenter", function()
            if row:isAlive() then row:setColor(0xFF3A6EA5) end
        end)
        row:on("mouseleave", function()
            if row:isAlive() then row:setColor(0xFF2A2A2A) end
        end)
        row:on("click", function()
            node:hide()
            if cb then cb() end
        end)
    end
    return node
end

-- ==================== M18: Controls (ADR-022) ==========================
-- Восстановление (M20): билдеры потерялись — дизайн по ADR-022.
-- CheckBox / RadioButton (Toggle), ProgressBar, Slider.

local ToggleMethods = {}

function ToggleMethods:setChecked(v)
    local tg = self._tg
    if tg.checked == (v == true) then return self end
    tg.checked = v == true
    self:_renderToggle()
    if tg.onChange then tg.onChange(tg.checked) end
    return self
end

function ToggleMethods:isChecked()
    return self._tg.checked == true
end

function ToggleMethods:toggle()
    return self:setChecked(not self._tg.checked)
end

function ToggleMethods:_renderToggle()
    local parts = self._parts
    if not parts or not parts.mark then return end
    parts.mark:setVisible(self._tg.checked)
end

function ToggleMethods:setLabel(text)
    local parts = self._parts
    if parts and parts.label then parts.label:setText(text or "") end
    return self
end

function ToggleMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    -- убрать себя из radio-группы
    local tg = self._tg
    if tg and tg.groupList then
        for i = #tg.groupList, 1, -1 do
            if tg.groupList[i] == self then
                table.remove(tg.groupList, i)
            end
        end
    end
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._tg = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeToggleMt(baseMethods)
    return { __index = function(_, k)
        local m = ToggleMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

-- RadioButton: setChecked(true) снимает остальных в группе; снять радио
-- кликом нельзя (клик по выбранному — no-op, ADR-022).
local RadioMethods = {
    setChecked = function(self, v)
        if not v then
            -- программное снятие (peer-группа) — разрешено
            return ToggleMethods.setChecked(self, false)
        end
        local tg = self._tg
        if tg.groupList then
            for i = 1, #tg.groupList do
                local other = tg.groupList[i]
                if other ~= self and other:isChecked() then
                    other:setChecked(false)
                end
            end
        end
        return ToggleMethods.setChecked(self, true)
    end,
}

local function makeRadioMt(baseMethods)
    return { __index = function(_, k)
        local m = RadioMethods[k]
        if m ~= nil then return m end
        local t = ToggleMethods[k]
        if t ~= nil then return t end
        return baseMethods[k]
    end }
end

--- Внутренний: построить box+mark+label под checkbox/radio.
local function buildToggleParts(k, node, props, markSize, markColor)
    local w = props.w or DEFAULTS.checkbox.w
    local h = props.h or DEFAULTS.checkbox.h
    node:setSize(w, h)
    local parts = {}
    node._parts = parts

    local box = k:create(C.NODE_PANEL, node)
    box:setPosition(0, (h - 16) / 2)
    box:setSize(16, 16)
    box:setColor(0xFF333333)
    box:setEnabled(false)
    parts.box = box

    local mark = k:create(C.NODE_PANEL, box)
    mark:setPosition((16 - markSize) / 2, (16 - markSize) / 2)
    mark:setSize(markSize, markSize)
    mark:setColor(markColor)
    mark:setEnabled(false)
    mark:setVisible(false)
    parts.mark = mark

    local label = k:create(C.NODE_TEXT, node)
    label:setPosition(22, (h - 14) / 2)
    label:setColor(COLOR_TEXT)
    label:setEnabled(false)
    label:setText(props.text or "")
    parts.label = label
    return parts
end

--- ui.checkbox(props) — галочка. props: checked, text, onChange(checked).
function UI:checkbox(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._checkboxMt then
        self._checkboxMt = makeToggleMt(k.proxy.methods)
    end
    setmetatable(node, self._checkboxMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._tg = {
        checked = props.checked == true,
        onChange = props.onChange,
        group = nil,
        groupList = nil,
    }
    buildToggleParts(k, node, props, 10, 0xFF00CC00)
    node:_renderToggle()
    node:on("click", function()
        if node:isAlive() then node:toggle() end
    end)
    attachChildren(k, node, props)
    return node
end

--- ui.radiobutton(props) — радио. props: checked, text, group (string),
-- onChange(checked). Группа — общий список UI._radioGroups[group].
function UI:radiobutton(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._radioMt then
        self._radioMt = makeRadioMt(k.proxy.methods)
    end
    setmetatable(node, self._radioMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._tg = {
        checked = props.checked == true,
        onChange = props.onChange,
        group = props.group,
        groupList = nil,
    }
    -- регистрация в группе (общий список, ADR-022)
    if props.group then
        self._radioGroups = self._radioGroups or {}
        local list = self._radioGroups[props.group]
        if not list then
            list = {}
            self._radioGroups[props.group] = list
        end
        list[#list + 1] = node
        node._tg.groupList = list
    end
    buildToggleParts(k, node, props, 8, 0xFF3399FF)
    node:_renderToggle()
    node:on("click", function()
        if node:isAlive() then node:setChecked(true) end
    end)
    attachChildren(k, node, props)
    return node
end

-- ============ ProgressBar ============
local ProgressMethods = {}

function ProgressMethods:setValue(v)
    local pb = self._pb
    pb.value = v
    self:_renderProgress()
    if pb.onChange then pb.onChange(v) end
    return self
end

function ProgressMethods:getValue()
    return self._pb.value
end

function ProgressMethods:setRange(min, max)
    local pb = self._pb
    if min >= max then min, max = 0, 1 end
    pb.min, pb.max = min, max
    self:_renderProgress()
    return self
end

function ProgressMethods:_renderProgress()
    local pb = self._pb
    local parts = self._parts
    if not parts or not parts.fill then return end
    local frac = (pb.value - pb.min) / (pb.max - pb.min)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local w, h = self:getSize()
    parts.fill:setSize(w * frac, h)
end

function ProgressMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    local parts = self._parts
    if parts and parts.track then parts.track:setSize(w, h) end
    self:_renderProgress()
    return self
end

function ProgressMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._pb = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeProgressMt(baseMethods)
    return { __index = function(_, k)
        local m = ProgressMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.progressbar(props) — прогресс-бар. props: value, min, max, onChange.
function UI:progressbar(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._progressMt then
        self._progressMt = makeProgressMt(k.proxy.methods)
    end
    setmetatable(node, self._progressMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    local w = props.w or DEFAULTS.progressbar.w
    local h = props.h or DEFAULTS.progressbar.h
    node._pb = {
        value = props.value or 0,
        min = props.min or 0,
        max = props.max or 100,
        onChange = props.onChange,
    }
    node:setSize(w, h)

    local parts = {}
    node._parts = parts
    local track = k:create(C.NODE_PANEL, node)
    track:setPosition(0, 0)
    track:setSize(w, h)
    track:setColor(0xFF333333)
    track:setEnabled(false)
    parts.track = track

    local fill = k:create(C.NODE_PANEL, track)
    fill:setPosition(0, 0)
    fill:setSize(0, h)
    fill:setColor(0xFF00CC00)
    fill:setEnabled(false)
    fill:setZIndex(2)
    parts.fill = fill

    node:_renderProgress()
    attachChildren(k, node, props)
    return node
end

-- ============ Slider ============
local SLIDER_THUMB_MIN = 10

local SliderMethods = {}

function SliderMethods:setValue(v)
    local sl = self._sl
    sl.value = v
    self:_renderSlider()
    if sl.onChange then sl.onChange(v) end
    return self
end

function SliderMethods:getValue()
    return self._sl.value
end

function SliderMethods:setRange(min, max)
    local sl = self._sl
    if min >= max then min, max = 0, 1 end
    sl.min, sl.max = min, max
    self:_renderSlider()
    return self
end

--- frac из value (clamp 0..1)
function SliderMethods:_frac()
    local sl = self._sl
    return (sl.value - sl.min) / (sl.max - sl.min)
end

function SliderMethods:_renderSlider()
    local sl = self._sl
    local parts = self._parts
    if not parts or not parts.thumb then return end
    local w, h = self:getSize()
    local trackLen = sl.vertical and h or w
    local thumbLen = sl.vertical and w or h
    local frac = self:_frac()
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local span = trackLen - sl.thumbSize
    if span < 0 then span = 0 end
    local pos = frac * span
    -- fill от начала до thumb
    if sl.vertical then
        parts.fill:setSize(w, pos)
        parts.thumb:setPosition(0, pos)
        parts.thumb:setSize(w, sl.thumbSize)
    else
        parts.fill:setSize(pos, h)
        parts.thumb:setPosition(pos, 0)
        parts.thumb:setSize(sl.thumbSize, h)
    end
end

function SliderMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    local parts = self._parts
    if parts and parts.track then parts.track:setSize(w, h) end
    self:_renderSlider()
    return self
end

function SliderMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._sl = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeSliderMt(baseMethods)
    return { __index = function(_, k)
        local m = SliderMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.slider(props) — слайдер. props: value, min, max, orientation
-- ("h"|"v", default "h"), onChange(v), + общие.
-- Drag через Dispatcher:beginDrag (delta-подход, ADR-022); M20:
-- click-to-jump по треку (ADR-024).
function UI:slider(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._sliderMt then
        self._sliderMt = makeSliderMt(k.proxy.methods)
    end
    setmetatable(node, self._sliderMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._sl = {
        value = props.value or 0,
        min = props.min or 0,
        max = props.max or 100,
        onChange = props.onChange,
        vertical = props.orientation == "v",
        thumbSize = props.thumbSize or SLIDER_THUMB_MIN,
    }
    local sl = node._sl
    if sl.min >= sl.max then sl.min, sl.max = 0, 1 end

    local w = props.w or DEFAULTS.slider.w
    local h = props.h or DEFAULTS.slider.h
    node:setSize(w, h)

    local parts = {}
    node._parts = parts
    local track = k:create(C.NODE_PANEL, node)
    track:setPosition(0, 0)
    track:setSize(w, h)
    track:setColor(0xFF333333)
    track:setEnabled(false)
    parts.track = track

    local fill = k:create(C.NODE_PANEL, track)
    fill:setPosition(0, 0)
    fill:setSize(0, 0)
    fill:setColor(0xFF00CC00)
    fill:setEnabled(false)
    fill:setZIndex(2)
    parts.fill = fill

    local thumb = k:create(C.NODE_PANEL, track)
    thumb:setColor(0xFFDDDDDD)
    thumb:setZIndex(4)
    parts.thumb = thumb

    -- drag thumb (delta-подход без world-координат)
    thumb:on("mousedown", function(e)
        if e.button ~= "left" then return end
        if not node:isAlive() or not node._win then return end
        local s = k.storage
        local tSlot = s.idToSlot[thumb.id]
        if not tSlot then return end
        -- захват: текущая value => frac старта; далее сдвиг по осям
        local startFrac = node:_frac()
        local grab = sl.vertical and (e.y or 0) or (e.x or 0)
        local w0, h0 = node:getSize()
        local trackLen = sl.vertical and h0 or w0
        local span = trackLen - sl.thumbSize
        if span <= 0 then return end
        k.dispatcher:beginDrag(function(px, py)
            if not node:isAlive() then return end
            local nowPos = sl.vertical and py or px
            local frac = startFrac + (nowPos - grab) / span
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            node:setValue(sl.min + frac * (sl.max - sl.min))
        end)
    end)

    -- M20 (ADR-024): click-to-jump по треку (кроме thumb — его обрабатывает drag)
    node:on("mousedown", function(e)
        if e.button ~= "left" then return end
        if e.target == thumb.id then return end
        if not node:isAlive() then return end
        local w0, h0 = node:getSize()
        local trackLen = sl.vertical and h0 or w0
        local span = trackLen - sl.thumbSize
        if span <= 0 then return end
        local pos = sl.vertical and (e.y or 0) or (e.x or 0)
        -- нужна мировая позиция трека (begin-of-track)
        local s = k.storage
        local slot = s.idToSlot[node.id]
        if not slot then return end
        local base = sl.vertical and s.worldY[slot] or s.worldX[slot]
        local frac = (pos - base) / span
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        node:setValue(sl.min + frac * (sl.max - sl.min))
    end)

    node:_renderSlider()
    attachChildren(k, node, props)
    return node
end

-- ============ M19: ComboBox + TabPanel + GridList (ADR-023) ============
-- Composite-proxy (тот же паттерн):
--   * ComboBox: node(PANEL) + label(TEXT) + arrow(TEXT) + dropdown(POPUP, root)
--   * TabPanel: node(PANEL) + bar(PANEL) + per-tab: btn(PANEL) + page(PANEL)
--   * GridList: node(PANEL) + header(PANEL) + scroll(ScrollPanel M13, child)
-- Memo не нужен: Edit multiline (M15) покрывает многострочный ввод.

local COMBO_ITEM_H    = 24
local TAB_BAR_H       = 24
local TAB_COLOR_ACTIVE   = 0xFF3A6EA5
local TAB_COLOR_INACTIVE = 0xFF2A2A2A
local GRID_HEADER_H   = 20
local GRID_ROW_H      = 22
local GRID_ROW_COLOR     = 0xFF222222
local GRID_ROW_HOVER     = 0xFF2E4A6B
local GRID_ROW_SELECTED  = 0xFF3A6EA5

-- =======================================================================
-- ComboBox
-- =======================================================================
local ComboMethods = {}

function ComboMethods:setItems(items)
    local cb = self._cb
    cb.items = items or {}
    if cb.selected > #cb.items then cb.selected = 0 end
    self:_renderCombo()
    return self
end

function ComboMethods:getItems()
    return self._cb.items
end

function ComboMethods:setSelected(idx)
    local cb = self._cb
    if idx < 0 then idx = 0 end
    if idx > #cb.items then idx = 0 end
    if cb.selected == idx then return self end
    cb.selected = idx
    self:_renderCombo()
    if cb.onChange then cb.onChange(idx, self:_itemValue(idx)) end
    return self
end

function ComboMethods:getSelected()
    return self._cb.selected
end

function ComboMethods:getValue()
    return self:_itemValue(self._cb.selected)
end

function ComboMethods:_itemValue(idx)
    local it = self._cb.items[idx]
    if it == nil then return nil end
    if type(it) == "table" then return it.value end
    return it
end

function ComboMethods:_itemText(idx)
    local it = self._cb.items[idx]
    if it == nil then return nil end
    if type(it) == "table" then return it.text end
    return tostring(it)
end

function ComboMethods:_renderCombo()
    local cb = self._cb
    local parts = self._parts
    if not parts or not parts.label then return end
    local t = cb.selected > 0 and self:_itemText(cb.selected) or nil
    if t then
        parts.label:setText(t)
        parts.label:setColor(cb.textColor)
    else
        parts.label:setText(cb.placeholder or "")
        parts.label:setColor(0xFF888888)
    end
end

--- Открыть dropdown (перестраивает rows — cold path, актуальная ширина).
function ComboMethods:open()
    local cb = self._cb
    local parts = self._parts
    if not parts or not parts.dropdown then return self end
    if self:isOpen() then return self end

    self:_rebuildRows()

    local k = self._kernel
    local slot = k.storage.idToSlot[self.id]
    if not slot then return self end
    local wx, wy = k.storage.worldX[slot], k.storage.worldY[slot]
    local w, h = self:getSize()
    parts.dropdown:setSize(w, #cb.items * cb.itemH)
    parts.dropdown:show(wx, wy + h)
    return self
end

function ComboMethods:close()
    local parts = self._parts
    if parts and parts.dropdown then parts.dropdown:hide() end
    return self
end

function ComboMethods:isOpen()
    local parts = self._parts
    return (parts and parts.dropdown and parts.dropdown:isShown()) or false
end

--- Перестроить пункты dropdown (destroy old rows -> create new).
function ComboMethods:_rebuildRows()
    local cb = self._cb
    local k = self._kernel
    local parts = self._parts
    if not parts or not parts.dropdown then return end

    for i = 1, #cb.rows do
        local r = cb.rows[i]
        if r.row and r.row:isAlive() then r.row:destroy() end
        if r.row then k.proxy:release(r.row) end
        if r.label then k.proxy:release(r.label) end
    end
    cb.rows = {}

    local w = self:getSize()
    for i = 1, #cb.items do
        local row = k:create(C.NODE_PANEL, parts.dropdown)
        row:setPosition(0, (i - 1) * cb.itemH)
        row:setSize(w, cb.itemH)
        row:setColor(0xFF2A2A2A)
        local label = k:create(C.NODE_TEXT, row)
        label:setPosition(6, (cb.itemH - 14) / 2)
        label:setText(self:_itemText(i) or "")
        label:setColor(0xFFFFFFFF)
        local idx = i
        row:on("mouseenter", function() row:setColor(0xFF3A6EA5) end)
        row:on("mouseleave", function() row:setColor(0xFF2A2A2A) end)
        row:on("click", function()
            self:setSelected(idx)
            self:close()
        end)
        cb.rows[i] = { row = row, label = label }
    end
end

function ComboMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    local parts = self._parts
    if parts then
        if parts.label then parts.label:setPosition(6, (h - 14) / 2) end
        if parts.arrow then parts.arrow:setPosition(w - 16, (h - 14) / 2) end
    end
    return self
end

function ComboMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    local cb = self._cb
    if parts and k then
        -- dropdown — отдельный корневой узел: уничтожить явно (каскад снесёт rows)
        if parts.dropdown then
            parts.dropdown:destroy()
            k.proxy:release(parts.dropdown)
            parts.dropdown = nil
        end
        if cb and cb.rows then
            for i = 1, #cb.rows do
                local r = cb.rows[i]
                if r.row then k.proxy:release(r.row) end
                if r.label then k.proxy:release(r.label) end
            end
        end
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._cb = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeComboMt(baseMethods)
    return { __index = function(_, k)
        local m = ComboMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.combobox(props) — выпадающий список. props: items (массив строк или
--- {text=, value=}), selected, placeholder, onChange(idx, value),
--- itemHeight, textColor + общие. Методы: setItems/getItems/setSelected/
--- getSelected/getValue/open/close/isOpen.
function UI:combobox(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._comboMt then
        self._comboMt = makeComboMt(k.proxy.methods)
    end
    setmetatable(node, self._comboMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._cb = {
        items = props.items or {},
        selected = props.selected or 0,
        itemH = props.itemHeight or COMBO_ITEM_H,
        placeholder = props.placeholder or "",
        onChange = props.onChange,
        textColor = resolveColor(props.textColor) or COLOR_TEXT,
        rows = {},
    }

    local parts = {}
    node._parts = parts
    local w = props.w or DEFAULTS.combobox.w
    local h = props.h or DEFAULTS.combobox.h
    node:setSize(w, h)

    local label = k:create(C.NODE_TEXT, node)
    label:setPosition(6, (h - 14) / 2)
    label:setEnabled(false)
    parts.label = label

    local arrow = k:create(C.NODE_TEXT, node)
    arrow:setPosition(w - 16, (h - 14) / 2)
    arrow:setText("v")
    arrow:setColor(0xFF888888)
    arrow:setEnabled(false)
    parts.arrow = arrow

    -- dropdown — popup (M17): root-узел, скрыт; dismiss по клику вне бесплатный
    local dropdown = self:popup({ w = w })
    parts.dropdown = dropdown

    node:on("click", function()
        if node:isOpen() then node:close() else node:open() end
    end)

    node:_renderCombo()
    attachChildren(k, node, props)
    return node
end

-- =======================================================================
-- TabPanel
-- =======================================================================
local TabMethods = {}

--- Добавить вкладку. children — массив виджетов для страницы (опционально).
--- Возвращает page (PANEL) — можно прикреплять детей напрямую.
function TabMethods:addTab(title, children)
    local k = self._kernel
    local t = self._tabs
    local parts = self._parts
    if not parts or not parts.bar then return nil end
    local w, h = self:getSize()

    local btn = k:create(C.NODE_PANEL, parts.bar)
    local label = k:create(C.NODE_TEXT, btn)
    label:setText(title)
    label:setColor(COLOR_TEXT)
    label:setEnabled(false)

    local page = k:create(C.NODE_PANEL, self)
    page:setPosition(0, t.barH)
    page:setSize(w, h - t.barH)
    page:setColor(t.pageColor)
    page:setVisible(false)

    local entry = { title = title, btn = btn, label = label, page = page }
    t.tabs[#t.tabs + 1] = entry

    btn:on("click", function()
        for i, e in ipairs(t.tabs) do
            if e == entry then
                self:selectTab(i)
                break
            end
        end
    end)

    if children then
        for i = 1, #children do children[i]:setParent(page) end
    end

    self:_layoutTabs()
    if #t.tabs == 1 then self:selectTab(1) end
    return page
end

function TabMethods:removeTab(idx)
    local k = self._kernel
    local t = self._tabs
    if idx < 1 or idx > #t.tabs then return self end
    local entry = t.tabs[idx]
    table.remove(t.tabs, idx)
    if entry.btn and entry.btn:isAlive() then entry.btn:destroy() end
    if entry.btn then k.proxy:release(entry.btn) end
    if entry.label then k.proxy:release(entry.label) end
    if entry.page and entry.page:isAlive() then entry.page:destroy() end
    if entry.page then k.proxy:release(entry.page) end
    if t.selected == idx then
        t.selected = 0
        if #t.tabs > 0 then self:selectTab(1) end
    elseif t.selected > idx then
        t.selected = t.selected - 1
    end
    self:_layoutTabs()
    return self
end

function TabMethods:selectTab(idx)
    local t = self._tabs
    if idx < 1 or idx > #t.tabs then return self end
    if t.selected == idx then return self end
    if t.selected > 0 and t.tabs[t.selected] then
        t.tabs[t.selected].page:setVisible(false)
    end
    t.selected = idx
    t.tabs[idx].page:setVisible(true)
    self:_layoutTabs()
    if t.onChange then t.onChange(idx) end
    return self
end

function TabMethods:getSelectedIndex()
    return self._tabs.selected
end

function TabMethods:getTabCount()
    return #self._tabs.tabs
end

--- Перепозиционировать кнопки вкладок (auto-ширина по заголовку).
function TabMethods:_layoutTabs()
    local t = self._tabs
    local x = 0
    for i, e in ipairs(t.tabs) do
        local tw = #e.title * 7 + 16
        e.btn:setPosition(x, 0)
        e.btn:setSize(tw, t.barH)
        e.label:setPosition(6, (t.barH - 14) / 2)
        e.label:setSize(tw - 12, 14)
        e.btn:setColor(i == t.selected and TAB_COLOR_ACTIVE or TAB_COLOR_INACTIVE)
        x = x + tw
    end
end

function TabMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    local parts = self._parts
    local t = self._tabs
    if parts and parts.bar then
        parts.bar:setSize(w, t.barH)
    end
    if t then
        for i = 1, #t.tabs do
            t.tabs[i].page:setSize(w, h - t.barH)
        end
        self:_layoutTabs()
    end
    return self
end

function TabMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    local t = self._tabs
    if t and k then
        for i = 1, #t.tabs do
            local e = t.tabs[i]
            if e.btn then k.proxy:release(e.btn) end
            if e.label then k.proxy:release(e.label) end
            if e.page then k.proxy:release(e.page) end
        end
    end
    if parts and k then
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._tabs = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeTabMt(baseMethods)
    return { __index = function(_, k)
        local m = TabMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.tabpanel(props) — вкладки. props: barHeight, barColor, pageColor,
--- onChange(idx) + общие. Методы: addTab(title, children)/removeTab/
--- selectTab/getSelectedIndex/getTabCount. addTab возвращает page.
function UI:tabpanel(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._tabMt then
        self._tabMt = makeTabMt(k.proxy.methods)
    end
    setmetatable(node, self._tabMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._tabs = {
        tabs = {},
        selected = 0,
        barH = props.barHeight or TAB_BAR_H,
        onChange = props.onChange,
        pageColor = resolveColor(props.pageColor) or 0xFF222222,
    }

    local parts = {}
    node._parts = parts
    local w = props.w or DEFAULTS.tabpanel.w
    local h = props.h or DEFAULTS.tabpanel.h
    node:setSize(w, h)

    local bar = k:create(C.NODE_PANEL, node)
    bar:setPosition(0, 0)
    bar:setSize(w, node._tabs.barH)
    bar:setColor(resolveColor(props.barColor) or 0xFF181818)
    parts.bar = bar

    return node
end

-- =======================================================================
-- GridList
-- =======================================================================
local GridMethods = {}

function GridMethods:addColumn(text, width)
    local g = self._grid
    g.columns[#g.columns + 1] = { text = text, width = width or 100 }
    self:_rebuildHeader()
    return self
end

--- Перестроить заголовок (destroy old labels -> create new).
function GridMethods:_rebuildHeader()
    local k = self._kernel
    local g = self._grid
    local parts = self._parts
    if not parts or not parts.header then return end

    for i = 1, #g.headerLabels do
        local l = g.headerLabels[i]
        if l:isAlive() then l:destroy() end
        k.proxy:release(l)
    end
    g.headerLabels = {}

    local x = 0
    for i = 1, #g.columns do
        local l = k:create(C.NODE_TEXT, parts.header)
        l:setPosition(x + 4, (g.headerH - 14) / 2)
        l:setText(g.columns[i].text or "")
        l:setColor(0xFFAAAAAA)
        l:setEnabled(false)
        g.headerLabels[i] = l
        x = x + g.columns[i].width
    end
    parts.header:setSize(x, g.headerH)
end

function GridMethods:_totalWidth()
    local g = self._grid
    local w = 0
    for i = 1, #g.columns do w = w + g.columns[i].width end
    return w
end

--- Добавить строку (cells — массив значений по колонкам). Возвращает индекс.
function GridMethods:addRow(cells)
    local k = self._kernel
    local g = self._grid
    local parts = self._parts
    if not parts or not parts.scroll then return 0 end
    local content = parts.scroll:getContent()
    local totalW = self:_totalWidth()
    local y = #g.rows * g.rowH

    local row = k:create(C.NODE_PANEL, content)
    row:setPosition(0, y)
    row:setSize(totalW, g.rowH)
    row:setColor(GRID_ROW_COLOR)

    local labels = {}
    local x = 0
    for i = 1, #g.columns do
        local l = k:create(C.NODE_TEXT, row)
        l:setPosition(x + 4, (g.rowH - 14) / 2)
        l:setText(tostring(cells[i] or ""))
        l:setColor(0xFFFFFFFF)
        l:setEnabled(false)
        labels[i] = l
        x = x + g.columns[i].width
    end

    local idx = #g.rows + 1
    g.rows[idx] = { row = row, labels = labels, cells = cells }

    row:on("mouseenter", function() if g.selected ~= idx then row:setColor(GRID_ROW_HOVER) end end)
    row:on("mouseleave", function() if g.selected ~= idx then row:setColor(GRID_ROW_COLOR) end end)
    row:on("click", function() self:selectRow(idx) end)

    parts.scroll:refresh() -- auto-measure по детям + переразложить полосы
    return idx
end

function GridMethods:selectRow(idx)
    local g = self._grid
    if idx < 1 or idx > #g.rows then return self end
    if g.selected > 0 and g.rows[g.selected] then
        g.rows[g.selected].row:setColor(GRID_ROW_COLOR)
    end
    g.selected = idx
    g.rows[idx].row:setColor(GRID_ROW_SELECTED)
    if g.onChange then g.onChange(idx, g.rows[idx].cells) end
    return self
end

function GridMethods:getSelected()
    return self._grid.selected
end

function GridMethods:getSelectedCells()
    local g = self._grid
    if g.selected > 0 and g.rows[g.selected] then return g.rows[g.selected].cells end
    return nil
end

function GridMethods:getRowCount()
    return #self._grid.rows
end

function GridMethods:clearRows()
    local k = self._kernel
    local g = self._grid
    for i = 1, #g.rows do
        local e = g.rows[i]
        if e.row and e.row:isAlive() then e.row:destroy() end
        if e.row then k.proxy:release(e.row) end
        for j = 1, #e.labels do k.proxy:release(e.labels[j]) end
    end
    g.rows = {}
    g.selected = 0
    local parts = self._parts
    if parts and parts.scroll then parts.scroll:refresh() end
    return self
end

function GridMethods:setSize(w, h)
    local win = self._win
    if not win then return self end
    win.baseSetSize(self, w, h)
    local g = self._grid
    local parts = self._parts
    if parts then
        if parts.header then parts.header:setSize(self:_totalWidth(), g.headerH) end
        if parts.scroll then
            parts.scroll:setPosition(0, g.headerH)
            parts.scroll:setSize(w, h - g.headerH)
        end
    end
    return self
end

function GridMethods:destroy()
    local k = self._kernel
    local win = self._win
    local parts = self._parts
    local g = self._grid
    if g and k then
        for i = 1, #g.rows do
            local e = g.rows[i]
            if e.row then k.proxy:release(e.row) end
            for j = 1, #e.labels do k.proxy:release(e.labels[j]) end
        end
        for i = 1, #g.headerLabels do
            k.proxy:release(g.headerLabels[i])
        end
    end
    if parts and k then
        if parts.scroll then
            parts.scroll:destroy() -- ScrollMethods:destroy (release своих parts)
            k.proxy:release(parts.scroll)
            parts.scroll = nil
        end
        for _, p in pairs(parts) do
            if p then k.proxy:release(p) end
        end
    end
    self._parts = nil
    self._win = nil
    self._kernel = nil
    self._grid = nil
    if win and win.baseDestroy then win.baseDestroy(self) end
end

local function makeGridMt(baseMethods)
    return { __index = function(_, k)
        local m = GridMethods[k]
        if m ~= nil then return m end
        return baseMethods[k]
    end }
end

--- ui.gridlist(props) — таблица. props: columns = { {text=, width=}, ... },
--- rowHeight, headerHeight, headerColor, onSelect(idx, cells) + общие.
--- Методы: addColumn/addRow/selectRow/getSelected/getSelectedCells/
--- getRowCount/clearRows. Скролл — встроенный ScrollPanel (M13).
function UI:gridlist(props)
    props = props or {}
    local k = self.kernel
    local node = k:create(C.NODE_PANEL, nil)
    applyCommon(node, props)

    if not self._gridMt then
        self._gridMt = makeGridMt(k.proxy.methods)
    end
    setmetatable(node, self._gridMt)
    node._kernel = k
    node._win = {
        baseSetSize = k.proxy.methods.setSize,
        baseDestroy = k.proxy.methods.destroy,
    }
    node._grid = {
        columns = {},
        headerLabels = {},
        rows = {},
        selected = 0,
        rowH = props.rowHeight or GRID_ROW_H,
        headerH = props.headerHeight or GRID_HEADER_H,
        onChange = props.onSelect,
    }

    local parts = {}
    node._parts = parts
    local w = props.w or DEFAULTS.gridlist.w
    local h = props.h or DEFAULTS.gridlist.h
    node:setSize(w, h)

    local header = k:create(C.NODE_PANEL, node)
    header:setPosition(0, 0)
    header:setSize(w, node._grid.headerH)
    header:setColor(resolveColor(props.headerColor) or 0xFF181818)
    header:setEnabled(false)
    parts.header = header

    -- scroll — встроенный ScrollPanel (M13), reparent под grid
    local scroll = self:scrollpanel({
        x = 0, y = node._grid.headerH,
        w = w, h = h - node._grid.headerH,
    })
    scroll:setParent(node)
    parts.scroll = scroll

    if props.columns then
        for i = 1, #props.columns do
            local col = props.columns[i]
            node:addColumn(col.text, col.width)
        end
    end

    return node
end
