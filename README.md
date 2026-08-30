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
| M11 | Stabilization: фиксы MTA-блокеров, Lua 5.1 pin, SelfTest, реформа тестов | ✅ |
| M12 | Window 2.0: composite-proxy, drag/resize/close/z-order/modal-флаг | ✅ |
| M13 | ScrollPanel: composite + wheel + drag scrollbar + virtualization + HitTest clip-aware | ✅ |
| M14 | Edit: text input + focus system + keyboard (onClientKey → focusedId) | ✅ |
| M15 | Edit 2.0: selection (drag-select) + clipboard + multiline + placeholder | ✅ |
| M16 | Modal: overlay + focus lock + input trap + наследование layer | ✅ |
| M17 | Tooltip + Popup + ContextMenu: hover-подсказка, dismiss по клику вне | ✅ |
| M18 | CheckBox + RadioButton + Slider + ProgressBar: input/display-контролы | ✅ |
| M19 | ComboBox + TabPanel + GridList: контейнерные виджеты | ✅ |
| M20 | Polish: ANIM_OPACITY (fade overlay/popup), tooltip delay, modal auto-focus, slider click-to-jump + vertical | ✅ |

Версия: `1.0.0-M20`. Тесты: **357/357** зелёные (16 файлов, Lua 5.1, ADR-015). SelfTest QUICK 11/11, FULL 8/8.

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

-- Window 2.0 (M12): drag по title bar, resize grip, close, z-order
local win2 = ui:window({
    title = "Full", x = 400, y = 80, w = 300, h = 220,
    closable = true, resizable = true,          -- opt-in
    onClose = function(e) outputChatBox("bye") end,
})
win2:setTitle("Renamed")
win2:bringToFront()
win2:close()  -- событие "close"; destroy отменяется через e.preventDefault()
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
| `setZIndex(z)` | z-порядок внутри layer (M12) |
| `on(event, fn)` | подписка (click/mousedown/.../close) |
| `animateTo(props, dur, ease?)` | анимация (M6) |
| `destroy()` | уничтожить |

### Widgets (`DXUI.ui`)

`window`, `panel`, `button`, `label`, `image` — декларативные билдеры. Цвет: `0xAARRGGBB` (packed) или `"#RRGGBB[AA]"` или `{r,g,b,a}`.

**Window 2.0** (M12, ADR-016) — composite-proxy (один handle → несколько узлов):

| Метод | Описание |
|-------|----------|
| `setTitle(t)` / `getTitle()` | текст title bar |
| `setDraggable(v)` / `setResizable(v)` / `setClosable(v)` | режимы окна |
| `bringToFront()` | поверх соседей (zIndex = max+1) |
| `setModal(v)` | LAYER_MODAL (полный focus trap — M18) |
| `close()` | событие `"close"`; destroy отменяется `e.preventDefault()` |

Props: `title`, `titleBar`, `closable`, `resizable`, `modal`, `minW`, `minH`, `onClose`. Drag — по title bar через dispatcher capture; hover-события на время drag подавлены. Bare window (без `title`/`titleBar`) — 1 узел, M7-совместимость.

**Modal** (M16, ADR-020): `modal = true` или таблица `{ overlay=bool, dismissOnClickOutside=bool, overlayColor=0xAARRGGBB }`. Пока modal активен — overlay (затемнение фона), focus lock (фокус только внутри окна), input trap (клики/колесо/наведение вне окна блокируются). `setModal(v)` — тот же API. `dismissOnClickOutside` — клик по overlay закрывает окно. Вложенные modal — через стек (z-порядок по глубине).

**Tooltip / Popup / ContextMenu** (M17, ADR-021):

| Виджет | API | Описание |
|--------|-----|----------|
| Tooltip | `node:setTooltip(text)` | hover-подсказка (любой узел), показ ниже узла на mouseenter |
| Popup | `ui:popup(props)` + `show(x,y)`/`hide()`/`isShown()`/`toggle()` | всплывающая панель (LAYER_POPUP), dismiss по клику вне |
| ContextMenu | `ui:contextmenu({ items = { {text=, onClick=}, ... } })` | popup со списком пунктов, hover-highlight, клик → onClick + hide |

