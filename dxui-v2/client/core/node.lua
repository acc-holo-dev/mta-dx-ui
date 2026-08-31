--[[
    node.lua — DXUI V2

    Node: публичный объект UI. Обычная Lua-таблица с метатаблицей, которая
    перехватывает чтение/запись свойств ради единого mutation layer
    (валидация + инвалидация).

    Ключевые решения (см. ARCHITECTURE.md):
      - AoS: состояние узла — это сам объект (не SoA + slot + id).
      - Property-style (node.x = 100) и method-style (node:setPosition(...))
        сходятся в один слой Node:_set(prop, value).
      - Инвалидация — именованные категории (DIRTY_LAYOUT и т.д.), хранятся
        как булевы флаги в node._dirty. Никаких битовых масок наружу.
      - parent/children — управляются методами (setParent/addChild), читаются
        как read-only поля.
      - Наследование — простое prototype-наследование через Node.extend().

    Модуль не зависит от MTA API — чистый Lua 5.1, тестируем вне игры.
]]

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Конфигурация и предупреждения (error handling, §69)
-- ---------------------------------------------------------------------
DXUI.config = DXUI.config or { debug = false }

function DXUI._warn(msg)
    if DXUI.config.debug then
        if outputDebugString then
            outputDebugString("[dxui] " .. msg)
        else
            print("[dxui] " .. msg)
        end
    end
end

-- ---------------------------------------------------------------------
-- Dirty categories (читаемые имена; внутренне — булевы флаги)
-- ---------------------------------------------------------------------
DXUI.DIRTY = {
    LAYOUT     = "layout",     -- позиция/размер/родитель/якорь/margin/padding
    RENDER     = "render",     -- цвет/текст/текстура/opacity/геометрия
    INPUT      = "input",      -- hit-геометрия/видимость/enabled/z-order
    STYLE      = "style",      -- разрешение стиля
    CHILDREN   = "children",   -- состав детей
    VISIBILITY = "visibility", -- видимость/culling
}

local DIRTY = DXUI.DIRTY

-- ---------------------------------------------------------------------
-- Layers (именованные)
-- ---------------------------------------------------------------------
DXUI.LAYER = {
    BASE    = 0,
    OVERLAY = 1,
    MODAL   = 2,
    POPUP   = 3,
    TOOLTIP = 4,
    DEBUG   = 5,
}

local LAYER = DXUI.LAYER

-- ---------------------------------------------------------------------
-- Node
-- ---------------------------------------------------------------------
local Node = {}
Node._name = "Node"
Node._super = nil

