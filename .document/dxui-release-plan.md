# DXUI — единый план релиза (исполняемый документ для ИИ-агента)

Источник: `.document/dxui-backlog.md` (пункты A1–A9, B1–B6, C1–C3, D1–D6, E1–E6 — обоснования и источники) + `dxui-roadmap.md` (анализ, аудит DGS). Этот файл — операционный: агент исполняет ЕГО, backlog открывает только при неоднозначности. ID задач = ID пунктов backlog.

## 0. Правила исполнения (агенту)

1. Волны W0→W6 строго последовательны. Внутри волны — порядок карточек сверху вниз. Отступления — только по зависимостям, указанным в карточке.
2. Одна карточка = одна задача = один мини-отчёт. После КАЖДОЙ карточки: синтаксис-чек (§7.1) всех изменённых .lua. После волны: сводка (§7.3).
3. Инварианты §1 обязательны в каждой задаче. Конфликт требований или недостаток данных → стоп и вопрос пользователю; API не выдумывать, сверяться с кодом по якорям §2.
4. git: правки без коммитов; `git diff --stat` в сводке волны. Коммит — только по явному указанию.
5. Тест-файлы в репо НЕ создавать (правило проекта). Проверка: headless (§7.1) + сценарии ручного смоука в MTA — формулировать в сводке волны для пользователя.
6. Существующие файлы править точечно (edit), новые — создавать (write). Полная перезапись существующего файла без запроса запрещена.

## 1. Инварианты (нарушать нельзя ни в одной задаче)

- **Spec-валидация**: каждый новый пропс описан в spec-таблице виджета `{default, type, min?, max?, validate?, transform?, invalidates?, onSet?}`; записи мимо спека запрещены (node.lua:345-371).
- **Обратная совместимость**: новые пропсы аддитивны; при дефолтных значениях поведение и вид байт-в-байт как до релиза.
- **Zero-work idle**: новых пер-фрейм-затрат нет, кроме overlay-паттерна (образец — каретка, edit.lua:257-270) или opt-in флагов/пропсов.
- **Запрещено**: `loadstring`, скрытые нативные GUI-элементы (guiCreateEdit и любые другие guiCreate*), новые внешние зависимости, user-code хуки внутри рендер-лупа.
- **Настройки**: новые ключи — только через defaults-блок (settings.lua:52-65), чтение через `DXUI.Settings.defaults.*`; вне MTA — безопасные дефолты (образец: scrollpanel.lua:53-54).
- **Инвалидация**: любая правка, влияющая на рендер/хит, ставит нужный dirty-флаг (категории DIRTY → 4 фрейм-флага, pass.lua:62-70); «тихие» записи без инвалидации запрещены.
- **Рендер-луп**: порядок тика не менять (runtime.lua:173-227); изменения бэкенда — минимальные, через StateCache (state.lua), не мимо него.

## 2. Карта архитектуры (якоря для навигации)