ContextMenu типовое использование: `node:on("mousedown", function(e) if e.button == "right" then menu:show(e.x, e.y) end end)`. Dismiss по клику вне — через Dispatcher.popupStack (клик съедается, не доходит до фона).

**CheckBox / RadioButton / Slider / ProgressBar** (M18, ADR-022):

| Виджет | API | Описание |
|--------|-----|----------|
| CheckBox | `ui:checkbox({ text=, checked=, onChange= })` + `setChecked/isChecked/toggle` | флажок |
| RadioButton | `ui:radiobutton({ text=, checked=, group=, onChange= })` | радио-кнопка (группа через `group`) |
| Slider | `ui:slider({ min=, max=, value=, onChange= })` + `setValue/getValue/setRange` | ползунок (drag thumb) |
| ProgressBar | `ui:progressbar({ min=, max=, value= })` + `setValue/getValue/setRange` | индикатор |

Все — composite-proxy (1 handle → несколько узлов). Slider горизонтальный (drag через Dispatcher:beginDrag, delta-подход без world-координат). RadioButton: выбор одного снимает остальные в той же `group`.

**ComboBox / TabPanel / GridList** (M19, ADR-023):

| Виджет | API | Описание |
|--------|-----|----------|
| ComboBox | `ui:combobox({ items=, selected=, onChange= })` + `setItems/setSelected/getValue/open/close` | выпадающий список (dropdown = popup M17) |
| TabPanel | `ui:tabpanel({ onChange= })` + `addTab(title, children)/removeTab/selectTab` | вкладки (addTab возвращает page) |
| GridList | `ui:gridlist({ columns=, onSelect= })` + `addColumn/addRow/selectRow/clearRows` | таблица (скролл = ScrollPanel M13) |

ComboBox: `items` — строки или `{text=, value=}`; dropdown dismiss по клику вне (M17). TabPanel: `addTab("Title", {child1, child2})` или ручное прикрепление к возвращённой page. GridList: `columns = { {text=, width=} }`, `addRow({cell1, cell2, ...})`, встроенный скролл. Memo не нужен — Edit multiline (M15).

**M20 polish** (ADR-024): `animateTo({opacity=}, ms, ease)` — fade любого узла (ANIM_OPACITY); overlay modal и popup появляются fade-in (150/100ms). Tooltip — задержка 400ms через `Kernel:schedule` (единый clock, без setTimer). Modal авто-фокусирует первый Edit в окне (реестр `kernel.focusables`), иначе фокус на окно. Slider: `orientation="v"` (вертикальный) + click-to-jump по треку. Отложенные колбэки: `kernel:schedule(ms, fn)` — выполняются в renderFrame.

**ScrollPanel** (M13, ADR-017) — composite-proxy, scrollable container:

| Метод | Описание |
|-------|----------|
| `setScroll(x, y)` / `getScroll()` | позиция скролла (clamped + emit) |
| `getScrollMax()` / `scrollToPercent(px, py)` / `scrollBy(dx, dy)` | навигация |
| `setContentSize(w, h)` / `refresh()` | явный размер контента (nil = auto-measure) |
| `setVirtualProvider(prov)` | виртуализация: пул строк, bind по диапазону |
| `getContent()` | content-узел (для ручного прикрепления детей) |

Props: `axis` ("v"/"h"/"both"), `scrollbar` (default true), `smooth` (default false), `wheelStep`, `contentW`, `contentH`, `children` (в content). Wheel через MTA bindKey; hit-test уважает clip-регион (M13 core-улучшение).

**Edit** (M14, ADR-018) — composite-proxy, text input:

