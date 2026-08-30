--[[
    proxy.lua

    Пользовательский handle: лёгкая таблица {id = N}, отдающая удобный
    объектный API (node:setPosition(...)) поверх сырых операций Storage.

    Ключевое решение (см. обсуждение архитектуры перед ADR-документом):
    proxy-объекты ПУЛЯТСЯ так же, как node-слоты, а не создаются заново на
    каждый ui.create()/destroy(). Единая metatable создаётся один раз на
    модуль, а не на каждый объект — иначе каждый create() тратил бы лишнюю
    таблицу под metatable, что для сценария виртуализированных списков
    (§58 исходного ТЗ, тысячи create/destroy) было бы заметным churn'ом
    для GC.

    Proxy никогда не хранит данные узла — только id. Вся реальная работа
    делегируется в Storage. Это то же самое "тонкий handle поверх плотных
    данных", что и ADR-002, только с человеческим лицом для разработчика.
]]

DXUI = DXUI or {}
local C = DXUI.Constants

local TOOLTIP_DELAY_MS = 400 -- M20 (ADR-024): задержка показа tooltip

local Proxy = {}
Proxy.__index = Proxy
DXUI.Proxy = Proxy

-- M20: kernel — опциональный 4-й аргумент (tooltip delay через schedule).
function Proxy.new(storage, eventBus, animPool, kernel)
    local self = setmetatable({}, Proxy)
    self.storage = storage
    self.eventBus = eventBus
    self.animPool = animPool

    -- Пул свободных proxy-таблиц, готовых к переиспользованию.
    self.pool = {}
    self.poolCount = 0

    -- Единая metatable на все proxy этого экземпляра библиотеки.
    -- __index указывает на методы; сами методы читают self.id и дергают storage.
    local methods = {}
    self.methods = methods
    self.mt = { __index = methods }

    local proxyFactory = self -- M17: фабрика для создания tooltip-узлов из методов
    local storageRef = storage -- upvalue для замыканий методов
    local eventBusRef = eventBus
    local animPoolRef = animPool -- M6
    local kernelRef = kernel -- M20 (ADR-024): tooltip delay через Kernel:schedule

    -- M6: таблица свойств для animateTo — строится ОДИН раз на Proxy (cold),
    -- не на каждый вызов animateTo (aloc в user-event допустим, но зачем).
    -- M20 (ADR-024): + opacity (fade-анимации).
    local ANIM_FIELDS = {
        { C.ANIM_X, "x" }, { C.ANIM_Y, "y" }, { C.ANIM_W, "w" }, { C.ANIM_H, "h" },
        { C.ANIM_OPACITY, "opacity" },
    }

    function methods:setPosition(x, y)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setPosition: proxy uses a destroyed node")
        s.x[slot] = x
        s.y[slot] = y
        -- M9: DIRTY_POS — единый бит (layout+transform+render), см. constants.
        s:markDirty(self.id, C.DIRTY_POS)
        return self
    end

    function methods:setSize(w, h)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setSize: proxy uses a destroyed node")
        s.w[slot] = w
        s.h[slot] = h
        -- M9: DIRTY_POS — единый бит (layout+transform+render).
        s:markDirty(self.id, C.DIRTY_POS)
        return self
    end

    function methods:getPosition()
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "getPosition: proxy uses a destroyed node")
        return s.x[slot], s.y[slot]
    end

    function methods:getSize()
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "getSize: proxy uses a destroyed node")
        return s.w[slot], s.h[slot]
    end

    function methods:setVisible(visible)
        storageRef:setFlag(self.id, C.FLAG_VISIBLE, visible)
        storageRef:markDirty(self.id, C.DIRTY_VISIBILITY + C.DIRTY_RENDER)
        return self
    end    function methods:isVisible()
        return storageRef:hasFlag(self.id, C.FLAG_VISIBLE)
    end

    -- M3: включает/выключает участие узла в hit-test'е (§27/§28 ТЗ).
    -- Не влияет на видимость/рендер — узел может быть виден, но не кликабелен
    -- (например, декоративная подложка), и наоборот в теории (обычно нет).
    function methods:setEnabled(enabled)
        storageRef:setFlag(self.id, C.FLAG_ENABLED, enabled)
        return self
    end

    function methods:isEnabled()
        return storageRef:hasFlag(self.id, C.FLAG_ENABLED)
    end

    -- M20 (ADR-024): disabled — визуально "серый" + не кликабелен.
    -- Включает и выключает hit-test через setEnabled, плюс модулирует
    -- opacity (полупрозрачный вид) — per-node, дети не трогаем (ADR-024).
    function methods:setDisabled(disabled)
        self:setEnabled(not disabled)
        self:setOpacity(disabled and 120 or 255)
        return self
    end

    function methods:isDisabled()
        return not storageRef:hasFlag(self.id, C.FLAG_ENABLED)
    end

    -- ---- M4: layout setters (ADR-007) --------------------------------
    function methods:setLayoutMode(mode)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setLayoutMode: proxy uses a destroyed node")
        s.layoutMode[slot] = mode
        s:markDirty(self.id, C.DIRTY_LAYOUT)
        return self
    end

    function methods:setAnchor(anchor)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setAnchor: proxy uses a destroyed node")
        s.anchor[slot] = anchor
        s:markDirty(self.id, C.DIRTY_LAYOUT)
        return self
    end

    function methods:setMargin(l, t, r, b)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setMargin: proxy uses a destroyed node")
        local packed = (l % 256) + (t % 256) * 256 + (r % 256) * 65536 + (b % 256) * 16777216
        s.margin[slot] = packed
        s:markDirty(self.id, C.DIRTY_LAYOUT)
        return self
    end

    function methods:setPadding(l, t, r, b)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setPadding: proxy uses a destroyed node")
        local packed = (l % 256) + (t % 256) * 256 + (r % 256) * 65536 + (b % 256) * 16777216
        s.padding[slot] = packed
        s:markDirty(self.id, C.DIRTY_LAYOUT)
        return self
    end

    -- ---- M5: clip/opacity/blur setters (ADR-009) -----------------------
    function methods:setClip(enabled)
        storageRef:setFlag(self.id, C.FLAG_CLIP, enabled)
        storageRef:markDirty(self.id, C.DIRTY_LAYOUT + C.DIRTY_RENDER)
        return self
    end

    function methods:setOpacity(opacity)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setOpacity: proxy uses a destroyed node")
        s.opacity[slot] = opacity
        local wasFlag = s:hasFlag(self.id, C.FLAG_OPACITY)
        local isFlag = opacity ~= 255
        if wasFlag ~= isFlag then
            s:setFlag(self.id, C.FLAG_OPACITY, isFlag)
        end
        s:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    function methods:setBlur(blur)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setBlur: proxy uses a destroyed node")
        s.blur[slot] = blur
        local wasFlag = s:hasFlag(self.id, C.FLAG_BLUR)
        local isFlag = blur ~= 0
        if wasFlag ~= isFlag then
            s:setFlag(self.id, C.FLAG_BLUR, isFlag)
        end
        s:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    -- ---- M2: render-релевантные setters -------------------------------
    function methods:setColor(packedRGBA)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setColor: proxy uses a destroyed node")
        s.color[slot] = packedRGBA
        s:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    function methods:setText(text)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setText: proxy uses a destroyed node")
        s.text[slot] = text
        s:markDirty(self.id, C.DIRTY_CONTENT + C.DIRTY_RENDER)
        return self
    end

    function methods:setTexture(textureHandle)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setTexture: proxy uses a destroyed node")
        s.texture[slot] = textureHandle
        s:markDirty(self.id, C.DIRTY_CONTENT + C.DIRTY_RENDER)
        return self
    end

    function methods:setLayer(layer)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setLayer: proxy uses a destroyed node")
        s.layer[slot] = layer
        s.orderDirty = true
        s:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    -- M12: z-порядок внутри layer (batcher сортирует layer -> zIndex -> type -> id).
    -- Меняет порядок отрисовки -> orderDirty (как setLayer).
    function methods:setZIndex(z)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setZIndex: proxy uses a destroyed node")
        s.zIndex[slot] = z
        s.orderDirty = true
        s:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    -- Optimization hint из ADR-004 (auto-уровень RT-кэша): не создаёт RT сам
    -- по себе, лишь помечает поддерево кандидатом для авто-кэширования —
    -- фактическое кэширование реализует Render/RT Manager в M5.
    function methods:setStatic(isStatic)
        storageRef:setFlag(self.id, C.FLAG_STATIC, isStatic)
        storageRef:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    -- Явный pinned RT-кэш (ADR-004): не вытесняется автоматически.
    -- Фактическое создание RT — обязанность RT Manager (M5); здесь только флаг.
    function methods:pinRenderTarget(pinned)
        storageRef:setFlag(self.id, C.FLAG_PINNED_RT, pinned)
        storageRef:markDirty(self.id, C.DIRTY_RENDER)
        return self
    end

    function methods:setParent(parentProxyOrId)
        local parentId = parentProxyOrId
        if type(parentProxyOrId) == "table" then
            parentId = parentProxyOrId.id
        end
        storageRef:setParent(self.id, parentId)
        return self
    end

    -- M17 (ADR-021): tooltip — hover-подсказка. Создаёт PANEL+TEXT (дети узла,
    -- LAYER_TOOLTIP, ниже узла), показывает на mouseenter, скрывает на mouseleave.
    -- Дети узла -> destroy-каскад сносит tooltip вместе с узлом (без утечки).
    -- setTooltip(nil) — скрыть и очистить текст.
    function methods:setTooltip(text)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "setTooltip: proxy uses a destroyed node")

        if text == nil then
            if self._tooltip then
                self._tooltip.panel:setVisible(false)
                self._tooltip.label:setText("")
            end
            return self
        end

        if not self._tooltip then
            local panelId = s:createNode(C.NODE_PANEL, self.id)
            local panel = proxyFactory:acquire(panelId)
            panel:setLayer(C.LAYER_TOOLTIP) -- переопределить унаследованный слой
            panel:setColor(0xE61E1E1E)      -- тёмный фон
            panel:setEnabled(false)         -- не участвует в hit-test
            panel:setVisible(false)

            local textId = s:createNode(C.NODE_TEXT, panelId) -- наследует TOOLTIP
            local label = proxyFactory:acquire(textId)
            label:setColor(0xFFFFFFFF)
            label:setEnabled(false)

            self._tooltip = { panel = panel, label = label }

            -- hover wiring (cold path — регистрация один раз).
            -- M20 (ADR-024): показ с задержкой TOOLTIP_DELAY_MS через
            -- Kernel:schedule (единый clock, без setTimer). Колбэк сам
            -- проверяет актуальность (hoveredId + isAlive) — отмена не нужна.
            local targetId = self.id
            local function showTip()
                local tslot = s.idToSlot[targetId]
                if not tslot then return end
                if not panel:isAlive() then return end
                panel:setPosition(0, s.h[tslot] + 4)
                panel:setVisible(true)
            end
            eventBusRef:on(targetId, "mouseenter", function()
                if kernelRef and kernelRef.schedule then
                    kernelRef:schedule(TOOLTIP_DELAY_MS, function()
                        if kernelRef.dispatcher.hoveredId ~= targetId then return end
                        showTip()
                    end)
                else
                    showTip() -- fallback без kernel — немедленно
                end
            end)
            eventBusRef:on(targetId, "mouseleave", function()
                if panel:isAlive() then panel:setVisible(false) end
            end)
        end

        local tip = self._tooltip
        tip.label:setText(text)
        -- размер панели по длине текста (monospace estimate, как Edit M15)
        local tw = #text * 7 + 8
        tip.panel:setSize(tw, 20)
        tip.label:setPosition(4, 3)
        tip.label:setSize(tw - 8, 14)
        return self
    end

    -- M3: публичная строковая API поверх числового EventBus (ADR-006 —
    -- строки допустимы в cold path регистрации, не в hot path диспетчеризации).
    function methods:on(eventName, fn)
        eventBusRef:on(self.id, eventName, fn)
        return self
    end

    -- M6: Animation (ADR-010). Анимация — cold path (событие пользователя):
    -- в пул записываются ДАННЫЕ (from/to/dur/ease), движением управляет
    -- единый тик AnimationPool:update() в начале renderFrame. Никаких
    -- setTimer на узел.
    --
    -- props: {x=, y=, w=, h=, opacity=} — целевые значения свойств (то, что
    -- задаёт setPosition/setSize/setOpacity); duration в мс (default 300);
    -- ease — C.EASE_* (default C.EASE_DEFAULT = smoothstep).
    -- Запуск прерывает уже идущую анимацию того же свойства (start от
    -- ТЕКУЩЕГО значения, т.е. плавно, без скачка).
    function methods:animateTo(props, duration, ease)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "animateTo: proxy uses a destroyed node")
        assert(type(props) == "table", "animateTo: props must be {x=,y=,w=,h=,opacity=}")
        duration = duration or 300
        for i = 1, #ANIM_FIELDS do
            local f = ANIM_FIELDS[i]
            local target = props[f[2]]
            if target ~= nil then
                animPoolRef:start(self.id, f[1], target, duration, ease)
            end
        end
        return self
    end

    --- M6: останавливает все анимации узла (значение остаётся текущим).
    function methods:stopAnimations()
        local slot = storageRef.idToSlot[self.id]
        assert(slot, "stopAnimations: proxy uses a destroyed node")
        animPoolRef:stop(self.id)
        return self
    end

    --- M6: есть ли у узла хотя бы одна активная анимация.
    function methods:isAnimating()
        local s = storageRef
        local slot = s.idToSlot[self.id]
        if not slot then return false end
        return s.animX[slot] ~= C.NO_ANIM_SLOT
            or s.animY[slot] ~= C.NO_ANIM_SLOT
            or s.animW[slot] ~= C.NO_ANIM_SLOT
            or s.animH[slot] ~= C.NO_ANIM_SLOT
            or s.animOpacity[slot] ~= C.NO_ANIM_SLOT -- M20
    end

    function methods:isAlive()
        return storageRef:isAlive(self.id)
    end

    function methods:destroy()
        storageRef:destroyNode(self.id)
        -- id больше не валиден; сам proxy можно вернуть в пул через
        -- Proxy-фабрику (release), это ответственность вызывающей стороны
        -- (Node API в M2+ будет делать это автоматически при явном destroy()).
    end

    return self
