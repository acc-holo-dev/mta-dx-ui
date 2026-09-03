# DXUI — полный backlog следующего обновления

> **Статус релиза v4-next (доделано):** W0: E1 ✅ · W1: E2, E3, A1–A9, A5, E4 ✅ · W2: B4, B1, B5, B3, B6, B2 ✅ · W3: C2, C1, C3 ✅ · W4: D1, D2, D3, D5, D6, D4 ✅ · W5: E6, E5 ✅. Полный отчёт — `dxui-release-report.md`. Остаток: E7–E12 (по спросу).

Единственный рабочий список задач. Базис: ваш список из 9 пунктов + `dxui-roadmap.md` (анализ и rationale; ссылки вида «1.2 / 3.5» ведут туда) + количественный аудит DGS (roadmap §6) + интернет-исследование (раздел E). Состав скорректирован по вашему решению: инструменты разработчика, adaptive quality и пул «вне плана» исключены.

Усилие: XS <30 строк · S 30–100 · M 100–400 · L 400+.

Покрытие вашего списка: п.1 → B1+B2 · п.2 → A1 · п.3 → A2+A3 · п.4 → A6 · п.5 → C2 · п.6 → C1 · п.7 → закрыт (§0) · п.8 → A5 · п.9 → A4.

## 0. Не в списке — уже есть в коде

Проверено в этом проходе; не «делать», а «не сломать» при рефакторингах:
- **Late allocation RT** (ваш п.7): RT создаётся при промахе пула в draw-фазе — effects.lua:219-240, backend_mta.lua:204-213.
- **Очистка флагов скрытых поддеревьев** (пункт G из раундов ревью): реализована — clearSubtreeFlags, pass.lua:62-70 (вызовы :82, :96, :129).
- Tooltip авто-показ на hover — tooltip.lua:73-86 (без задержки; задержка = A3).
- Focus-визуалы темой (states.focused) — widget.lua:52, 108-109; tween-движок — animation.lua; design-space stretch/fit — runtime.lua:132-156; live-темы с owner-guard — theme.lua:254-309.

## A. Быстрые победы (XS–S, «Обновление A»)

### A1 Rich text #RRGGBB в Label — XS ✅ (text.lua rich-флаг, backend colorCoded; ключ кэша `|r`)
Источник: ваш п.2 / 1.2. Что: `colorCoded=true` в backend drawText (backend_mta.lua:179-184) и в measurer dxGetTextSize (backend_mta.lua:230-239); spec-проп `Label.rich` (default false). Готово, когда: `rich=true` красит сегменты, wrap/ellipsis считают ширину без кодов; `rich=false` — байт-в-байт как сейчас; ключи кэшей не меняются (text.lua:63-65).

### A2 Событие hover-stay + стационарный hover — S ✅ (Dispatcher:update(now, hitRebuilt) из tick)
Источник: ваш п.3 / 1.3. Что: `hoverSince` на hover-start (dispatcher.lua:166-175); хранить lastX/lastY; `dispatcher:update(now)` из Runtime:tick (runtime.lua:173-227) → emit("hover-stay") один раз по истечении N; реализовать no-op `_updateNodeState` (dispatcher.lua:325-329): re-hit-test стационарного hover при mount (вызов уже есть — node.lua:654-655). Готово, когда: узел, смонтированный под неподвижным курсором, получает hover-start; stay срабатывает один раз; сброс на hover-end.

### A3 Задержка tooltip — XS ✅ (attach(target, anchor, {delay=N}))
Источник: ваш п.3 / 1.3. Зависит от A2. Что: `attach(target, anchor, { delay = N })` (tooltip.lua:73-86) — при delay>0 показ по hover-stay, иначе как сейчас. Готово, когда: tooltip с delay=400 появляется через 400 мс наведения и прячется при уходе.