| Метод | Описание |
|-------|----------|
| `setText(t)` / `getText()` | текст поля |
| `setCursor(pos)` / `getCursor()` | позиция курсора (0..#text) |
| `setPlaceholder(t)` | текст-подсказка (M14: в state, M15: рендер) |
| `setMaxChars(n)` | cap на длину (0 = unlimited) |
| `setReadonly(v)` | readonly mode (фокус можно, ввод нельзя) |
| `setSelection(s, e)` / `getSelection()` | выделение [start, end) |
| `onFocus(fn)` / `onBlur(fn)` / `onEnter(fn)` / `onChange(fn)` | handlers |

Props: `text`, `placeholder`, `maxChars`, `readonly`, `multiline`, `textColor`, `onFocus`, `onBlur`, `onEnter`, `onChange`. Focus: mousedown (автоматически). Keyboard: EVENT_TEXT → append char; EVENT_KEY → special keys (backspace/delete/arrow_l/r/u/d/home/end/enter/escape). M15: drag-select (mousedown → beginDrag), clipboard (ctrl+a/c/v/x через kernel.clipboard), multiline (enter → \n, UP/DOWN + goalCol), placeholder render.

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
# Все тесты (Python lupa, Lua 5.1 runtime -- как MTA, ADR-015)
.venv\Scripts\python.exe tests\run_lupa.py --all

# SelfTest (QUICK/FULL) -- инварианты системы, в MTA и через lupa
#   DXUI.selfTest("quick") / DXUI.selfTest("full")

# Бенчмарк (10 сценариев, median из 5 прогонов)
.venv\Scripts\python.exe -c "import lupa.lua51; lua=lupa.lua51.LuaRuntime(); lua.execute(open('bench/_run.lua', encoding='utf-8').read())"
```

> ⚠️ Тесты pinned к Lua 5.1 (`lupa.lua51`): 5.3+ синтаксис (`//`, `<<`, `&`) невидим под 5.5, но **ломает MTA** (ADR-015). Windows `os.clock()` нестабилен — финальные замеры в MTA (`getTickCount()`).

---

## ADR (Architecture Decision Records)

24 решения задокументированы в [`docs/adr/`](docs/adr/README.md): dirty-bitmask, SoA, dirty-очередь, RT-кэш, handle/ID, числовые константы, layout, anchors, clip/opacity/blur, animation, RT Manager, M9-оптимизации, Profiler, Debug, Lua 5.1 pin (M11), Window 2.0 composite/drag (M12), ScrollPanel + wheel + virtualization (M13), Edit + focus + keyboard (M14), Edit 2.0 selection/clipboard/multiline (M15), Modal overlay/focus-lock/input-trap (M16), Tooltip/Popup/ContextMenu (M17), CheckBox/RadioButton/Slider/ProgressBar (M18), ComboBox/TabPanel/GridList (M19), M20 polish (opacity-anim, tooltip delay, modal auto-focus, slider).

---

## Известные ограничения

- **Nested clip** — полный вложенный стек реализован (M10, до 4 уровней). Глубже 4 — сводится к innermost.
- **Blur для rect/text** — реализован (M10) через RT-fallback: rect/text рендерится в RT, затем RT рисуется с blur-шейдером.
- **FLAG_STATIC / FLAG_PINNED_RT** — зарезервированы (ADR-004), RT-кэш статичных поддеревьев не реализован.
- **Rotation/scale** — анимация только x/y/w/h (ADR-010).
- **Window animateTo({w/h})** — не синхронизирует title bar (ADR-016); размер окна менять только через `win:setSize()`.
- **Modal** — M12 даёт только LAYER_MODAL; полный focus lock/trap — M18.

---

## Структура

```
client/
  core/       constants, storage, proxy, kernel, selftest
  render/     commands, culling, layout, clip, builder, batcher,
              state_cache, rt_manager, profiler, backend_mta
  anim/       animation (AnimationPool)
  input/      events, hittest (clip-aware M13), dispatcher (wheel M13)
  widgets/    ui (Window 2.0 composite M12, ScrollPanel composite M13)
  debug/      debug (инспекция)
  bootstrap.lua (wheel binding M13)
bench/        bench.lua (harness), _run.lua (standalone)
tests/        loader.lua (единый манифест загрузки), run_lupa.py,
              test_*.lua (357 тестов, Lua 5.1) — M1-M20
docs/adr/     ADR-001..017
```