- Node/спеки: node.lua:345-371 (валидация) · node.lua:59-60 (LAYER: BASE/OVERLAY/MODAL/POPUP/TOOLTIP/DEBUG) · node.lua:654-655 (mount → _updateNodeState).
- Widget: widget.lua:126-129 (тема, per-state пропы) · :131-138 (transitions) · :222 (attachChildren) · :245-256 (applyTranslation).
- Кадр: runtime.lua:30-34 (clock) · :79-83 (stats, счётчик draws) · :173-227 (tick: anim → layout → pass rebuild → hit rebuild → draw) · :245-256 (overlays) · :241 (stats.draws).
- Хит: hit_test.lua:23-27 (имена interactive-событий) · :47-62 (painter-order rebuild) · :65-83 (hitTestNode — точка входа pixel-hit) · :91-108 (topAt).
- Ввод: init.lua:112-135 (onClientKey-glue; «tab» приходит сюда) · :138-144 (onClientCharacter) · dispatcher.lua:112-124 (reachable) · :166-175 (hover) · :182-196 (drag→pressed) · :225-229 (click) · :270-287 (key→focus) · :325-329 (_updateNodeState — no-op).
- Текст: text.lua:63-65 (ключи кэша, 2 поколения) · :101-106, :148-154 (wrap) · :172-192 (ellipsis) · :226-230 (charX).
- Бэкенд: backend_mta.lua:146-148 (RenderState.setBlendMode) · :165-176 (drawImage) · :179-184 (drawText, 15-й аргумент colorCoded) · :205-219 (beginGroup/endGroup RT-групп) · :230-239 (measurer) · state.lua:26-35 (setBlendMode-дедуп, BLEND_DEFAULT) · state.lua:52-59 (драйвер RT-групп).
- Эффекты/кэши: effects.lua:29-61 (rounded — один шейдер на всех, дедуп параметров) · :145-166 (blur) · :219-240 (RT-пул, RT_POOL_CAP=64) · manager.lua:40-60 (texture cache) · :64-82 (DXUI.font + FAIL_TTL) · :72-73 (dxCreateFont(name, size) — quality/bold НЕ передаются) · :89-107 (systemFont, спека "path:size" :97).
- Темы: theme.lua:128 (font:-префикс `^font:([^:]+):(%d+)$`) · :254-309 (live-темы, owner-guard).
- Анимации: animation.lua:87-113 (token.remaining) · :116-124 (animate) · :27, :88 (defaults.easing/duration).
- Виджеты: edit.lua:91-156 (selection; shift-якорь :147-156) · :219-235 (_scrollX) · :257-270 (overlay-каретка) · :311-332 (key-handler) · gridlist.lua:13-15 (rowText), :102-106 (culling) · scrollpanel.lua:76-102 (scrollBy/_applyScroll) · slider.lua:13-22 · label.lua:69-75 (тень) · image.lua:14 (texture+section) · tooltip.lua:73-86 (attach) · popup.lua, contextmenu.lua, window.lua, modal.lua — существуют (widgets/).
- API: api/ui.lua · api/diagnostics.lua:29-36 (describe → stats) · api/exports.lua.

## 3. Состав и порядок релиза

Ядро: 29 задач + финализация. Соответствие приоритетам пользователя: п.1→B1+B2 · п.2→A1 · п.3→A2+A3 · п.4→A6 · п.5→C2 · п.6→C1 · п.7→закрыт ранее · п.8→A5 · п.9→A4. Опциональный хвост E7–E12 (§6) в релиз НЕ входит без явного указания.

| Волна | Задачи (порядок исполнения) | Ключевые зависимости |
|---|---|---|
| W0 hotfix | E1 | — |
| W1 быстрые победы | E2, E3, A1, A2, A3, A4, A6, A7, A8, A9, A5, E4 | A3←A2; E4 — последним (виз-проверка) |
| W2 крупные виджеты | B4, B1, B5, B3, B6, B2 | B2 после B1 и E4 |
| W3 взаимодействие | C2, C1, C3 | — |
| W4 i18n + полировка | D1, D2, D3, D5, D6, D4 | — |
| W5 эффекты | E6, E5 | после W2 |
| W6 финализация | аудит + отчёт | после всех |

Усилие: XS <30 · S 30–100 · M 100–400 · L 400+ строк. Суммарно ядро ≈ 2×S-волна + 6×M + 2×L.

## 4. Карточки задач

### W0-1 · E1 — страж системного ввода · XS
Файлы: init.lua:112-144 · settings.lua:52-65
Реализация: (1) в key-glue (:112-135) и character (:138-144) первым делом страж: при `DXUI.Settings.defaults.systemInputGuard` и (`isChatBoxInputActive()` или `isConsoleActive()` или `isMTAWindowActive()`) → return; функции натива брать локальными при загрузке модуля с no-MTA-заглушкой `function() return false end`. (2) Ключ `systemInputGuard = true` в defaults.
Готово, когда: при открытом чате/консоли Edit не получает символы, key-пути молчат; при закрытом — байт-в-байт; флаг=false снимает фильтр.
Проверка: §7.1; смоук — фокус в Edit → открыть чат → печать → Edit не меняется.