end

--- Выдаёт proxy для существующего id: либо переиспользует объект из пула,
-- либо создаёт новую таблицу (только если пул пуст — тогда это разовая
-- аллокация, которая при следующем release() вернётся в пул и больше не
-- потребует создания новой таблицы).
function Proxy:acquire(id)
    local handle
    if self.poolCount > 0 then
        handle = self.pool[self.poolCount]
        self.pool[self.poolCount] = nil
        self.poolCount = self.poolCount - 1
        -- M12: пул мог вернуть handle с widget-metatable (composite, ADR-016) -- сброс
        setmetatable(handle, self.mt)
    else
        handle = setmetatable({}, self.mt)
    end
    handle.id = id
    return handle
end

--- Возвращает proxy-таблицу в пул для переиспользования. Вызывающая сторона
-- обязана не использовать handle после release() — id уже мог быть уничтожен.
function Proxy:release(handle)
    handle.id = C.NIL_ID
    -- M12 (ADR-016): composite-виджеты держат на handle служебные поля -- чистим,
    -- иначе пул выдаст "грязный" handle следующему узлу.
    handle._parts = nil
    handle._win = nil
    handle._kernel = nil
    handle._tooltip = nil -- M17 (ADR-021)
    handle._popupShown = nil -- M17 (ADR-021)
    setmetatable(handle, self.mt)
    self.poolCount = self.poolCount + 1
    self.pool[self.poolCount] = handle
end
