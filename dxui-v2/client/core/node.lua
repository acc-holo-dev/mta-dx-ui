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
    x        = { default = 0,    invalidates = { DIRTY.LAYOUT } },
    y        = { default = 0,    invalidates = { DIRTY.LAYOUT } },
    width    = { default = 0,    invalidates = { DIRTY.LAYOUT } },
    height   = { default = 0,    invalidates = { DIRTY.LAYOUT } },
    visible  = { default = true, invalidates = { DIRTY.VISIBILITY, DIRTY.INPUT, DIRTY.RENDER } },
    enabled  = { default = true, invalidates = { DIRTY.INPUT } },
    opacity  = { default = 1,    invalidates = { DIRTY.RENDER } },
    zIndex   = { default = 0,    invalidates = { DIRTY.INPUT, DIRTY.RENDER } },
    layer    = { default = LAYER.BASE, invalidates = { DIRTY.RENDER } },
    style    = { default = nil,  invalidates = { DIRTY.STYLE } },
    userData = { default = nil,  invalidates = {} },
}

Node._spec = Node.properties

-- read-only вычисляемые поля (управляются методами, не присваиванием)
local READONLY = {
    parent = true, children = true, id = true,
    context = true, destroyed = true,
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
    nextId = nextId + 1

    -- значения по умолчанию
    for k, spec in pairs(cls._spec) do
        self._data[k] = spec.default
    end

    -- применить props (через __newindex -> _set)
    if props then
        for k, v in pairs(props) do
            self[k] = v
        end
    end

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
    self._data[key] = value
    self:_invalidate(spec.invalidates)
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

function Node:setZIndex(z)
    self:_set("zIndex", z)
    return self
end

function Node:setLayer(l)
    self:_set("layer", l)
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
end

function Node:isDestroyed()
    return self._destroyed
end

-- ---------------------------------------------------------------------
-- Публикация
-- ---------------------------------------------------------------------
DXUI.Node = Node