### W1-1 · E2 — ui:texture(path, opts) {format, mipmaps, edge} · S
Файлы: manager.lua:40-60 (кэш текстур) · api/ui.lua (проксирование ui:texture)
Реализация: (1) opts: format ∈ {argb, dxt1, dxt3, dxt5} (default argb), mipmaps=true, edge ∈ {wrap, clamp} — валидация значений. (2) Ключ кэша: при дефолтных opts — прежний ключ `path` (нулевое влияние на существующие кэши); при не-дефолтных — суффикс `|fmt|mip|edge`. (3) dxCreateTexture(path, format, mipmaps, edge). (4) failAt-механика без изменений.
Готово, когда: `{format="dxt5"}` рисуется; без opts — прежний путь; dxt5 даёт меньшую видеопамять (dxGetStatus).
Проверка: §7.1; смоук — одна png в argb и dxt5, визуально идентичны.

### W1-2 · E3 — quality/bold в спеке шрифтов · XS-S
Файлы: manager.lua:64-82 (DXUI.font), :72-73 (создание), :97 (спека "path:size") · theme.lua:128 (font:-префикс) · settings.lua:52-65
Реализация: (1) DXUI.font(name, size, opts): opts {bold=false, quality=nil}; при заданных — pcall(dxCreateFont, name, size, bold, quality); качество не задан → вызов как сейчас (:72-73), дефолт MTA "proof" сохраняется. (2) Ключ кэша (:65) расширяется только при не-дефолтных opts. (3) Спека "path:size:quality": расширить матчеры :97 (`^(.*):(%d+):(%a+)$` с fallback на 2-сегментный) и theme.lua:128. (4) Валидация quality ∈ {default, draft, proof, nonantialiased, antialiased, cleartype, cleartype_natural}.
Готово, когда: `font:Roboto.ttf:12:cleartype` даёт cleartype-рендер; спеки без quality работают как раньше.
Проверка: §7.1; смоук — один текст proof vs cleartype.

### W1-3 · A1 — rich text #RRGGBB в Label · XS
Файлы: backend_mta.lua:179-184 (drawText), :230-239 (measurer) · text.lua:63-65, :101-106, :148-154, :172-192, :226-230 · widgets/label.lua (spec)
Реализация: (1) spec-проп `rich` (default false, invalidates RENDER) у Label. (2) backend drawText: 15-й аргумент colorCoded ← rich; measurer — colorCoded=rich. (3) Кэш: при rich=true маркер в ключ (text.lua:63-65); ключи rich=false не меняются. (4) wrap/ellipsis/charX: измерения по strip-версии (код "#RRGGBB" не считается) — text.lua:101-106, :148-154, :172-192, :226-230.
Готово, когда: rich=true красит сегменты, ширины/ellipsis считаются без кодов; rich=false байт-в-байт.
Проверка: §7.1; смоук — rich + wrap + ellipsis.

### W1-4 · A2 — hover-stay + стационарный hover · S
Файлы: dispatcher.lua:166-175 · runtime.lua:173-227 · settings.lua:52-65
Реализация: (1) На hover-start: `_hoverSince`, `_hoverX/_hoverY` (:166-175). (2) Dispatcher-update из tick: при hover-узле, неподвижном курсоре и (now - since ≥ defaults.hoverStayDelay=400) и ещё не сработавшем — emit("hover-stay") один раз. (3) Реализовать `_updateNodeState` (:325-329): re-hit-test стационарного hover при mount (вызов уже есть — node.lua:654-655). (4) Сброс на hover-end.
Готово, когда: узел, смонтированный под курсором, получает hover-start; stay один раз по задержке; уход — hover-end.
Проверка: §7.1; смоук — монтирование под курсором.