### A4 Multi-click / doubleclick + cooldown — S ✅ (lastClick, click несёт count)
Источник: ваш п.9 / 1.9. Что: в mouseUp click-путь (dispatcher.lua:225-229) state `lastClick {node,t,count}`; click несёт count, при count==2 emit "doubleclick"; новые ключи Settings.defaults.doubleClickInterval=300, clickCooldown=0 (settings.lua:52-65). Готово, когда: двойной клик <300 мс даёт doubleclick, одиночный не меняется, cooldown давит спам.

### A5 Tab-навигация фокуса — S ✅ (cycleFocus по painter order, wrap-around)
Источник: ваш п.8 / 1.8. Что: перехват keyName=="tab" в Dispatcher:key до юзер-хендлеров (dispatcher.lua:270-287); обход = painter order по `_interactive` (hit_test.lua:47-62), фильтр focusable+enabled+reachable (dispatcher.lua:112-124), shift — назад. Готово, когда: Tab в Edit перескакивает на следующий focusable; под модалью цикл замкнут внутри неё.

### A6 ui:setEach / ui:animateEach — S ✅ (+ fix: AnimHandle:_finished → поздний onDone)
Источник: ваш п.4 / 1.4. Что: API в api/ui.lua; групповой handle: onDone после завершения ВСЕХ цепочек (счётчик поверх token.remaining — animation.lua:87-113). Готово, когда: `ui:animateEach({a,b,c},{opacity=0},200):onDone(fn)` зовёт fn ровно один раз.

### A7 Slider: step-кванта + клавиатура — XS ✅ (arrow_l/arrow_r — имена по wiki)
Источник: гэп 2.1. Что: spec `step` (квант в onSet), focusable=true, стрелки/home/end в key-хендлере по образцу edit.lua:311-332. Готово, когда: value квантуется step, стрелки двигают при фокусе.

### A8 Label: shadowOffsetX/Y — XS ✅
Источник: гэп 2.1. Что: пропы (default 1,1) + использование в теневом проходе (label.lua:69-75, сейчас хардкод). Готово, когда: смещение тени настраивается, дефолт не меняет вид.

### A9 Image: rotation / rotationCenter — S ✅ (hit остаётся AABB — задокументировано)
Источник: гэп 2.1. Что: spec-пропы, проброс в backend drawImage (сейчас шлёт 0,0,0 — backend_mta.lua:165-176), renderer-item расширить. Риск: hit-test остаётся прямоугольным — задокументировать. Flip нативно невозможен (только через шейдер). Готово, когда: повёрнутое изображение рендерится с корректным центром.

## B. Крупные виджеты (M–L, «Обновление B»)

### B1 GridList v2: колонки, сортировка, мультивыделение, клавиатура — M-L ✅ (сортировка in-place сохраняет выделение по идентичности)
Источник: заимствование 3.5. Что: columns = { {title, width, align, sortable} }, sort-API (клик по хедеру), selectedIndices + ctrl/shift (shift-механика — edit.lua:147-156), стрелочная навигация (DGS enableNavigation — gridlist.lua:4-48), item = {text | textKey, image?}. Culling не ломать (gridlist.lua:102-106). Ресайз колонок мышью не делаем (нет даже в DGS — только API ширины, gridlist.lua:1112, 1147). Готово, когда: колонки сортируются по клику, ctrl/shift-выделение работает, стрелки двигают выделение.

### B2 RT content-cache + инкрементальный скролл-блит — M-L ✅ (margin-window blit, НЕ пер-ряд redraw; RT w×2h; замер stats.draws — у пользователя)
Источник: ваш п.1 / 1.1 + изобретение 3.6. Что: opt-in `cacheContent` на контейнере: persistent RT (не из пула), инвалидация по dirty (items/scrollY/size), композит 1 drawImage; при скролле — сдвиг содержимого RT (dxDrawImageSection) + перерисовка только новых рядов. Порог включения решается по существующему счётчику stats.draws (runtime.lua:241; describe — api/diagnostics.lua:29-36) на целевом экране. Готово, когда: тяжёлый GridList в покое = 1 draw вместо K; скролл = blit + 1-2 ряда; без флага всё как было.

