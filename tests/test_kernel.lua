--[[
    Тесты загружают файлы в ТОМ ЖЕ порядке и тем же способом (общий
    глобальный DXUI, без require), в каком их грузит meta.xml в реальной
    MTA-среде — чтобы тест проверял именно ту модель загрузки, которая
    будет использоваться в игре, а не удобную для автономного запуска
    альтернативу.
]]

dofile("loader.lua")

local Kernel = DXUI.Kernel
local Storage = DXUI.Storage
local C = DXUI.Constants

local passed, failed = 0, 0

local function check(name, cond)
    if cond then
        passed = passed + 1
        print("[OK]   " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

-- =======================================================================
-- 1. Базовое создание / destroy + compaction (ADR-002)
-- =======================================================================
do
    local s = Storage.new()
    local a = s:createNode(C.NODE_PANEL)
    local b = s:createNode(C.NODE_PANEL)
    local c = s:createNode(C.NODE_PANEL)

    check("create: 3 узла -> count == 3", s.count == 3)
    check("create: id уникальны", a ~= b and b ~= c and a ~= c)

    local slotA = s.idToSlot[a]
    s:destroyNode(a) -- уничтожаем НЕ последний -> должен сработать swap-with-last

    check("destroy: count уменьшился до 2", s.count == 2)
    check("destroy: id 'a' больше не разрешается", s.idToSlot[a] == nil)
    check("destroy: 'c' (был последним) переехал на освободившийся slot",
        s.idToSlot[c] == slotA)
    check("destroy: 'b' не пострадал", s.idToSlot[b] ~= nil)

    -- переиспользование освободившегося id
    local d = s:createNode(C.NODE_PANEL)
    check("create после destroy: id переиспользуется (freelist работает)", d == a)
end

-- =======================================================================
-- 2. Dirty dedup через QUEUED-бит (ADR-003)
-- =======================================================================
do
    local s = Storage.new()
    local a = s:createNode(C.NODE_PANEL)
    s:clearFrameDirty() -- сбрасываем dirty от самого createNode для чистоты теста

    check("dirty: после clearFrameDirty очередь пуста", s.dirtyCount == 0)

    s:markDirty(a, C.DIRTY_TRANSFORM)
    s:markDirty(a, C.DIRTY_STYLE)
    s:markDirty(a, C.DIRTY_RENDER)
    s:markDirty(a, C.DIRTY_TRANSFORM) -- повторно, тот же бит

    check("dirty: один и тот же узел помечен 4 раза -> одна запись в очереди",
        s.dirtyCount == 1)
    check("dirty: маска содержит все выставленные биты (transform+style+render)",
        s:hasDirty(a, C.DIRTY_TRANSFORM) and
        s:hasDirty(a, C.DIRTY_STYLE) and
        s:hasDirty(a, C.DIRTY_RENDER))
    check("dirty: бит, который не выставляли, отсутствует",
        not s:hasDirty(a, C.DIRTY_CONTENT))

    s:clearFrameDirty()
    check("dirty: после очистки кадра очередь снова пуста", s.dirtyCount == 0)
    check("dirty: после очистки маска узла обнулена",
        not s:hasDirty(a, C.DIRTY_TRANSFORM))

    -- узел должен снова попадать в очередь в СЛЕДУЮЩЕМ кадре
    s:markDirty(a, C.DIRTY_RENDER)
    check("dirty: узел снова dirty-able в новом кадре после очистки",
        s.dirtyCount == 1)
end

-- =======================================================================
-- 3. Dirty на уже уничтоженный узел — не должен падать (no-op)
-- =======================================================================
do
    local s = Storage.new()
    local a = s:createNode(C.NODE_PANEL)
    s:destroyNode(a)
    local ok = pcall(function() s:markDirty(a, C.DIRTY_RENDER) end)
    check("dirty: markDirty на destroyed id не падает (no-op)", ok)
end

-- =======================================================================
-- 4. Parent/child: иерархия, unlink, каскадное уничтожение
-- =======================================================================
do
    local s = Storage.new()
    local root = s:createNode(C.NODE_WINDOW)
    local p1 = s:createNode(C.NODE_PANEL, root)
    local p2 = s:createNode(C.NODE_PANEL, root)
    local btn = s:createNode(C.NODE_BUTTON, p1)

    local children = s:getChildren(root)
    check("hierarchy: у root 2 прямых ребёнка", #children == 2)

    local p1Children = s:getChildren(p1)
    check("hierarchy: у p1 1 ребёнок (btn)", #p1Children == 1 and p1Children[1] == btn)

    -- уничтожение p1 должно каскадно снести btn, но не тронуть p2/root
    s:destroyNode(p1)
    check("hierarchy: p1 уничтожен", not s:isAlive(p1))
    check("hierarchy: btn (ребёнок p1) уничтожен каскадно", not s:isAlive(btn))
    check("hierarchy: p2 жив", s:isAlive(p2))
    check("hierarchy: root жив, и у него остался 1 ребёнок (p2)",
        s:isAlive(root) and #s:getChildren(root) == 1)
end

-- =======================================================================
-- 5. Reparenting (setParent) корректно переносит узел между родителями
-- =======================================================================
do
    local s = Storage.new()
    local winA = s:createNode(C.NODE_WINDOW)
    local winB = s:createNode(C.NODE_WINDOW)
    local btn = s:createNode(C.NODE_BUTTON, winA)

    check("reparent: изначально btn у winA", #s:getChildren(winA) == 1)
    s:setParent(btn, winB)
    check("reparent: winA больше не имеет детей", #s:getChildren(winA) == 0)
    check("reparent: winB теперь имеет btn", #s:getChildren(winB) == 1 and s:getChildren(winB)[1] == btn)
end

-- =======================================================================
-- 6. Kernel facade + Proxy pooling
-- =======================================================================
do
    local k = Kernel.new()
    local button = k:create(C.NODE_BUTTON)
    button:setPosition(10, 20)
    button:setSize(100, 40)

    local x, y = button:getPosition()
    local w, h = button:getSize()
    check("proxy: setPosition/getPosition roundtrip", x == 10 and y == 20)
    check("proxy: setSize/getSize roundtrip", w == 100 and h == 40)

    button:setVisible(false)
    check("proxy: setVisible(false) отражается в isVisible()", button:isVisible() == false)

    -- проверяем реальное пуловое переиспользование proxy-таблиц
    local rawProxyTable = button
    k:destroy(button)
    check("proxy: после destroy узел не жив", not rawProxyTable:isAlive())

    local button2 = k:create(C.NODE_BUTTON)
    check("proxy: пул переиспользовал ту же Lua-таблицу под новый handle",
        button2 == rawProxyTable)
end

-- =======================================================================
-- 7. Нагрузочная проверка целостности: 2000 create/destroy в случайном порядке
-- =======================================================================
do
    local s = Storage.new()
    local alive = {}
    local ids = {}

    for i = 1, 2000 do
        local id = s:createNode(C.NODE_PANEL)
        alive[id] = true
        ids[#ids + 1] = id
    end

    -- уничтожаем каждый третий в порядке создания (не с конца — это и есть
    -- проверка swap-with-last на "неудобных" позициях)
    for i = 1, #ids, 3 do
        s:destroyNode(ids[i])
        alive[ids[i]] = nil
    end

    local expectedCount = 0
    for _ in pairs(alive) do expectedCount = expectedCount + 1 end

    check("stress: count после выборочного destroy соответствует ожиданию",
        s.count == expectedCount)

    local allConsistent = true
    for id, _ in pairs(alive) do
        if not s:isAlive(id) then allConsistent = false end
    end
    for id, _ in pairs(alive) do
        -- каждый живой id должен указывать на slot в пределах [1, count]
        local slot = s.idToSlot[id]
        if slot == nil or slot < 1 or slot > s.count then allConsistent = false end
        -- и slotToId должен указывать обратно на тот же id (нет перекрёстных ссылок)
        if s.slotToId[slot] ~= id then allConsistent = false end
    end
    check("stress: все живые id консистентны (idToSlot <-> slotToId, диапазон)",
        allConsistent)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