### W1-5 · A3 — tooltip delay · XS — ЗАВИСИТ ОТ W1-4
Файлы: tooltip.lua:73-86
Реализация: attach(target, anchor, opts): opts.delay (default 0 = немедленно, как сейчас); delay>0 — показ по hover-stay цели.
Готово, когда: delay=400 → tooltip через 400 мс после наведения; 0 — как раньше.
Проверка: §7.1; смоук.

### W1-6 · A4 — multi-click + cooldown · S
Файлы: dispatcher.lua:225-229 · settings.lua:52-65
Реализация: (1) state `_lastClick {node, t, count}`. (2) В click-пути: тот же узел и Δt < defaults.doubleClickInterval=300 → count+1, иначе count=1; click несёт count; при count==2 — emit "doubleclick". (3) defaults.clickCooldown=0; при >0 подавлять клики чаще порога. (4) Оба ключа в defaults.
Готово, когда: двойной клик <300 мс даёт doubleclick; одиночный не меняется; cooldown при 0 выключен.
Проверка: §7.1; смоук — bind("doubleclick") + bind("click").

### W1-7 · A6 — ui:setEach / ui:animateEach · S
Файлы: api/ui.lua · animation.lua:87-113, :116-124
Реализация: (1) ui:setEach(nodes, props) — set на каждом узле (спеки сработают у каждого). (2) ui:animateEach(nodes, props, duration, easing) — Anim на каждом (animation.lua:116-124), возвращает group-handle: onDone(fn) срабатывает один раз, когда завершены ВСЕ (счётчик поверх token.remaining — :87-113).
Готово, когда: `ui:animateEach({a,b,c},{opacity=0},200):onDone(fn)` зовёт fn ровно один раз.
Проверка: §7.1; смоук — три узла фейдятся, onDone в конце.

### W1-8 · A7 — Slider: step + клавиатура · XS
Файлы: widgets/slider.lua:13-22
Реализация: (1) spec: step (number, default nil, transform-квантование к кратному в пределах min/max), focusable=true. (2) key-handler по образцу edit.lua:311-332: left/right=±step (или 1), home/end=min/max — при фокусе.
Готово, когда: value квантуется step; стрелки работают.
Проверка: §7.1; смоук.

### W1-9 · A8 — Label: shadowOffsetX/Y · XS
Файлы: widgets/label.lua:69-75 + spec
Реализация: spec shadowOffsetX/Y (default 1 — текущий хардкод), invalidates RENDER; использование в теневом проходе (:69-75).
Готово, когда: смещение настраивается, при дефолтах вид прежний.
Проверка: §7.1; смоук.

### W1-10 · A9 — Image: rotation / rotationCenter · S
Файлы: widgets/image.lua (spec+render) · backend_mta.lua:165-176 (drawImage)
Реализация: (1) spec: rotation=0, rotationCenterX/Y (в px, default = центр узла на момент рендера). (2) Проброс в drawItem → backend drawImage (сейчас шлёт нули — :165-176). (3) Комментарий в спеку: hit-test остаётся по AABB (поворот не учитывается).
Готово, когда: rotation=45 рендерится вокруг заданного центра; без rotation — байт-в-байт.
Проверка: §7.1; смоук.

### W1-11 · A5 — Tab-навигация фокуса · S
Файлы: dispatcher.lua:270-287 · hit_test.lua:47-62
Реализация: (1) В Dispatcher:key ПЕРЕД юзер-хендлерами: keyName=="tab" → перехват. (2) Кандидаты: painter order (:47-62) ∩ focusable+enabled+reachable (:112-124); shift — назад; wrap по кругу. (3) Есть focused → следующий после него; нет → первый. (4) Приоритет: страж E1 → Tab (A5) → window-hotkeys (D6) → юзер-хендлеры.
Готово, когда: Tab в Edit перескакивает на следующий focusable, цикл замкнут, юзер-хендлеры "tab" при перехвате не получают.
Проверка: §7.1; смоук — 2 Edit + Slider, Tab по кругу.