### B3 Memo (многострочный ввод) — M ✅ (новый виджет, meta.xml подключён)
Источник: заимствование 3.1. Что: Text.wrap (text.lua:111-170) + selection из Edit (edit.lua:91-156) + внутренний v/h-скролл по образцу _scrollX (edit.lua:219-235; DGS-прецедент h-скролла — memo.lua:1396-1397). Enter = новая строка, submit на Ctrl+Enter. Готово, когда: многострочный ввод с selection и скроллом работает.

### B4 Edit undo/redo — S-M ✅ (коалесценция правок 300 мс, лимит editHistoryLimit)
Источник: заимствование 3.3 (в DGS есть — client.lua:901-904). Что: ring-буфер правок на узле (insert/delete/replace + восстановление selection), ctrl+z/ctrl+y через key-хендлер (edit.lua:311-332), лимит истории (DGS: historyMaxRecords — edit.lua:1230-1231). Готово, когда: ctrl+z откатывает ввод, не конфликтует с selection.

### B5 Фоновые текстуры Button/Panel + per-state — S-M ✅ (bgTexture кэш на узле, fail не кэшируется — FAIL_TTL жив)
Источник: заимствование 3.7 (DGS button image ×3 состояния — styleSettings.txt:87-104). Что: spec-проп `texture` (+section), рисование до текста через renderer:image; theme states подхватят автоматически (widget.lua:126-129) — hover-текстура = states.hover.texture. Готово, когда: кнопка с фоном из темы, hover-подмена текстурой, дефолт без текстуры не меняется.

### B6 Edit autoComplete — M ✅ (Popup-сиблиинг, per-instance render override)
Источник: заимствование 3.8 (DGS meta.xml:517-520). Что: источник подсказок — callback/массив на узле; рендер поверх существующих Popup; up/down/enter в key-хендлере. Приоритет внутри B — ниже B1–B5. Готово, когда: подсказки фильтруются по вводу и вставляются по Enter.

## C. Взаимодействие (M, «Обновление C»)

### C1 Drag&Drop data-transfer — M ✅ (node.dragData — спека базового Node; _dropTargets rebuild с _interactive)
Источник: ваш п.6 / 1.6. Что: список drop-таргетов по образцу `_interactive` (rebuild на interactiveDirty — hit_test.lua:47-62, имена в isInteractive :23-27); drag-move → drag-over/drag-out; mouseUp при dragging → drop(data, source) либо drag-cancel; `_dragData` на нажатом узле; таргеты через reachable() (dispatcher.lua:112-124). Готово, когда: перенос строки на панель дропа доставляет данные; клики/модали не сломаны.

### C2 Пиксель-перфект hit для Image — M ✅ (бит-маска ≤256/сторона ≤8 КБ; любые размеры текстуры — стрид-сэмплинг, fail → rect)
Источник: ваш п.5 / 1.5. Что: opt-in `Image.pixelHit`; hook `_hitMask` в hitTestNode (hit_test.lua:65-83); бит-маска альфы из dxGetTexturePixels при первом запросе, кэш на текстуру рядом с textureCache (manager.lua:40-60), downsample ≤256, ≤8 КБ; fallback rect при превышении; учёт section; rotation не поддержан (документ). Готово, когда: прозрачные пиксели не ловят hover; без флага — rect.

### C3 Scroll inertia — S ✅ (velocity по последним дельтам, Anim на scrollY + onSet=_applyScroll)
Источник: изобретение 4.4. Что: скорость при отпускании → доводка через Anim на scrollY (animation.lua:116-124; scrollpanel.lua:76-102); Settings.defaults.scrollInertia=0 (off). Готово, когда: флик прокатывается и затухает; с off — как сейчас.

## D. Полировка и i18n (S–L, «Обновление D»)

### D1 Перевод шрифтов per-locale — XS-S ✅ ({text=, font="path:size"} через systemFont-резолв)
Источник: 2.3. Что: значение словаря `{text=..., font=...}` → applyTranslation пишет оба (widget.lua:245-256); шрифт через ui:font (кэш manager.lua:64-82).

