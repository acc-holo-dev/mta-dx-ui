--[[
    widget.lua — DXUI V2

    Widget: базовый класс всех виджетов. Наследует Node и добавляет контракт
    виджета (§98): create / render / input behavior / properties / events /
    destroy.

    Новый виджет пишется БЕЗ изменения core/kernel/storage/dispatcher —
    только через существующие интерфейсы (§74):

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

    render() — контракт отрисовки. Вызывается renderer'ом (Stage 3), а не
    напрямую виджетом. В Stage 2 render() — заглушка-контракт.
]]

DXUI = DXUI or {}

local DIRTY = DXUI.DIRTY

local Widget = DXUI.Node:extend("Widget", {
    -- Виджет добавляет цвет как first-class свойство (Node его не имеет —
    -- цвет — визуальная характеристика виджета, а не базового узла).
    color = { default = 0xFFFFFFFF, invalidates = { DIRTY.RENDER } },
})

-- ---------------------------------------------------------------------
-- Контракт отрисовки (Stage 3 реализует renderer; здесь — заглушка)
-- ---------------------------------------------------------------------

--- Отрисовывает виджет через публичный renderer API (§72/§73).
-- Переопределяется каждым конкретным виджетом.
function Widget:render(renderer)
    -- Базовый виджет ничего не рисует. Конкретные виджеты переопределяют.
end

-- ---------------------------------------------------------------------
-- События (минимальный реестр; полная bubble-система — Stage 4)
-- ---------------------------------------------------------------------

--- Подписка на событие. fn(event). Возвращает self (chaining).
-- Слушатель хранится на самом узле (node._listeners); EventBus.emit читает
-- его при бабблинге. Работает и до монтирования узла в контекст.
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

--- Доставляет событие, начиная с этого узла, с бабблингом вверх (Stage 4).
function Widget:emit(eventName, event)
    return DXUI.EventBus.emit(self, eventName, event)
end

-- ---------------------------------------------------------------------
-- Публикация
-- ---------------------------------------------------------------------
DXUI.Widget = Widget