### W1-12 · E4 — blend-паттерн RT-групп (modulate_add/add) · S
Файлы: backend_mta.lua:205-219 · state.lua:26-35 (кэш режимов), :52-59 (драйвер групп)
Реализация: (1) beginGroup: контент RT рисуется с "modulate_add" (wiki DxSetBlendMode — прямая рекомендация). (2) endGroup: композит RT на экран — "add"; восстановление "blend". (3) Все переключения через StateCache.setBlendMode (state.lua:26-30), не мимо — иначе сломается дедуп currentBlendMode; сброс к BLEND_DEFAULT уже есть (:35). (4) blur/mask-группы — проверить визуально и решить отдельно (стоп-точка §5).
Готово, когда: текст в clipMode="rt" неотличим от прямого рендера (скриншот до/после — §5); кадр без RT не меняет поведения.
Проверка: §7.1; скриншот-сравнение пользователем.

### W2-1 · B4 — Edit undo/redo · S-M
Файлы: widgets/edit.lua:311-332 (key), :91-156 (selection)
Реализация: (1) History-ring на узле: {text, selection} до/после; лимит defaults.editHistoryLimit=64. (2) Запись правок — обернуть существующие мутации текста (вставка/удаление/replace); коалесцировать соседние правки <300 мс в одну. (3) ctrl+z / ctrl+y в key-handler (:311-332): применить инверсию + восстановить selection. (4) История пишется только на вводе пользователя, не на программной set.
Готово, когда: ctrl+z откатывает ввод, selection восстанавливается, ctrl/y возвращает; лимит соблюдён.
Проверка: §7.1; смоук — печать, undo×3, redo×2.

### W2-2 · B1 — GridList v2 · M-L
Файлы: widgets/gridlist.lua (весь), :13-15 (rowText), :102-106 (culling) · scrollpanel.lua:76-102 (скролл)
Реализация: (1) columns = {{key, title, width, align, sortable}}; row = {cells={…}}; сумма ширин > клиентской → горизонтальный скролл (образец :76-102). (2) Сортировка: API + клик по заголовку (asc/desc); culling (:102-106) не трогать. (3) Мультивыделение: selectedIndices; ctrl — toggle, shift — диапазон от якоря (образец shift-якоря — edit.lua:147-156); API get/setSelectedIndices. (4) Клавиатура: стрелки, home/end, ctrl+A (при multi). (5) columns=nil → одноколоночный режим байт-в-байт как сейчас (items — строки). Ресайз колонок мышью НЕ делать (нет даже в DGS).
Готово, когда: 3 колонки сортируются кликом; ctrl/shift-выделение; стрелки; одноколоночный список работает как раньше.
Проверка: §7.1; смоук — 3 колонки × 200 рядов.

### W2-3 · B5 — фоновые текстуры Button/Panel · S-M
Файлы: widgets/button.lua, panel.lua (spec+render) · manager.lua:40-60 · theme (states)
Реализация: (1) spec `texture` (путь | handle | nil) + `textureSection`; рисуется до текста существующим image-item. (2) Тема: states.texture подхватится автоматически (widget.lua:126-129) — hover-текстура = states.hover.texture. (3) Fallback: незагрузившаяся текстура (FAIL_TTL) → только bgColor + DXUI._warn.
Готово, когда: кнопка с фоном из темы, hover подменяет текстуру; без texture — прежний вид.
Проверка: §7.1; смоук. Ассеты png/dds — у пользователя (§5).