### D2 Декларативные плюрализации — S ✅ (pluralFor: ru one/few/many, en one/other; без loadstring)
Источник: 2.3. Что: формы one/few/many/other + `pluralFor(locale, n)` (ru: n%10==1 и n%100~=11 → one; n%10 in 2..4 и не *10..19 → few; иначе many). БЕЗ loadstring (антипаттерн DGS — functions.lua:1090-1106). Готово, когда: `tr("items", 5)` → «5 элементов».

### D3 Перевод items в GridList/ComboBox — S ✅ (textKey-строки; binding через weak _textBindings → invalidate RENDER)
Источник: 2.3. Что: item = `{textKey="..."}`; rowText (gridlist.lua:13-15) рендерит через tr текущей locale; localeChange → invalidate.

### D4 Кастомный курсор per-type — M ✅ (defaults.cursor; текстуры у пользователя — §5)
Источник: заимствование 3.4 (DGS customCursor.lua:8-68, meta.xml:268-276; типы styleSettings.txt:20-78). Что: `Settings.cursor = {enabled, types={arrow={texture,hotspot}, text={...}}, scale, color}`; отрисовка в Runtime:draw после overlays (runtime.lua:245-256).

### D5 Switch (вариант Checkbox) — XS-S ✅ (variant/style="switch"; тумблер Anim switchT; пример в defaults)
Источник: заимствование 3.9. Что: тема-вариант checkbox (radius=full, тумблер в render) + transition-твин (widget.lua:131-138); пример в defaults.lua. Отдельный виджет — только если вариант не выразится.

### D6 Хоткеи окна — S-M ✅ (window.hotkeys; матчинг до focus-цепочки; false → fall-through)
Источник: изобретение 4.6. Что: window-scoped bindings: фокус внутри окна → map хоткеев; fallback в Dispatcher:key (dispatcher.lua:270-287). Опционально.

## E. Из интернет-исследования (MTA-трюки, паттерны, конкуренты)

Верифицировано по MTA wiki, клону DGS (file:line) и репозиториям-конкурентам. Скрытые нативные GUI-элементы (guiCreateEdit и т.п.) исключены по вашему ограничению — их тут нет ни в одном пункте.

### E1 Страж системного ввода — XS, bugfix-класс ✅ (systemInputBlocked() в init.lua)
Факт: onClientKey/onClientCharacter продолжают приходить при открытом чате/консоли (wiki OnClientKey/OnClientCharacter); DXUI их не фильтрует — 0 упоминаний isChatBoxInputActive/isConsoleActive/isMTAWindowActive/isMainMenuActive по source/client. Фокуснутый Edit ловит буквы, идущие в чат; Tab-навигация (A5) дёргается во время ввода в чат. Прецедент DGS: edit.lua:1383, memo.lua:1702 — `if isConsoleActive() or isMainMenuActive() or isChatBoxInputActive()`. Что: guard в input-glue init.lua (key :112-135, character :138-144); Settings.input.systemInputGuard=true (settings.lua:52-65). Готово, когда: при открытом чате/консоли Edit не получает символы; при закрытом — байт-в-байт как сейчас.

### E2 DXT-форматы, mipmaps, edge у ui:texture — S ✅ (DXUI.texture(path, opts) + UI:texture)
wiki DxCreateTexture: `dxCreateTexture(filepath [, textureFormat="argb", mipmaps=true, textureEdge="wrap"])`; dxt1 — в 8, dxt3/dxt5 — в 4 раза меньше видеопамяти, «can speed up drawing» (speedtests на wiki-странице); edge="clamp" убирает краевые артефакты; предконверт в .dds снимает лаги загрузки. Что: `ui:texture(path, {format, mipmaps, edge})`; опции в ключ кэша (manager.lua:40-60). Готово, когда: `{format="dxt5"}` даёт рабочую текстуру; дефолт байт-в-байт argb/mipmaps=true.

