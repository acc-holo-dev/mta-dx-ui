# DXUI

Высокопроизводительный retained-mode DX GUI-фреймворк для **MTA:SA** (Multi Theft Auto: San Andreas, клиентский Lua 5.1, DirectX 9).

> **Принцип:** «просто снаружи, сложно внутри» (§42 ТЗ). Публичный API — декларативный и минимальный; внутри — data-oriented ядро (SoA), dirty-bitmask инвалидация, zero-work idle-кадры.

---

## Статус

| Веха | Содержание | Статус |
|------|-----------|--------|
| M1 | Ядро: Storage (SoA), handle/ID, dirty-система | ✅ |
| M2 | Render pipeline: cmd-пул, Builder, Batcher, StateCache | ✅ |
| M3 | Input: единый dispatcher, hit-test, события | ✅ |
| M4 | Layout: LAY_ABS/REL/CENTER, anchor, margin, padding | ✅ |
| M5 | Clip/Opacity/Blur: dirty-driven clip-глубина + state | ✅ |
| M6 | Animation: AnimationPool (SoA), без per-node таймеров | ✅ |
| M7 | Widgets: декларативный API (window/panel/button/label/image) | ✅ |
| M8 | Advanced: RT-clip, opacity (alpha), blur (HLSL shader) | ✅ |
| M9 | Optimization: slot dirtyList, итеративный layout, DIRTY_POS | ✅ |
| M10 | Production: Profiler, Debug-система, minimal overhead | ✅ |

Версия: `1.0.0-M10`. Тесты: **177/177** зелёные.

---

## Архитектура

### Конвейер кадра (`Kernel:renderFrame`)

```
animPool:update → Culling → Layout → Clip → Builder → Batcher
  → StateCache:executeOrder → StateCache:flushClip → endFrame
```

Каждый проход работает **только по dirty-узлам** (ADR-001/003). Idle-кадр без изменений = **zero work** (§8 ТЗ).

### Хранение: SoA (ADR-002)

Узлы хранятся не как объекты, а как **плоские массивы полей** (Structure of Arrays), индексированные по `slot`:

```lua
storage.x[slot], storage.y[slot], storage.w[slot], storage.h[slot]
storage.worldX[slot], storage.worldY[slot]  -- результат layout
storage.nodeType[slot], storage.flags[slot], storage.dirty[slot]
```

`id ↔ slot` через `idToSlot`/`slotToId`. Уничтожение — swap-with-last компакция (O(1)).

### Dirty-система (ADR-001/003)

Каждый узел несёт битовую маску `dirty`. Каждый бит инвалидирует ровно одну подсистему:

| Бит | Подсистема |
|-----|-----------|
| `DIRTY_LAYOUT` (0x001) | пересчёт позиции/размера |
| `DIRTY_STYLE` (0x002) | визуальный стиль |
| `DIRTY_CONTENT` (0x004) | текст/текстура |
| `DIRTY_TRANSFORM` (0x008) | позиция/масштаб |
| `DIRTY_VISIBILITY` (0x010) | видимость/culling |
| `DIRTY_RENDER` (0x020) | перегенерация команды |
| `DIRTY_CHILDREN` (0x040) | состав детей |
| `DIRTY_INPUT` (0x080) | hit-test список |
| `DIRTY_POS` (0x091) | слитый бит (layout+transform+render) |

`dirtyList` — плоский массив без дублей (бит `DIRTY_QUEUED` = «уже в списке»).

### Handle/ID (ADR-005)

Публичный API возвращает **proxy-handle** (таблица из пула). Внутри — числовой `id` (стабилен, freelist) и `slot` (SoA-индекс, двигается при destroy).

---

## Быстрый старт

```lua
-- bootstrap.lua уже создаёт DXUI.instance и DXUI.ui.

local ui = DXUI.ui

local win = ui:window({
    title = "Settings",
    x = 100, y = 80, w = 320, h = 240,
    children = {
        ui:label({ text = "Volume", x = 10, y = 40 }),
        ui:button({ text = "OK", x = 10, y = 180, w = 100, h = 30,
            onClick = function() outputChatBox("OK pressed") end }),
    },
})

-- Анимация (M6)
win:animateTo({ x = 200, y = 100 }, 300, DXUI.Constants.EASE_IN_OUT)

-- Clip/Opacity/Blur (M5/M8)
local panel = ui:panel({ x = 0, y = 0, w = 200, h = 200, clip = true })
panel:setOpacity(128)  -- 0..255
panel:setBlur(2)       -- радиус blur (image only, M8)
```