### W2-4 · B3 — Memo · M
Файлы: widgets/memo.lua (новый) · text.lua:111-170 (wrap) · edit.lua:91-156, :219-235, :311-332
Реализация: (1) Новый виджет на Edit-механике: многострочный буфер, wrap (:111-170). (2) Selection — перенос из edit.lua:91-156. (3) v-скролл (образец _scrollX — :219-235) + h-скролл при выключенном wrap. (4) Enter = \n; Ctrl+Enter = submit; key-handler расширяется (:311-332). (5) Регистрация: factories/builders + meta.xml-скрипты (как у edit.lua).
Готово, когда: многострочный ввод, выделение, скролл, Ctrl+Enter submit.
Проверка: §7.1; смоук.

### W2-5 · B6 — Edit autoComplete · M
Файлы: widgets/edit.lua:311-332 · widgets/popup.lua (рендер поверх) · node.lua:59-60 (LAYER.POPUP)
Реализация: (1) spec: autoComplete = callback(list, prefix) → массив | nil. (2) При вводе и >0 совпадений — popup-список под Edit в LAYER.POPUP, до 8 пунктов. (3) up/down/enter/escape/Tab — в key-handler Edit приоритетно при открытом popup. (4) Вставка — replace префикса.
Готово, когда: подсказки фильтруются, вставляются по Enter/Tab, escape закрывает.
Проверка: §7.1; смоук.

### W2-6 · B2 — RT content-cache + инкрементальный скролл-блит · M-L — ПОСЛЕ B1, ИСПОЛЬЗУЕТ E4
Файлы: effects.lua:219-240 (пул — не трогать) · backend_mta.lua:205-219 · widgets/gridlist.lua
Реализация: (1) Опт-ин `cacheContent` у контейнера: persistent RT вне пула (свой аллокатор; RT_POOL_CAP не менять), размер = клиентский rect, пересоздание при resize. (2) Полная перерисовка при dirty (items/scrollY/size); без dirty — композит 1 drawImage с blend из E4. (3) Скролл: dxDrawImageSection-сдвиг + перерисовка только новых рядов. (4) Сброс при visibility=false; инвалидация — те же dirty-категории.
Готово, когда: GridList 200 рядов в покое ≈ 1 draw (stats.draws, §7.2); скролл = блит + 1-2 ряда; без флага — прежний путь.
Проверка: §7.1; замер до/после в отчёт (§7.2, §5).

### W3-1 · C2 — пиксель-перфект hit Image · M
Файлы: hit_test.lua:65-83 · manager.lua:40-60 (соседний кэш масок)
Реализация: (1) spec Image.pixelHit (default false). (2) Hook в hitTestNode (:65-83): бит-маска альфы из dxGetTexturePixels при первом запросе; кэш масок рядом с textureCache. (3) Downsample ≤256 по большей стороне; больше — fallback rect + warn; учёт section; rotation не поддержан (документ). (4) Память ≤8 КБ/текстура.
Готово, когда: прозрачные пиксели не ловят hover/click; без флага — rect; маска не пересоздаётся.
Проверка: §7.1; смоук — круглая иконка, клики только по кругу.

### W3-2 · C1 — Drag&Drop data-transfer · M
Файлы: dispatcher.lua:182-196, :225-229 · hit_test.lua:23-27, :47-62, :91-108
Реализация: (1) Регистрация drop-таргетов — список по образцу _interactive (rebuild при interactiveDirty :47-62; имена :23-27). (2) drag-move при dragData источника: topAt по таргетам (:91-108) + reachable (:112-124) → drag-over/drag-out; mouseUp → drop(data, source) | drag-cancel. (3) Клик-путь (:225-229) не ломать: drop без движения < 4 px = обычный click.
Готово, когда: перенос строки GridList→Panel доставляет данные; клики работают; модаль не пробивается.
Проверка: §7.1; смоук — GridList→GridList, GridList→Panel.