-- Декларация свойств: name -> { default, invalidates = {категории} }.
-- Каждое свойство знает, какие подсистемы оно инвалидирует (§26).
Node.properties = {
    -- геометрия: изменение влияет и на layout, и на render (world-координаты)
    x        = { default = 0,    invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    y        = { default = 0,    invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    width    = { default = 0,    invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    height   = { default = 0,    invalidates = { DIRTY.LAYOUT, DIRTY.RENDER } },
    visible  = { default = true, invalidates = { DIRTY.VISIBILITY, DIRTY.INPUT, DIRTY.RENDER } },
    enabled  = { default = true, invalidates = { DIRTY.INPUT } },
    opacity  = { default = 1,    invalidates = { DIRTY.RENDER } },
    zIndex   = { default = 0,    invalidates = { DIRTY.INPUT, DIRTY.RENDER } },
    layer    = { default = LAYER.BASE, invalidates = { DIRTY.RENDER } },
    -- style: имя стиля из темы или inline-таблица. Запись ПОСЛЕ создания
    -- переключает стиль (onSet → Widget.applyStyle, см. style/theme.lua).
    style    = { default = nil,  invalidates = { DIRTY.STYLE },
                 onSet = function(node, value)
                     -- позднее связывание: Widget определяется позже node.lua
                     if DXUI.Widget and DXUI.Widget._onStyleSet then
                         DXUI.Widget._onStyleSet(node, value)
                     end
                 end },
    userData = { default = nil,  invalidates = {} },
    -- Stage 5: layout (§29). margin/padding — number (все стороны) или
    -- table {left, top, right, bottom}. Менять целиком, не мутировать in-place.
    layoutMode = { default = "absolute", invalidates = { DIRTY.LAYOUT } },
    anchor     = { default = "tl",       invalidates = { DIRTY.LAYOUT } },
    margin     = { default = nil,        invalidates = { DIRTY.LAYOUT } },
    padding    = { default = nil,        invalidates = { DIRTY.LAYOUT } },
    -- Stage 7: clip (§35). true — дети обрезаются по границам узла.
    -- Дешёвый путь — geometric clip в render list; RT-стек — позже (маски/blur).
    clip       = { default = false,      invalidates = { DIRTY.RENDER, DIRTY.INPUT } },
    -- Stage 11 (§35 expensive path): clipMode = "rt" — поддерево композитится
    -- в offscreen RT: pixel-perfect clip + true group-opacity (§34) +
    -- blur/mask на весь контейнер. Default (nil) — дешёвый geometric путь.
    clipMode   = { default = nil,         invalidates = { DIRTY.RENDER } },
    -- Stage 7b: autosize (§29) — размер по содержимому (layout вызывает
    -- _measureContent и пишет width/height через mutation layer).
    autoSize   = { default = false,      invalidates = { DIRTY.LAYOUT } },
}

Node._spec = Node.properties

-- read-only вычисляемые поля (управляются методами, не присваиванием)
local READONLY = {
    parent = true, children = true, id = true,
    context = true, destroyed = true,
    worldX = true, worldY = true, -- Stage 5: вычисляются layout-проходом
}

-- глобальный счётчик id (для отладки/событий; не доминирует над объектом)
local nextId = 1

-- ---------------------------------------------------------------------
-- Instance metatable (общая для всех узлов)
-- ---------------------------------------------------------------------
local mt = {
    __index = function(self, key)
        if key == "parent"    then return self._parent end
        if key == "children"  then return self._children end
        if key == "id"        then return self._id end
        if key == "context"   then return self._context end
        if key == "destroyed" then return self._destroyed end
        if key == "worldX"    then return self._worldX end
        if key == "worldY"    then return self._worldY end

        local spec = self._spec[key]
        if spec then
            return self._data[key]
        end

        -- методы через цепочку классов (Node -> Widget -> Button -> ...)
        local cls = self._class
        while cls do
            local m = rawget(cls, key)
            if m ~= nil then return m end
            cls = cls._super
        end
        return nil
    end,

    __newindex = function(self, key, value)
        if READONLY[key] then
            DXUI._warn("read-only property: " .. key)
            return
        end
        local spec = self._spec and self._spec[key]
        if spec then
            self:_set(key, value)
        else
            rawset(self, key, value) -- произвольные пользовательские поля
        end
    end,
}

-- ---------------------------------------------------------------------
-- Создание
-- ---------------------------------------------------------------------

--- Создаёт узел. self — класс (Node или подкласс).
function Node:new(props)
    return self:_instantiate(self, props)
end

function Node:_instantiate(cls, props)
    local self = setmetatable({}, mt)
    rawset(self, "_class", cls)
    rawset(self, "_spec", cls._spec)
    rawset(self, "_data", {})
    rawset(self, "_dirty", {})
    rawset(self, "_queued", false)
    rawset(self, "_context", nil)
    rawset(self, "_parent", nil)
    rawset(self, "_children", {})
    rawset(self, "_destroyed", false)
    rawset(self, "_id", nextId)
    rawset(self, "_worldX", 0) -- Stage 5: вычисляется layout-проходом
    rawset(self, "_worldY", 0)
    nextId = nextId + 1

    -- значения по умолчанию
    for k, spec in pairs(cls._spec) do
        self._data[k] = spec.default
    end

    -- _building: на стадии построения onSet-хук style не применяет стиль
    -- повторно — начальное применение делает applyThemeDefaults ниже
    rawset(self, "_building", true)

    -- применить props: свойства — через _set; прочие ключи — rawset,
    -- НО не затеняем методы (props.onChange не должен перекрыть Node:onChange)
    if props then
        for k, v in pairs(props) do
            if self._spec[k] then
                self[k] = v
            else
                local cls = self._class
                local isMethod = false
                while cls do
                    if rawget(cls, k) ~= nil then isMethod = true; break end
                    cls = cls._super
                end
                if isMethod then
                    DXUI._warn("props key shadows a method (skipped): " .. tostring(k))
                else
                    self[k] = v
                end
            end
        end
    end

    -- Stage 7b: theme-дефолты для свойств, не заданных в props (§63).
    -- Lookup ленивый — style/theme.lua загружается позже, но до runtime.
    if DXUI.Widget and DXUI.Widget.applyThemeDefaults then
        DXUI.Widget.applyThemeDefaults(self, props)
    end

    rawset(self, "_building", nil)
    return self
end

-- ---------------------------------------------------------------------
-- Наследование (простое prototype-наследование Lua 5.1)
-- ---------------------------------------------------------------------

--- Создаёт подкласс. self — родительский класс.
function Node:extend(name, properties)
    local Sub = {}
    Sub._name = name
    Sub._super = self
    Sub.properties = properties or {}
    Sub._spec = {}
    for k, v in pairs(self._spec) do Sub._spec[k] = v end
    for k, v in pairs(Sub.properties) do Sub._spec[k] = v end
    setmetatable(Sub, { __index = self })
    return Sub
end

-- ---------------------------------------------------------------------
-- Mutation layer (единая точка изменения свойств)
-- ---------------------------------------------------------------------

function Node:_set(key, value)
    if self._destroyed then
        DXUI._warn("set on destroyed node: " .. key)
        return self
    end
    local spec = self._spec[key]
    if not spec then
        rawset(self, key, value)
        return self
    end
    if spec.validate and not spec.validate(value) then
        error("invalid value for '" .. key .. "': " .. tostring(value), 2)
    end
    if spec.transform then
        value = spec.transform(value)
    end
    -- §26: то же значение — без инвалидации (и без циклов layout↔size).
    if self._data[key] == value then return self end
    self._data[key] = value
    -- ручная запись свойства снимает с него theme-происхождение: смена
    -- стиля не перезапишет то, что пользователь задал явно (§63)
    if self._themeApplied and not self._applyingTheme then
        self._themeApplied[key] = nil
    end
    -- и фиксирует user-ownership: смена стиля не тронет свойство,
    -- заданное явно (props или manual) или системой (layout/autosize).
    if not self._applyingTheme then
        self._userSet = self._userSet or {}
        self._userSet[key] = true
    end
    self:_invalidate(spec.invalidates)
    -- спец-хук свойства (style → переключение стиля); после инвалидации,
    -- т.к. хук сам пишет свойства через тот же mutation layer
    if spec.onSet then spec.onSet(self, value) end
    return self
end

function Node:_invalidate(categories)
    for i = 1, #categories do
        self._dirty[categories[i]] = true
    end
    if self._context then
        self._context:_queueDirty(self)
    end
end

function Node:_hasDirty()
    for _, v in pairs(self._dirty) do
        if v then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Method-style setters/getters (тот же mutation layer)
-- ---------------------------------------------------------------------

function Node:setPosition(x, y)
    self:_set("x", x)
    self:_set("y", y)
    return self
end

function Node:getPosition()
    return self.x, self.y
end

function Node:setSize(w, h)
    self:_set("width", w)
    self:_set("height", h)
    return self
end

function Node:getSize()
    return self.width, self.height
end

function Node:setVisible(v)
    self:_set("visible", v)
    return self
end

function Node:isVisible()
    return self.visible
end

function Node:show() return self:setVisible(true) end
function Node:hide() return self:setVisible(false) end

function Node:setEnabled(v)
    self:_set("enabled", v)
    return self
end

function Node:isEnabled()
    return self.enabled
end

function Node:setOpacity(v)
    self:_set("opacity", v)
    return self
end

-- ---- Stage 7b: animation (§51–§53) ---------------------------------
-- Меняет реальные свойства через нормальный mutation layer (никаких
-- дублирующих node.x / animation.x). Единый тик — в Context:renderFrame.
-- Возвращает AnimHandle: :after(...) цепочка, :onDone(fn), :cancel() (§52).

function Node:animate(props, duration, ease)
    if self._context and self._context.animation then
        return self._context.animation:animate(self, props, duration, ease)
    end
    return self -- без контекста (до монтирования) — no-op, прежний chaining
end

function Node:stopAnimations()
    if self._context and self._context.animation then
        self._context.animation:stop(self)
    end
    return self
end

function Node:isAnimating()
    if self._context and self._context.animation then
        return self._context.animation:isAnimating(self)
    end
    return false
end

-- ---- Stage 7b: autosize hook (§29) -----------------------------------
--- Измеряет содержимое для autoSize. Node-базовая: текущий размер (стабильно).
-- Widget переопределяет (дети), Label — текст.
function Node:_measureContent()
    return self.width, self.height
end

function Node:setZIndex(z)
    self:_set("zIndex", z)
    return self
end

function Node:setLayer(l)
    self:_set("layer", l)
    return self
end

--- Stage 7: поверх соседей — zIndex = max(соседей)+1 (no-op если уже сверху).
function Node:bringToFront()
    local maxZ = -1
    local siblings = self._parent and self._parent._children or nil
    if not siblings then return self end
    for i = 1, #siblings do
        local s = siblings[i]
        if s ~= self and s.zIndex > maxZ then maxZ = s.zIndex end
    end
    if maxZ >= self.zIndex then
        self.zIndex = maxZ + 1
    end
    return self
end

-- ---- Stage 5: layout setters ----------------------------------------
function Node:setLayoutMode(mode)
    self:_set("layoutMode", mode)
    return self
end

function Node:setAnchor(anchor)
    self:_set("anchor", anchor)
    return self
end

function Node:setMargin(l, t, r, b)
    self:_set("margin", { left = l, top = t, right = r, bottom = b })
    return self
end

function Node:setPadding(l, t, r, b)
    self:_set("padding", { left = l, top = t, right = r, bottom = b })
    return self
end

-- ---------------------------------------------------------------------
-- Parent / child
-- ---------------------------------------------------------------------

function Node:addChild(child)
    child:setParent(self)
    return self
end

function Node:setParent(parent)
    if parent == self._parent then return self end
    if parent == self then
        error("cannot set a node as its own parent", 2)
    end
    if parent and parent._destroyed then
        error("cannot set parent to a destroyed node", 2)
    end

    -- защита от циклов: parent не должен быть потомком self
    local p = parent
    while p do
        if p == self then
            error("cycle detected in parent chain", 2)
        end
        p = p._parent
    end

    -- отвязать от старого родителя
    if self._parent then
        self._parent:_removeChild(self)
    end
    self._parent = parent
    if parent then
        parent._children[#parent._children + 1] = self
        -- Слой НЕ мутируется при attach: эффективный слой (собственный
        -- не-BASE, иначе — ближайшего предка с не-BASE слоем) вычисляется
        -- при сборе списков (Context:_collectRenderable/_collectInteractive).
        -- Это чинит «застревание» детей в MODAL после setModal(false) и
        -- убирает неявную модификацию свойства (§95).
    end

    -- распространить контекст на поддерево
    self:_setContextRecursive(parent and parent._context or nil)

    -- инвалидация
    self:_invalidate({ DIRTY.LAYOUT })
    if parent then
        parent:_invalidate({ DIRTY.CHILDREN, DIRTY.LAYOUT })
    end
    return self
end

function Node:_removeChild(child)
    local children = self._children
    for i = 1, #children do
        if children[i] == child then
            table.remove(children, i)
            return
        end
    end
end

function Node:_setContextRecursive(ctx)
    self._context = ctx
    if ctx and self:_hasDirty() then
        ctx:_queueDirty(self)
    end
    local children = self._children
    for i = 1, #children do
        children[i]:_setContextRecursive(ctx)
    end
end

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------

function Node:destroy()
    if self._destroyed then return end
    self._destroyed = true

    -- хук очистки для composite-виджетов (modal overlay, popup stack и т.п.)
    -- ДО сноса детей — _context ещё жив
    if self._onDestroy then
        self:_onDestroy()
    end

    -- дети первыми (родитель владеет детьми)
    local children = self._children
    for i = #children, 1, -1 do
        children[i]:destroy()
    end

    -- отвязать от родителя
    if self._parent then
        self._parent:_removeChild(self)
        self._parent = nil
    end

    -- убрать из очереди контекста
    if self._context then
        self._context:_onNodeDestroyed(self)
    end

    -- очистить ссылки (освобождает node-owned ресурсы в Stage 3+)
    self._context = nil
    self._children = {}
    self._data = {}
    self._dirty = {}
    self._queued = false
    self._listeners = nil -- §14: destroy снимает подписки (нет событий с мёртвого узла)
end

function Node:isDestroyed()
    return self._destroyed
end

function Node:isAlive()
    return not self._destroyed
end

-- ---------------------------------------------------------------------
-- Публикация
-- ---------------------------------------------------------------------
DXUI.Node = Node