---

## Публичный API

### Kernel (`DXUI.instance`)

| Метод | Описание |
|-------|----------|
| `create(nodeType, parent?)` | создать узел → proxy |
| `destroy(handle)` | уничтожить узел |
| `renderFrame()` | полный кадр (вызывается bootstrap'ом) |
| `setScreenSize(w, h)` | размер экрана (layout) |
| `setClock(fn)` | источник времени (мс) |
| `stats()` | `{liveNodes, dirtyQueued, freeIdsPooled, nextFreshId}` |
| `onCursorMove/onMouseDown/onMouseUp` | input (bootstrap) |

### Proxy (handle узла)

| Метод | Описание |
|-------|----------|
| `setPosition(x, y)` / `setSize(w, h)` | позиция/размер (DIRTY_POS) |
| `setVisible(v)` / `setEnabled(v)` | видимость/интерактивность |
| `setLayoutMode(m)` / `setAnchor(a)` | layout (LAY_ABS/REL/CENTER, ANCHOR_*) |
| `setMargin(l,t,r,b)` / `setPadding(l,t,r,b)` | отступы |
| `setClip(v)` / `setOpacity(o)` / `setBlur(b)` | clip/opacity/blur |
| `setColor(c)` / `setText(t)` / `setTexture(tex)` | контент |
| `setLayer(l)` / `setStatic(v)` / `setParent(p)` | слой/static/иерархия |
| `on(event, fn)` | подписка (click/mousedown/...) |
| `animateTo(props, dur, ease?)` | анимация (M6) |
| `destroy()` | уничтожить |

### Widgets (`DXUI.ui`)

`window`, `panel`, `button`, `label`, `image` — декларативные билдеры. Цвет: `0xAARRGGBB` (packed) или `"#RRGGBB[AA]"` или `{r,g,b,a}`.

---

## Debug / Profiler (M10)

Оба **OFF by default** — zero overhead в проде (§50 ТЗ).

```lua
DXUI.toggleProfile()  -- Profiler: avg-статистика 9 фаз кадра (overlay)
DXUI.toggleDebug()    -- Debug: bounds-overlay + инспекция

DXUI.debug:dumpTree()          -- печать дерева узлов
DXUI.debug:inspect(id)         -- детали узла
DXUI.debug:hitTest(x, y)       -- узел под курсором
```

---

## Тесты и бенчмарк

```bash
# Тесты (Python lupa, Lua 5.5 runtime)
.venv\\Scripts\\python.exe tests\\run_lupa.py test_kernel.lua   # и др.

# Бенчмарк (10 сценариев, median из 5 прогонов)
.venv\\Scripts\\python.exe -c "import lupa; lua=lupa.LuaRuntime(); lua.execute(open('bench/_run.lua', encoding='utf-8').read())"
```

> ⚠️ Windows `os.clock()` нестабилен (разброс ×30). Финальные замеры — в MTA (`getRealTime()`).

---

## ADR (Architecture Decision Records)

14 решений задокументированы в [`docs/adr/`](docs/adr/README.md): dirty-bitmask, SoA, dirty-очередь, RT-кэш, handle/ID, числовые константы, layout, anchors, clip/opacity/blur, animation, RT Manager, M9-оптимизации, Profiler, Debug.

---

## Известные ограничения

- **Nested clip** — полный вложенный стек реализован (M10, до 4 уровней). Глубже 4 — сводится к innermost.
- **Blur для rect/text** — реализован (M10) через RT-fallback: rect/text рендерится в RT, затем RT рисуется с blur-шейдером.
- **FLAG_STATIC / FLAG_PINNED_RT** — зарезервированы (ADR-004), RT-кэш статичных поддеревьев не реализован.
- **Rotation/scale** — анимация только x/y/w/h (ADR-010).

---

## Структура

```
client/
  core/       constants, storage, proxy, kernel
  render/     commands, culling, layout, clip, builder, batcher,
              state_cache, rt_manager, profiler, backend_mta
  anim/       animation (AnimationPool)
  input/      events, hittest, dispatcher
  widgets/    ui (декларативный API)
  debug/      debug (инспекция)
  bootstrap.lua
bench/        bench.lua (harness), _run.lua (standalone)
tests/        test_*.lua (177 тестов)
docs/adr/     ADR-001..014
```