### W3-3 · C3 — scroll inertia · S
Файлы: scrollpanel.lua:76-102 · animation.lua:116-124 · settings.lua:52-65
Реализация: (1) Скорость по последним дельтам при отпускании. (2) Доводка Anim на scrollY с затуханием (:116-124); прерывание новым вводом. (3) defaults.scrollInertia=0 (выключено).
Готово, когда: флик прокатывается и затухает; при 0 — прежнее поведение.
Проверка: §7.1; смоук.

### W4-1 · D1 — шрифты per-locale · XS-S
Файлы: widget.lua:245-256 (applyTranslation) · manager.lua:64-82
Реализация: значение словаря {text="…", font="path:size"} — applyTranslation пишет оба; строка-значение = как сейчас.
Готово, когда: ключ с font рендерится шрифтом локали; смена локали подхватывает.
Проверка: §7.1; смоук ru/en.

### W4-2 · D2 — декларативные плюрализации · S
Файлы: api/ui.lua (tr) · settings.lua:52-65
Реализация: (1) Словарь: ключ = {one, few, many, other} | строка. (2) pluralFor(locale, n): ru — n%10==1 и n%100≠11 → one; n%10∈2..4 и (n%100<10 или n%100≥20) → few; иначе many; en — one/other. Без loadstring. (3) tr(key, n): форма + подстановка числа.
Готово, когда: tr("items",5) → «5 элементов»; tr("items",21) → «21 элемент»; tr("items",1) → «1 элемент».
Проверка: §7.1; числовые кейсы (0,1,2,5,11,21,101,111) перечислить в отчёте.

### W4-3 · D3 — перевод items · S
Файлы: gridlist.lua:13-15 (rowText) · combobox.lua (items) · widget.lua:245-256
Реализация: (1) item = {textKey="…"} — rowText рендерит через tr текущей локали; ComboBox — то же. (2) Событие смены локали → invalidate RENDER списков.
Готово, когда: items с textKey переключаются по локали на лету.
Проверка: §7.1; смоук — смена локали.

### W4-4 · D5 — Switch · XS-S
Файлы: widgets/checkbox.lua (render) · style defaults (тема)
Реализация: вариант темы `switch` для checkbox: radius full, тумблер, переход позиции через transitions (widget.lua:131-138); пример в defaults. Отдельный класс не заводить, если хватает варианта.
Готово, когда: `variant="switch"` рисует тумблер с анимацией; обычный checkbox не меняется.
Проверка: §7.1; смоук.

### W4-5 · D6 — хоткеи окна · S-M
Файлы: dispatcher.lua:270-287 · widgets/window.lua
Реализация: (1) window.hotkeys = {[keyName]=handler} — активны, пока focused ∈ поддерево окна. (2) Матчинг в Dispatcher:key после стража E1 и Tab A5, до юзер-хендлеров. (3) Дефолтов не добавлять (в т.ч. Escape) — только пользовательские.
Готово, когда: хоткеи работают при фокусе в окне, молчат вне, не конфликтуют с Edit.
Проверка: §7.1; смоук.

### W4-6 · D4 — кастомный курсор per-type · M
Файлы: runtime.lua:245-256 (overlays) · settings.lua:52-65 · manager.lua:40-60
Реализация: (1) defaults.cursor = {enabled=false, scale=1, color, types={arrow={texture,hotspot={x,y}}, text={…}, hand={…}}}. (2) Отрисовка после overlays (:245-256): тип по hover-узлу (текстовые → "text", кликабельные → "hand", иначе "arrow"). (3) enabled=false — ноль затрат. (4) Встроенных ассетов не поставлять; без текстуры → системный курсор.
Готово, когда: enabled=true рисует per-type; false — прежний системный.
Проверка: §7.1; смоук. Ассеты — у пользователя (§5).