### E3 quality/bold в спеке шрифта — XS-S ✅ (DXUI.fontCacheKey/font(path,size,opts), "path:size:quality")
wiki DxCreateFont: `dxCreateFont(filepath [, size=9, bold=false, quality="proof"])`; quality: default/draft/proof/nonantialiased/antialiased/cleartype/cleartype_natural. DXUI сейчас quality не передаёт (дефолт MTA "proof" — сохранить). Что: спека "path:size:quality" и опция bold в ui:font (manager.lua:64-82), theme-префикс font: (theme.lua:128-137), defaults.font (manager.lua:89-107). Wiki-предупреждение «creation may fail» уже покрыто FAIL_TTL-кэшем. Готово, когда: "Roboto.ttf:12:cleartype" рендерится cleartype; bold-вариант из .ttf создаётся.

### E4 Blend-паттерн RT-групп: modulate_add/add — S ✅ (modulate_add внутри RT, add на композит; скрин-сверка — у пользователя §5)
wiki DxSetBlendMode (прямая рекомендация): «use modulate_add when drawing text to a render target, and add when drawing the render target to the screen». DGS применяет по всему ядру: client.lua:494-495 (`rndtgt and "modulate_add" or "blend"`), gridlist.lua:3430-3441, memo.lua:1852-1894, edit.lua:1475-1534, tabpanel.lua:700-714. DXUI: StateCache.setBlendMode есть (state.lua:26-30 — дедуп; backend_mta.lua:146-147), но вызывается только с BLEND_DEFAULT (state.lua:35) — RT-группы рисуют контент и композит в дефолтном blend → текст/полупрозрачность через RT теряют качество. Что: beginGroup → "modulate_add", композит RT на экран → "add", восстановление blend (сначала clipMode="rt" + B2; blur/mask-группы проверить отдельно). Готово, когда: текст в clipMode="rt"-контейнере неотличим от прямого рендера (скриншот до/после).

### E5 backdropBlur (frosted glass) — M ✅ (ленивый half-res source, обновление раз в кадр и только при видимом узле)
wiki DxUpdateScreenSource: `resampleNow=false` — берёт кадр N-1, дешевле, для эффектов рекомендован false. Прецедент DGS BlurBox: глобальный screen source с даунсемпл-фактором (blurBox.lua:64), blur-шейдер + blend "add" (:20-21, 48-50). DXUI: blur-шейдер уже есть (effects.lua:145-166). Что: опция `backdropBlur` у Window/Modal: source в разрешении /2-/4, обновление только пока виджет видим, инвалидация при перетаскивании, слой под окном. Готово, когда: за окном заблюренный мир; в покое нет лишнего dxUpdateScreenSource.

### E6 Градиенты — S-M ✅ (ОДИН шейдер + дедуп param-таблиц; gradient заменяет заливку у Panel/Button/Image; текст-градиент — вторая очередь)
Прецедент DGS plugin/Gradient: шейдер gradient.fx, colorFrom/colorTo/rotation, наложение и на текст (test.lua:1302-1305), 12 экспортов (meta.xml:918-928). DXUI: один общий шейдер по образцу rounded (один инстанс + дедуп параметров, effects.lua:29-61); проп `gradient={from, to, angle}` у Panel/Button/Image вместо/поверх bgColor. Текст-градиент — вторая очередь. Готово, когда: градиент из темы рендерится без шейдера на инстанс.

### E7 Frame-анимация Image — S
Спрайт-листы (спиннеры, анимированные иконки): texture + `frames={count, cols, rows, fps}` → рендер секцией кадра (section уже есть — image.lua:14); драйвер — overlay-паттерн (как каретка — edit.lua:257-270). Готово, когда: frames-иконка крутится; без frames — как раньше.

### E8 Toast-виджет — S-M
Авто-скрываемые уведомления: стек + позиция экрана, fade через Anim, LAYER.POPUP (node.lua:60). Ни у DGS, ни у uikit нет — дифференциатор. Готово, когда: `ui:toast("text",{duration=3000})` появляется, в стеке не перекрывает, исчезает с fade.

