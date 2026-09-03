# DXUI — недоделанные задачи

Список реальных остатков после архитектурного аудита и рефакторинга
(theme/metrics миграция всех виджетов, Debug-система с уровнями/категориями,
тайминги подсистем, naming cleanup). Каждая задача — конкретная работа,
не stub. Код должен оставаться Lua 5.1 (MTA:SA), без внешних dependency.

## 1. Private-field access: `context._mapScaleY` в GridList

- `widgets/gridlist.lua` читает `self._context._mapScaleY` напрямую (RT bake
  для `cacheContent`). Это render-масштаб протекает в виджет через private field.
- Решение: expose масштаб через renderer (например `renderer.scaleY` уже
  читается в `render/pass.lua`) или публичный accessor на Runtime/UI,
  и мигрировать gridlist на него.
- Также `effects.lua:315` читает `ctx._mapScaleX/_mapScaleY` — тот же accessor.

## 2. Performance счётчики (Section 11 из ТЗ)

`Debug.perf()` готов (guarded, агрегированный flush), но не подключен в hot
paths. Осталось:

- style-resolution счётчик: инвалидация в `Widget:_applyStyleState` /
  `Theme.getMetric` (counter `styleResolutions`).
- resource cache hits/misses: инвалидация в `resources/manager.lua`
  (counter `resourceCacheHits` / `resourceCacheMisses`) — сейчас cache
  статистика не показывается через Debug.
- «dirty style / dirty input / dirty render» счётчики по инстансам: `stats`
  уже имеет layoutMs/renderMs/inputMs и layoutRuns/rebuilds/hitRebuilds,
  но dirty-flags по категориях (STYLE/INPUT/RENDER) не агрегированы.

## 3. Дублирование кода Edit/Memo (~90% undo/redo/caret/selection)

- `widgets/edit.lua` и `widgets/memo.lua` повторяют undo/redo chain,
  caret/selection clamp, `_moveCaret`, `_insert` почти идентично.
- Решение: вынести общую механику в shared module (`widgets/edit_base.lua`
  или `core/text_edit.lua`) и наследовать оба виджета. Keep public API
  (`caret`, `selectionFrom`, `submit`, `change`) unchanged.

## 4. Context god object — прямые записи dirty flags из виджетов

- `widgets/modal.lua`, `widgets/tabpanel.lua` (и combobox open) пишут
  `context.layoutDirty = true` / `context.interactiveDirty = true` /
  `context.renderDirty = true` напрямую.
- Решение: единый mutation путь — `Node:_invalidate` уже принимает
  категории; виджетам нужен public `invalidate()` через context (например
  `context.invalidate(DXUI.DIRTY.LAYOUT)`) вместо ручной записи полей.

## 5. Builder contract — полная унификация

- Widgets с parts/events имеют `_build`; simple widgets (button, label,
  panel, image, progressbar) — нет. Это допустимо, но boilerplate
  (`Widget:new` + `Builders.register` + `Builders.wireStates`) повторяется
  в каждом builder.
- Решение: единый builder helper (например `Builders.build(node, props,
  partDefs)`), который делает создание/normalize props/defaults/
  wireStates/register в одном месте. Каждый builder ≤100–200 строк.

## 6. Naming audit — глубокая pass по internal helpers

- `updateAnimations`, `updateHover`, `Layout.resolve`, `reposition` уже
  переименованы. Остались vague internal helpers:
  - `Builders.wireStates` — acceptable, но `_stateWired` flag повторяется.
  - `GridList:_rtUpdateScrollState` — осмысленное, но длинное.
  - `rowTextOf` / `isSeparator` в contextmenu vs `cellDisplay` в gridlist
    — один смысл (display text of an item) реализован разными способами.

## 7. Theme coverage audit — остальные magic constants

- GridList sort-mark triangle geometry (3/7/5/3/1) — fixed glyph shape,
  допустимо оставить hardcoded (algorithmic constant).
- Column separator width `1` — minor, можно вынести в metric.
- `rowHeight = 22` / `or 22` fallbacks в gridlist/combobox — redundant
  defensive fallbacks (theme props уже задают rowHeight), можно clean up.

## 8. Тесты для новых invariants (Section 21 из ТЗ)

Тесты external-only (не в repo). Добавить headless checks для:

1. Every public property mutation goes through one mutation layer.
2. User property cannot be silently overwritten by theme.
3. Destroyed node cannot stay in interaction/group registries.
4. Widget cannot require another widget's private implementation.
5. Theme metrics actually control component geometry.
6. State change resolves component state style centrally.
7. Context isolation works.
8. Debug levels can filter output.
9. Debug disabled path is cheap.
10. Design-to-screen and screen-to-design coordinates are inverse-consistent.

## Проверка

- Syntax gate: `node C:\Temp\dxui-tools\check-syntax.js <repo>` (luaparse
  0.3.1, Lua 5.1). Last run: 52 files, 0 errors.
- meta.xml: debug.lua добавлен в api section; script order = dependency
  order; init.lua MUST be last.