### W5-1 · E6 — градиенты · S-M
Файлы: effects.lua:29-61 (паттерн «один шейдер») · новый .fx + meta.xml `<file>` · panel.lua, button.lua, image.lua
Реализация: (1) Шейдер линейного градиента {from, to, angle} — один инстанс, кэш-дедуп по параметрам (образец rounded :29-61). (2) spec `gradient` у Panel/Button/Image: задан → заменяет заливку bgColor. (3) states.gradient — автоматически (widget.lua:126-129).
Готово, когда: градиент из темы рендерится; без gradient — прежний вид; шейдер один на все узлы.
Проверка: §7.1; смоук — 3 панели, углы 0/45/90.

### W5-2 · E5 — backdropBlur (frosted glass) · M
Файлы: effects.lua:145-166 (blur) · widgets/window.lua, modal.lua · manager.lua (screen source)
Реализация: (1) spec Window/Modal: backdropBlur=false. (2) Ленивый глобальный screen source: dxCreateScreenSource(sW/2, sH/2); dxUpdateScreenSource(src, false) — только в кадрах, где есть видимый backdropBlur-узел (кадр N-1, дешевле). (3) Blur-шейдер (:145-166) на rect окна → слой перед контентом окна. (4) Все такие окна скрыты → источник не обновляется (zero-work).
Готово, когда: за окном заблюренный мир; без узлов — ноль затрат.
Проверка: §7.1; смоук.

### W6 · финализация релиза
1. Полный синтаксис-проход по source/client (§7.1).
2. Греп-аудит инвариантов: `loadstring` → пусто; `guiCreate` → пусто; новые `DXUI.` raw-поля вне спек — просмотр по diff.
3. `git diff --stat` — сводка; итоговый отчёт релиза: задачи W0–W5, изменённые файлы, сценарии смоука, известные ограничения (hit при rotation, dxt-форматы и .dds-предконверт, качество шрифтов).
4. Обновить `.document/dxui-backlog.md`: выполненные пункты отметить, сдвинуть приоритеты остатка.

## 5. Стоп-точки (вопросы пользователю — не блокируют реализацию, кроме отмеченного)

1. **W1-12 (E4)**: скриншоты clipMode="rt" до/после — пользователь сверяет визуально. При спорном результате blur/mask-группы откатить на "blend".
2. **W2-6 (B2)**: замер stats.draws на тяжёлой сцене у пользователя (§7.2) — для отчёта до/после.
3. **W2-3 (B5), W4-6 (D4)**: png/dds-ассеты (кнопки, курсоры) — пользователь; без них — fallback, задачи выполняются.
4. **W4-2 (D2)**: ru/en в ядре; дополнительные локали с иными правилами плюрализма — additive по запросу.

## 6. Опциональный хвост — ТОЛЬКО по явному указанию пользователя

Не входит в релиз, пока не назван явно. Карточки в backlog §E. Порядок по возрастанию усилия: E12 (ui:build, S) → E9 (scrubbing, S) → E7 (frame-анимация, S) → E8 (toast, S-M) → E11 (NativeUI-циклеры, M) → E10 (tree view, M-L).

## 7. Процедуры

### 7.1 Синтаксис-чек (после каждой задачи, на каждом изменённом .lua)
Команда проверена и работает (pwsh):
```
& "D:\Program\AI\DSH Desktop\resources\app\node_modules\node\bin\node.exe" -e "const lp=require('C:/Temp/luaparse-check/node_modules/luaparse');const fs=require('fs');lp.parse(fs.readFileSync(process.argv[1],'utf8'),{luaVersion:'5.1'});console.log('SYNTAX OK')" "<файл.lua>"
```

### 7.2 Замер stats.draws (для B2 и общего контроля)
В MTA (F8-консоль): вывести stats через describe (api/diagnostics.lua:29-36). Сценарий: GridList ~200 рядов — cacheContent off → число; on → число; обе цифры в отчёт W2.

### 7.3 Сводка после волны
- задачи: ID + статус (готово/отклонено/перенесено) + причины;
- файлы: список + `git diff --stat`;
- сценарии ручного смоука для пользователя (по одному на задачу);
- отклонения от плана и их обоснование.