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

local Proxy = {}
Proxy.__index = Proxy
DXUI.Proxy = Proxy

function Proxy.new(storage, eventBus, animPool)
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

    local storageRef = storage -- upvalue для замыканий методов
    local eventBusRef = eventBus
    local animPoolRef = animPool -- M6

    -- M6: таблица свойств для animateTo — строится ОДИН раз на Proxy (cold),
    -- не на каждый вызов animateTo (aloc в user-event допустим, но зачем).
    local ANIM_FIELDS = {
        { C.ANIM_X, "x" }, { C.ANIM_Y, "y" }, { C.ANIM_W, "w" }, { C.ANIM_H, "h" },
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
    -- props: {x=, y=, w=, h=} — целевые значения локальных свойств (то, что
    -- задаёт setPosition/setSize); duration в мс (default 300); ease —
    -- C.EASE_* (default C.EASE_DEFAULT = smoothstep).
    -- Запуск прерывает уже идущую анимацию того же свойства (start от
    -- ТЕКУЩЕГО значения, т.е. плавно, без скачка).
    function methods:animateTo(props, duration, ease)
        local s = storageRef
        local slot = s.idToSlot[self.id]
        assert(slot, "animateTo: proxy uses a destroyed node")
        assert(type(props) == "table", "animateTo: props must be {x=,y=,w=,h=}")
        duration = duration or 300
        for i = 1, 4 do
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
    self.poolCount = self.poolCount + 1
    self.pool[self.poolCount] = handle
end