### E9 Value-scrubbing — S (опционально)
ImGui-паттерн: drag по числовому виджету меняет value с шагом. DXUI: поверх drag-механики (dispatcher.lua:182-196); применимо к Slider и числовым item'ам.

### E10 Tree view — M-L (кандидат по спросу)
Иерархический список (ImGui TreeNode-паттерн): инвентари, сервер-браузеры, настройки; механика GridList + indent + collapse.

### E11 NativeUI-циклеры, GTA V-стиль — M (кандидат по спросу)
Конкурент Allerek/MTASA-NativeUI («Recreation of GTA V's Native UI»): пункт меню с лево/право-циклом значений + баннер/описания. DXUI: composite ContextMenu/GridList + item-тип "cycler". Востребованный стиль на MTA-серверах.

### E12 ui:build(спек-дерево) — S
Декларативная фабрика `ui:build({type="window", props={...}, children={...}})` — рекурсия поверх factories + Widget.attachChildren (widget.lua:222); props валидируются как обычно (node.lua:345-371). Открывает внешний визуальный конструктор (аналог mta-sa-dx-ui-creator «DX UI Creator With AI Support») — DXUI спек-ориентирован, экспорт тривиален.

Приоритет внутри E (после релиза v4-next): E1–E6 ✅ выполнены; остаток E12 → E9 → E7 → E8 → E11 → E10 — по спросу.

Позиционирование (нашёл по GitHub API): заметный конкурент один — inceptionnet/mtasa-uikit (OOP-кит 2024 г., 2 компонента в доках, import-модульность, gitbook; их comparison-страница бьёт по DGS «spaghetti», Total DX Lib и TheNormalnij's DxGUI «outdated/no design system»). По их же осям DXUI впереди: design system есть (9 тем/23 токена/18 компонентов), спек-валидация — ни у кого из трёх. DMVMarcio/mta-sdx — минимальный кит, вне заимствований.

Источники: [DxCreateTexture](https://wiki.multitheftauto.com/wiki/DxCreateTexture) · [DxCreateFont](https://wiki.multitheftauto.com/wiki/DxCreateFont) · [DxSetBlendMode](https://wiki.multitheftauto.com/wiki/DxSetBlendMode) · [DxUpdateScreenSource](https://wiki.multitheftauto.com/wiki/DxUpdateScreenSource) · [IsChatBoxInputActive](https://wiki.multitheftauto.com/wiki/IsChatBoxInputActive) · [OnClientKey](https://wiki.multitheftauto.com/wiki/OnClientKey) · [OnClientCharacter](https://wiki.multitheftauto.com/wiki/OnClientCharacter) · [mtasa-uikit](https://github.com/inceptionnet/mtasa-uikit) · [uikit comparison](https://docs-uikit.gitbook.io/ui-kit/guide/comparison-with-other-ui-kits.md) · [MTASA-NativeUI](https://github.com/Allerek/MTASA-NativeUI) · [imgui](https://github.com/ocornut/imgui) · [mta-sdx](https://github.com/DMVMarcio/mta-sdx)

## Правила процесса

1. Перф-пункты (B2 прежде всего) — порог по существующему счётчику stats.draws (runtime.lua:241; api/diagnostics.lua:29-36), новых инструментов не вводим.
2. Проверка — внешними headless-скриптами (C:\Temp); тест-файлы в репо не добавляются (правило проекта).
3. Обратная совместимость: новые пропсы аддитивны, дефолты сохраняют текущий вид; всё через spec-валидацию (node.lua:345-371), никаких raw-полей в движковых путях.
4. Контракт zero-work idle не ломать: новые пер-фрейм-затраты только через overlay-паттерн (edit.lua:257-270) или opt-in флаги.
5. Порядок фаз: A → B → C → D → E; внутри фазы порядок свободный, кроме зависимостей (A3←A2).