# DXUI: заимствования из DGS и нативные фичи — follow-up отчёт

Продолжение `dgs-vs-dxui-review.md`. Три задачи: (1) техническая проверка вашего списка из 9 пунктов против реального кода DXUI — где «уже есть», где поддерживаю, где уточнение; (2) закрытие пропущенных осей сравнения — количество свойств на виджет, качество/количество настроек тем, смена языка; (3) новые заимствования из DGS и изобретения на базе архитектуры DXUI. Каждый факт — file:line, проверено по коду в этом проходе. Метод подсчёта свойств DXUI — grep по `default =` в spec-таблицах (node.lua:80-149, widget.lua:36-49, widgets/*.lua); многострочные декларации могут дать ±1.

## 0. Сводка вердиктов по вашему списку

| # | Пункт | Вердикт | Усилие | Крючок в коде |
|---|-------|---------|--------|----------------|
| 1 | RT-кэш контента | Поддерживаю с уточнением: GridList уже куллит видимые строки, RT нужен тяжёлым рядам; бонус — инкрементальный скролл-блит (нет ни у DGS, ни у DXUI) | M | render/pass.lua, render/effects.lua, widgets/gridlist.lua |
| 2 | Rich text #RRGGBB | Поддерживаю — почти готово: wrap уже переносит коды между строк, не хватает `colorCoded` в draw и measure | XS | backend_mta.lua:179-184, 230-239; text/text.lua:101-106 |
| 3 | onDgsMouseStay-аналог | Поддерживаю; tooltip уже авто-показывается, нет только задержки | S | input/dispatcher.lua:158-197, 325-329; widgets/tooltip.lua:73-86 |
| 4 | ui:each | Поддерживаю как эргономику (перф-смысла нет: dirty уже коалесится); ценность — animateEach с групповым onDone | S | api/ui.lua; animation/animation.lua:87-113 |
| 5 | Пиксель-перфект hit для Image | Поддерживаю, opt-in: бит-маска альфы, кэш на текстуру, без loadstring (в отличие от DGS detectarea) | M | input/hit_test.lua:65-83; resources/manager.lua:40-60 |
| 6 | Drag&drop data-transfer | Поддерживаю: сейчас drag идёт ТОЛЬКО на нажатый узел, drop-таргетов нет | M | input/dispatcher.lua:182-196 |
| 7 | Late allocation RT | **Уже реализовано** — RT создаётся при первом рендере группы из пула, не при установке эффекта | 0 | backend_mta.lua:204-213; render/effects.lua:215-250 |
| 8 | Tab-навигация | Поддерживаю: порядок обхода бесплатен (painter order уже есть) | S | input/dispatcher.lua:270-287; input/hit_test.lua:47-62 |
| 9 | Multi-click + cooldown | Поддерживаю: пара строк в click-путь + 2 settings-ключа | S | input/dispatcher.lua:216-233; source/settings.lua:52-65 |

---

## 1. Детальный разбор

### 1.1 RT-кэш контента (ваш п.1)

Факты по текущему коду:
- GridList рендерит **только видимые строки** (gridlist.lua:102-106 — first/last от scroll-смещения): ~2 draws на строку (rect + text, :111-113) + thumb (:116-119). Стоимость кадра ограничена вьюпортом, а не длиной списка.
- Render list кэшируется (runtime.lua:204-209), но MTA — immediate mode: каждый кадр список пере-испускается в dx. RT-кэш превращает K draws в 1 drawImage.
- Edit в RT-кэше **не нуждается**: он уже O(1) в кадре — measure/charX идут через двухпоколенческий кэш (text.lua:63-80, 226-230), в кадре 1 rect + 1 text + каретка-оверлей (edit.lua:206-255, 259-270).

Что даёт RT: выигрыш проявляется при (а) тяжёлых строках — иконки, >2 колонки, кастом-рендер; (б) десятках видимых строк. Для текущего плоского GridList (2 draws/строку) прирост копеечный.

Критичная проблема, которую надо решить в дизайне: **при скролле контент меняется каждый кадр** — наивный кэш перерисовывается так же часто, как и без него. Два режима:
- **(a) статический кэш** — инвалидация по dirty-флагам (items/scrollY) — выигрывает на неподвижном списке (а неподвижный список и есть 99% времени);
- **(b) инкрементальный скролл-блит** — при смене scrollY не перерисовывать всё содержимое RT, а сдвинуть старое (dxDrawImageSection старого RT в новый со сдвигом, round по строке) и дорисовать только новые строки — обычно 1–2. O(новых строк) вместо O(видимых). Этого нет ни в DGS (там retrieveRT перерисовывает весь RT при скролле), ни в DXUI.

Механика в DXUI: persistent RT на виджете-контейнере (не из пула — пул оставить для scratch/эффектов), инвалидация по DIRTY.CONTENT/RENDER узла и по scrollY; пер-кадрово — 1 drawImage. Предохранитель: включать по порогу и решать по замерам `stats.draws` (счётчик уже есть — runtime.lua:241, api/diagnostics.lua). Вердикт: делать как опцию GridList v2 / ScrollPanel, не глобально; сначала Diagnostics-замеры (см. 4.2).

### 1.2 Rich text #RRGGBB (ваш п.2)

Инфраструктура готова наполовину — это самое дешёвое улучшение списка:
- `Text.wrap` уже переносит активный `#RRGGBB` на следующую строку (text.lua:101-106 — activeColorCode; :148, 153-154 — carry);
- **draw не парсит коды**: backend_mta.lua:179-184 — 15-й аргумент dxDrawText `colorCoded = false`;
- **measure считает коды буквами**: measurer без colorCoded (backend_mta.lua:230-239) → ширина завышается на 7 байт на каждый код, wrap ломается.

Рецепт: `colorCoded = true` в обоих местах + spec-проп `Label.rich` (default false — чтобы литеральный текст «#ABC123» не съедался). Ellipsis (бинарный поиск, text.lua:172-192) правок не требует: dxGetTextSize с colorCoded сам исключает коды, ключи кэша — строки (text.lua:63-65) — не меняются. Теневой проход Label (label.lua:69-75) отрисует те же коды — парсинг идентичен. Итого ~5 строк + 1 spec. Граничный случай из головы: активный код в самом конце строки после hard-cut — уже обработан (:148).

### 1.3 hover-stay — «наведение дольше N мс» (ваш п.3)

Крючок готов: dispatcher держит `self.hover` (dispatcher.lua:159-175), Runtime:tick — единственный фрейм-цикл (runtime.lua:173-227). Реализация: на hover-start фиксировать `hoverSince = clock()`, в tick при `now - hoverSince >= delay` и не fired → `emit("hover-stay")`; сброс на hover-end/смене цели. Никаких таймеров/хендлеров MTA — тот же паттерн, что у каретки (overlay из instance clock, edit.lua:180-192).

В том же пункте закрыть известную дыру: `_updateNodeState` — документированный no-op «for future cursor tracking» (dispatcher.lua:325-329), вызывается при монтировании узлов (node.lua:654-655). Сейчас смонтированный под неподвижным курсором виджет не получает hover до первого шевеления мыши. Stay-логика обязана ре-хит-тестить стационарный hover при mount.

Tooltip: авто-показ уже есть (`attach` на hover-start, tooltip.lua:73-86), но мгновенный. Задержка = тот же hover-stay: `attach(target, anchor, { delay = 400 })`. Итого ~15 строк + опция tooltip.

### 1.4 ui:each и групповые анимации (ваш п.4)

`_set` уже dirty-coalesится (node.lua:376-430 — мутация → категория → фрейм-флаги, runtime.lua:95-99; один фрейм = один дрен), так что батч ради перфа не нужен — только эргономика. DGS-прецедент — dgsSetProperty по таблице (manager.lua:796-802). Два API:

- `ui:setEach(nodes, { opacity = 0.5 })` — сахар поверх `n[k]=v`;
- `ui:animateEach(nodes, props, dur, ease) → group-handle` с **onDone, когда завершились ВСЕ цепочки** — в AnimHandle уже есть поштучный token.remaining (animation.lua:91-113); группе нужен внешний счётчик завершений (~10 строк). Канонический fade-аут: `ui:animateEach(rows, {opacity=0}, 200):onDone(ui.removeEach)`.

### 1.5 Пиксель-перфект hit для Image (ваш п.5)

Крючок: `hitTestNode` — последняя проверка перед «inside» (hit_test.lua:65-83). Механизм:
- node-хук `_hitMask(lx, ly)` — вызывается из hitTestNode, если задан;
- `Image.pixelHit = true` (opt-in): при первом хит-запросе `dxGetTexturePixels(texture)` → битовая маска (downsample до ≤256 по большей стороне, 1 бит/пиксель, упакованные целые-строки) → кэш рядом с textureCache (текстуры дедуплицированы по пути — manager.lua:40-60, маска разделяемая);
- `section` учитывать смещением; rotation честно не поддерживаем (только axis-aligned, задокументировать).

Цена: dxGetTexturePixels дорог, но **однократно на текстуру**; маска ≤256×256 → ≤8 КБ. Для больших текстур — warn + fallback на rect. DGS-аналог (detectarea) делает то же через loadstring-поверхность (detectarea.lua:7) — наш путь без динамического кода. Усилие M (~50-70 строк), поддерживаю.

### 1.6 Drag&drop data-transfer (ваш п.6)

Текущее: drag-события маршрутизируются **только на нажатый узел** (dispatcher.lua:182-196: `pressed:emit("drag-start"/"drag-move"/"drag-end")`). Drop-таргетов нет.

Дизайн без ломки контрактов:
- таргет: `node.dropTarget = true` или первый `on("drop")` (список имён в isInteractive расширить — hit_test.lua:23-27);
- отдельный лёгкий список drop-таргетов по образцу `_interactive` (rebuild на interactiveDirty — hit_test.lua:47-62);
- в drag-move: `topAt` по этому списку → `drag-over`/`drag-out` на старом/новом; в mouseUp при dragging: `drop(data, sourceNode)` на таргете под курсором, иначе `drag-cancel`;
- dataTransfer: `pressed._dragData` (заполняет юзер в drag-start или через `node:setDragData(...)`), в drop приходит (data, source).

Модальный контракт сохраняется: таргет обязан проходить `reachable()` (dispatcher.lua:112-124) — дроп сквозь модаль невозможен, как и клик. Усилие M (~80-100 строк, только dispatcher + hit_test).

### 1.7 Late allocation RT (ваш п.7) — уже реализовано

`Effects.acquireRT` создаёт RT **только при промахе пула** (effects.lua:219-240), вызывается из `beginGroup` — а beginGroup вызывается в draw-фазе (backend_mta.lua:204-213), не в момент установки blur/mask. Установка свойства лишь ставит invalidates RENDER (node.lua spec). Первый рендер группы и создаёт RT; дальше — переиспользование из пула (bounded, RT_POOL_CAP=64, effects.lua:216-217). Реальный churn один: точные размерные ключи — ресайз группы = новый RT, старый уходит в пул; это нормально.

Вердикт: пункт закрыт, делать нечего. Впечатление «DXUI создаёт RT сразу при эффекте», вероятно, относится к DGS-стилю persistent content-RT — это ваш п.1, а не п.7.

### 1.8 Tab-навигация фокуса (ваш п.8)

Сейчас: dispatcher:key маршрутизирует только на focus-узел (dispatcher.lua:270-287); Tab приходит как обычный "key" (init.lua:112-135) и игнорируется. Попутный факт: Slider вообще не focusable (нет focusable-спека — slider.lua:13-22), клавиатура до него не доходит.

Дизайн: перехват "tab" в Dispatcher:key ДО пользовательских хендлеров:
- порядок обхода бесплатен — painter order (_interactive строится по нему, hit_test.lua:47-62);
- кандидаты: focusable && enabled (видимость уже гарантирована `_visible` в списке);
- от текущего focus (или первого) вперёд/назад (shift), skip недостижимых через reachable();
- Tab всегда навигирует (в однострочном Edit символ табуляции не нужен) — задокументировать.

Усилие S (~30 строк). Нюанс из аудита: в DGS Tab есть только точечно — свойство edit `enableTabSwitch` (Core/edit.lua:4-41); системного обхода фокуса нет ни там, ни в DXUI. Дешёвый дифференциатор доступности.

### 1.9 Multi-click interval + click cooldown (ваш п.9)

Крючок: click-эмиссия в mouseUp (dispatcher.lua:225-229). Реализация: state `lastClick = {node, t, count}`; клик на том же узле в пределах `Settings.defaults.doubleClickInterval` (новый ключ, ~300 мс) → count++ → `emit("click", button, x, y, node, count)`; при count==2 дополнительно `emit("doubleclick")`. Cooldown: подавление кликов чаще `Settings.defaults.clickCooldown` (default 0 = off). ~15 строк + 2 ключа в defaults (settings.lua:52-65). DGS-прецедент — dgsSetAutoClick/MultiClick (client.lua:1862-1874, 1919-1936 по ревью).

---

## 2. Пропущенные оси (ваш список замечаний)

### 2.1 Количество свойств на виджет

DXUI, метод и цифры: spec-таблицы. База: Node 29 пропсов (node.lua:80-149) + Widget 6 (widget.lua:36-49) = 35 унаследованных. Собственные:

| Виджет | own | всего | Виджет | own | всего |
|---|---|---|---|---|---|
| Edit | 25 | 60 | GridList | 10 | 45 |
| ComboBox | 13 | 48 | CheckBox | 11 | 46 |
| RadioButton | 10 | 45 (+RadioGroup: gap, direction) | ContextMenu | 9 | 44 |
| Button | 7 | 42 | Slider | 7 | 42 |
| Label | 8 | 43 | ScrollPanel | 5 | 40 |
| Window/TabPanel/Tooltip | 6 | 41 | Image | 2 | 37 |
| Popup | 4 | 39 | ProgressBar | 3–4 | 38–39 |
| Panel | 3 | 38 | Modal | 3 | 38 |

Среднее ~42 пропса на виджет; каждый — с типом/min/max/validate и точной invalidation-категорией (node.lua:78-79, 345-371): ошибочное значение падает на записи (`error`, node.lua:388-390), а не молча.

DGS, метод и цифры (аудит): канонический реестр — `dgsRegisterProperties("dgs-dx<имя>", {…})` в шапке Core-файлов; это схема допустимых ключей dgsSetProperty, **валидации значений нет** (todo — manager.lua:633-635). База: dgsBasic {visible, enabled, alpha} + dgsType2D {absPos, absSize, rltPos, rltSize, relative} = 8 (client.lua:2061-2072). Дефолты собираются из трёх мест: dgsElementData-таблица в конструкторе (edit.lua:190, gridlist.lua:188, button.lua:96…), or-цепочки аргументов + секция стиля (button.lua:89-95, 113) + dgsApplyGeneralProperties (client.lua:2074-2118).

| Виджет | DGS own | DGS всего | DXUI всего |
|---|---|---|---|
| edit | 38 | 46 | 60 |
| gridlist | 45 | 53 | 45 |
| memo | 37 | 45 | — (виджета нет) |
| combobox | 36 | 44 | 48 |
| button | 23 | 31 | 42 |
| scrollbar | 23 | 31 | — (scrollpanel: 40) |
| checkbox | 21 | 29 | 46 |
| window | 22 | 30 | 41 |
| tabpanel (+tab) | 16 | 24 | 41 |
| label | 13 | 21 | 43 |
| progressbar | 11 | 19 | 38–39 |
| scrollpane | 9 | 17 | 40 |
| image | 7 | 15 | 37 |

Вердикт по оси: ваш тезис подтверждён для **виджет-специфичных ручек** (own): edit 38 vs 25, gridlist 45 vs 10, memo 37 vs 0, combobox 36 vs 13. По полному счёту DXUI местами впереди (edit 60 vs 46) — за счёт 35 унаследованных универсальных пропсов (лейаут/якоря/flex/клип/z-order), которых у DGS свойствами нет вовсе. Два флипа в пользу DXUI, подняты аудитом: **слайдера в DGS нет вообще** (ближайшее — switchbutton, own 24), а label-autosize в DGS нет (только ручной dgsLabelGetTextSize, meta.xml:601-603) — у DXUI autoSize включён по умолчанию (label.lua:14). Что докупать по факту аудита: rtlAutoDetect и autoComplete у Edit (в DGS есть — edit.lua:4-41, meta.xml:517-520), selectionMode у GridList; остальное — из списка дыр ниже.

Вывод и конкретные дыры DXUI, которые я бы закрыл по спросу (не «догонять количеством»):
- **Image**: rotation/rotationCenter/flip (в MTA dxDrawImage это нативные параметры, сейчас не пробрасываются — backend_mta.lua:165-176 шлёт 0,0,0);
- **Label**: shadowOffsetX/Y — сейчас хардкод +1,+1 (label.lua:72-73);
- **Slider**: step-кванта значения нет (value 0..1 непрерывен, slider.lua:13-15) + focusable;
- **Edit**: undo/redo (см. 3.3);
- **GridList**: columns/sort/multiselect (см. 3.5);
- **Memo**: виджет отсутствует целиком (см. 3.1).

### 2.2 Качество/количество настроек тем

DXUI, посчитано точно:
- **9 встроенных тем**: light (авто-активируется, defaults.lua:241-245), dark, green (themes.lua:28-53, 56-84) × плотности default/compact/full (themes.lua:91-118) — density переопределяет только size/padding токены;
- **23 токена**: color×14, radius×4, size×4, padding×1 (defaults.lua:19-50);
- **18 стилизованных компонентов** (defaults.lua:53-238); у Button — 4 варианта (base/secondary/danger/ghost, :63-93) × состояния hover/pressed/disabled (:88-92) + transition-твины состояний через Anim-слой с owner="theme" (widget.lua:131-138, 174-183);
- живое переключение: reapplyAll по всем смонтированным (theme.lua:254-274, 290-309) c owner-guard — юзер-записи не перетираются (node.lua:398-408; widget.lua:146-192), asset-префиксы `texture:`/`font:` с чисткой устаревших (theme.lua:110-144; manager.lua:147-166), fallback-тема (theme.lua:228-232), inline-таблицы (theme.lua:239-250).

DGS (аудит): **в комплекте одна тема** — `styleManager/Default` (styleMapper.lua:5; других папок нет). styleSettings.txt — 590 строк: 20 секций (19 виджетов + cursor), 211 ключей, ~10.6 на виджет-секцию (top: memo 26, edit 24, combobox 20, gridlist 18); покрытие частичное — секций для image/line/layout/browser/detectarea/3d* нет. Button-секция целиком: textColor, color ×3 состояния, image ×3 состояния, font, textSize — 5 ключей (styleSettings.txt:87-104). Загрузка тем — loadstring в песочнице (styleManager.lua:291-299, env :4-11) — ещё одна динамическая поверхность. Live-рестайла baked-свойств нет, НО шрифты читаются из стиля каждый кадр как фолбэк (button.lua:311-313, gridlist.lua:3057, edit.lua:1282-1284) — смена стиля в рантайме всё же меняет шрифты виджетов без явного font. Нюанс к формулировке ревью «no live restyle»: она верна для цветов/картинок, но не для шрифтового фолбэка.

Вердикт: по этой оси вы правы — DGS берёт **количеством виджет-специфичных ручек** (image ×3 состояния и т.п.), DXUI — механикой (варианты, состояния, твины, токены, наследование, плотности) и комплектом (9 тем vs 1). Что докупить в DXUI: (a) **фоновые текстуры Button/Panel + per-state images** — в DXUI их нет вообще (button.lua:13-20, panel.lua:10-12), а theme states уже подставляют per-state props (widget.lua:126-129) — см. 3.7; (b) theme-inspector в DEBUG-слое (LAYER.DEBUG не занят — node.lua:59-61); (c) dev-warn контраста при Theme.define (~10 строк); (d) больше палитр в комплекте — дёшево, темы теперь данные (themes.lua:91-118).

### 2.3 Смена языка — есть у обоих, механики разные

DXUI (translate.lua, 151 строка): `addLocale/setLocale/tr/trFor`, подстановка %1..%N (:86-103), fallback exact → base → key (ru-RU → ru → ключ, :42-59), слабые биндинги `__mode="k"` (:28), pcall-изоляция падших биндингов (:107-122), instance-locale поверх engine (widget.lua:245-256; api/ui.lua:163-170), событие localeChange на корне (translate.lua:124-137).

DGS (аудит подтвердил): dgsSetTranslationTable + per-resource attach (functions.lua:985-1050; все 10 API экспортированы — meta.xml:278-287), подстановки %rep% (functions.lua:1114) и $var (:1133-1137), **условные переводы через loadstring** (:1090-1106 — динамическая поверхность), перевод **любых** свойств через translationListener (:1144-1154; manager.lua:691-694), перевод **шрифтов** (dgsGetTranslationFont — functions.lua:1156-1170; manager.lua:511-525). Рантайм-смена: dgsApplyLanguageChange обходит attached-элементы и зовёт per-типовые updaters (functions.lua:1172-1180): label/button/window (manager.lua:77-89), tabpanel (:505-525), combobox (:992-1004), gridlist (:3008-3027), memo (:1663-1668), edit (:1348-1353). Словарей в комплекте нет — их задаёт потребитель (единственные примеры — test.lua:801-862).

Заимствовать в DXUI (без loadstring):
1. **per-locale font**: значение словаря `{ text=..., font=... }` → applyTranslation пишет оба (widget.lua:245-256, +5 строк); тема уже умеет `font:` префиксы (theme.lua:128-137);
2. **плюрализация** декларативно: `{ one="%1 элемент", few="%1 элемента", many="%1 элементов" }` + pluralFor(locale, n) (ru: n%10==1 и n%100~=11 → one; n%10 in 2..4 → few; else many) — ~20 строк в translate.lua;
3. **items-перевод**: item = `{ textKey = "..." }` → rowText рендерит через tr текущей locale, localeChange → invalidate — ~10 строк в gridlist/combobox.

Итог оси: DXUI-механика чище (weak-биндинги, pcall, instance-локали), DGS — шире охват (шрифты, любые свойства, items). Закрывать пункты 1-3.

---

## 3. Новые заимствования из DGS (вне вашего списка)

1. **Memo — многострочный ввод.** Виджета нет (grep memo|textarea|multiline по source/client = 0). DGS-версия — 1992 строки, доказательство спроса; у dgsMemo есть и горизонтальный скролл (scrollBarState {vertical, horizontal} — memo.lua:1494-1496, скроллбар :1396-1397, SetHorizontalScrollPosition :1534) — закладываем оба в DXUI-версию. DXUI-путь дешевле: Text.wrap готов (text.lua:111-170), selection-механика Edit переносится (edit.lua:91-156), вертикальный внутренний скролл — по образцу _scrollX (edit.lua:219-235). Оценка 300-400 строк. Самый крупный функциональный пробел — приоритет высокий.
2. **IME-ввод (CJK).** Edit принимает onClientCharacter (init.lua:138-144) — IME-композиция невозможна. Приём DGS: скрытый нативный guiEdit (DGS edit.lua:283 — native-элемент для IME). Опционально `Edit.ime = true`: при фокусе offscreen guiEdit, onClientGUIChanged → синк. Честно: сложно (перехват нативного фокуса), для RU/EN не нужно. Приоритет опциональный.
3. **Undo/redo у Edit — заимствование, в DGS ЕСТЬ** (в ревью я ошибся): Ctrl+Z/Ctrl+Y → dgsEditDoOpposite (client.lua:901-904), undoHistory/redoHistory + лимит historyMaxRecords (Core/edit.lua:239-241, 1230-1231). Для DXUI: ring-буфер правок на узле + ctrl+z/ctrl+y через существующий key-хендлер (edit.lua:311-332). Усилие S-M.
4. **Кастомный курсор.** В DGS — dgsSetCustomCursorImage(cursorType, image, rotation, rotationCenter, offset, scale) + Enabled/Size/Type/Color (customCursor.lua:8-68; meta.xml:268-276), текстуры per-type (arrow/sizing_ns/ew/nwse/nesw/move/text/pointer — styleSettings.txt:20-78), по умолчанию выключен. Для DXUI тот же контракт: `Settings.cursor = { types = { arrow = {texture, w, h, hotspot} }, enabled }`, отрисовка в draw после overlays (runtime.lua:245-256). Усилие M, приоритет низкий.
5. **GridList v2: колонки/сортировка/мультивыделение/клавиатура.** DGS-спрос доказан API: сортировка (autoSort/sortColumn/sortEnabled + dgsGridListSort, meta.xml:760-767), мультивыделение (multiSelection, selectionMode — gridlist.lua:26, 45, 128-130; meta.xml:756, 715-716), **клавиатурная навигация** enableNavigation (gridlist.lua:4-48). Ресайза колонок мышью нет даже в DGS — только API ширины (gridlist.lua:1112, 1147) — не копируем, оставляем API. В DXUI: columns = { {title, width, align, sortable} }, selectedIndices + ctrl/shift (shift-механика уже есть — edit.lua:147-156), стрелки на focusable-узле; culling видимых строк уже есть (gridlist.lua:102-106), опционально RT-кэш (1.1). Усилие M-L, приоритет высокий — самый используемый виджет игровых UI.
6. **Инкрементальный скролл-блит RT** — см. 1.1(б). Нет ни у кого.
7. **Фоновые текстуры Button/Panel + per-state images.** В DGS стиль button задаёт image на 3 состояния (styleSettings.txt:87-104); в DXUI у Button/Panel фона-текстуры нет (button.lua:13-20, panel.lua:10-12), при этом theme states уже подставляют per-state props (widget.lua:126-129) — достаточно добавить spec-проп `texture` и рисовать его до текста. Усилие S-M.
8. **Edit autoComplete** (в DGS есть — meta.xml:517-520, autoCompleteSkip в edit.lua:4-41): подсказки поверх существующих Popup/ComboBox. Усилие M.
9. **Switch-виджет** (переключатель; DGS-аналог switchbutton, own 24 пропса): в DXUI выражается вариантом Checkbox + transition-твином состояния (theme transition уже есть — widget.lua:131-138) — возможно, отдельный виджет не нужен, достаточно примера в теме. Усилие XS.
10. **3D-слой** — стратегический пункт вне ближнего roadmap (DGS: отдельный preRender-проход, client.lua:1677-1683). Архитектура DXUI позволяет второй Runtime с 3D-backend (dxDrawMaterialLine3D/projection), но это отдельный проект — честно фиксирую, не обещаю.
11. **Осознанно НЕ заимствуем**: onDgsElementRender-хуки юзер-кода внутри рендер-цикла (источник крашей DGS — ревью, раздел дефектов), loadstring-поверхности (условия перевода functions.lua:1090-1106, песочница тем styleManager.lua:291-299, canvas, importer), G2D hooker (инъекция в чужие ресурсы).

## 4. Нативные фишки — изобретения на базе DXUI

1. **DevTools-инспектор.** LAYER.DEBUG зарезервирован и пуст (node.lua:59-61). Хоткей → оверлей: дерево узлов (children-рекурсия, _id/класс/state), подсветка узла под курсором (topAt уже есть — hit_test.lua:91-108), клик → dump спеков/значений/владельцев (`_owner` — node.lua:255, 408), счётчики stats (runtime.lua:79-83). ~150-200 строк, только DEBUG-слой. У DGS есть только /debugdgs профайлер — инспектора нет ни у кого в MTA dx-мире.
2. **Per-kind draw-атрибутция в Diagnostics.** Сейчас только агрегаты (diagnostics.lua:29-36). RenderList items имеют kind (pass.lua:242 — rtgroup; rect/text/image/rounded/line) → draws по kind + top-N узлов + опциональные ms-замеры build/draw (clock инжектится — runtime.lua:30-34; opt-in perf.timing, в кадре по умолчанию выкл — контракт zero-work не трогаем). Это предусловие для 1.1: без чисел RT-кэш не включать.
3. **Adaptive quality.** `Settings.quality = "low"` → Effects.blur()/roundedShader() возвращают nil (деградация уже предусмотрена headless-фолбэком — backend_mta.lua:79-91) + shadow-off у Label. Усилие S; целевая аудитория MTA — слабые машины.
4. **Scroll-inertia.** ScrollPanel velocity при отпускании → доводка через существующий Anim (animation.lua:116-124) на scrollY. S.
5. **Group-animate** — см. 1.4: onDone-агрегатор по N цепочкам.
6. **Хоткеи окна**: dispatcher:key сейчас только на focus-узел (dispatcher.lua:270-287); window-scoped bindings (фокус внутри окна → map хоткеев окна) — S-M, опционально.

Отказы (честно): batched text-draw — MTA не даёт инстансинга; icon-atlas — textureCache уже дедуплицирует (manager.lua:40-60), premature; RT-кеширование всего подряд — память против копеечного CPU.

## 5. Приоритизированный roadmap

| Фаза | Пункты | Усилие | Ценность |
|------|--------|--------|----------|
| 1. Быстрые победы | rich text (1.2), hover-stay + tooltip delay (1.3), multi-click (1.9), Tab (1.8), ui:each/animateEach (1.4), Slider.step+focusable, Label.shadowOffset | XS-S | UX и API-эргономика за дни |
| 2. Инструменты | Diagnostics-расширение (4.2), DevTools-инспектор (4.1) | S-M | предусловие для перф-решений |
| 3. Крупные виджеты | GridList v2: колонки+сорт+мультивыбор+стрелки (3.5) с опц. RT-кэшем и скролл-блитом (1.1, 3.6); Memo с горизонтальным скроллом (3.1); Edit undo/redo + autoComplete (3.3, 3.8); фоновые текстуры Button/Panel + per-state (3.7) | M-L | закрытие главных функциональных пробелов |
| 4. Взаимодействие | Drag&Drop (1.6), pixel-perfect hit opt-in (1.5), scroll-inertia (4.4) | M | продвинутые паттерны |
| 5. Полировка | per-locale fonts + plurals (2.3), adaptive quality (4.3), custom cursor per-type (3.4), switch-вариант чекбокса (3.9), хоткеи окон, IME (3.2, опц.), 3D (3.10, стратегический) | S-L | широта охвата |

Правило процесса: перед каждым перф-пунктом — замер через stats/Diagnostics; проверка — внешними headless-скриптами (правило проекта: тест-файлы в репо не добавляются).

## 6. Приложение: количественный аудит DGS (v3.524, meta.xml:2)

### 6.1 Свойства — детали метода

Реестр `dgsRegisterProperties("dgs-dx<имя>", {…})` в шапке каждого Core-файла — это схема допустимых ключей dgsSetProperty; валидации значений нет (todo — manager.lua:633-635). Наследование базы через dgsRegisterType (manager.lua:423-431): dgsBasic {visible, enabled, alpha} (client.lua:2061-2065) + dgsType2D {absPos, absSize, rltPos, rltSize, relative} (client.lua:2066-2072). Дефолты не в одном месте: dgsElementData-таблица конструктора (edit.lua:190, gridlist.lua:188, button.lua:96, memo.lua:203, combobox.lua:155, window.lua:98, label.lua:77, image.lua:56, checkbox.lua:127, scrollbar.lua:103, tabpanel.lua:118/:224, progressbar.lua:294, scrollpane.lua:83) + or-цепочки аргументов с фолбэком в секцию стиля (button.lua:89-95, 113) + dgsApplyGeneralProperties (client.lua:2074-2118).

Edit, 10 нестандартных (Core/edit.lua:4-41): rtlAutoDetect, typingSound, typingSoundVolume, autoCompleteSkip, placeHolderIgnoreRenderTarget, placeHolderVisibleWhenFocus, readOnlyCaretShow, enableTabSwitch, clearSelection, caretStyle.
GridList, 10 нестандартных (Core/gridlist.lua:4-48): rowColorTemplate, rowImageStyle, defaultSortIcons, defaultSortFunctions, selectionMode, enableNavigation, moveHardness, leading, sectionColumnOffset, rowMoveOffset.

### 6.2 Темы — детали

- 1 тема в комплекте: `styleManager/Default` — единственная папка; styleMapper.lua:5 (`Name="Path"`, use="Default"), мерж кастомных поверх deepcopy Default (styleManager.lua:301-334).
- styleSettings.txt (590 строк): 20 секций = 19 типов виджетов + `cursor`; 211 ключей в секциях, из них 202 на виджеты → **~10.6 ключа/виджет**; + 6 общих top-level (sharedTexture, sharedFont, disabledColor, disabledColorPercent, systemFont, changeOrder — styleSettings.txt:13-18). Покрытие частичное: секций нет для image, line, layout, browser, detectarea, effectview, 3d*.
- Button-секция (styleSettings.txt:87-104), полностью: `textColor`, `color` (normal/hover/click), `image` (normal/hover/click), `font`, `textSize` — 5 ключей.
- Загрузка тем — loadstring в песочнице styleSecEnv (styleManager.lua:291-299, env :4-11).

### 6.3 Локализация — подтверждённые ссылки

Хранилища LanguageTranslation/LanguageTranslationAttach/resourceTranslation (manager.lua:882-884). Событие onDgsTranslationTableChange (utility.lua:92; functions.lua:992). Перевод шрифтов: dgsGetTranslationFont (functions.lua:1156-1170), применение в manager.lua:511-525. Условные переводы — loadstring с кэшем (functions.lua:1090-1106; вызовы :1203-1206). PropertyListener — динамическая подстановка любых свойств (manager.lua:691-694). Словарей в комплекте нет.

### 6.4 Факты одной строкой

- a) **Глобального масштаба UI в DGS нет** — dgsSetScale не существует (только per-widget textSize, button.lua:115; dgsSetRenderSetting — про renderPriority, client.lua:53-75). DXUI сильнее: design-space stretch/fit (runtime.lua:132-156).
- b) **Относительное позиционирование есть**: dgsSetPosition relative → rltPos (functions.lua:135-146), dgsSetSize relative → rltSize с валидацией [0,1] (:204-210). DXUI шире: percent/auto/fill + anchor×9 + flex (node.lua:101-135).
- c) **Кастомный курсор есть**: dgsSetCustomCursorImage(cursorType, image, rotation, rotationCenter, offset, scale) + Enabled/Size/Type/Color (customCursor.lua:8-68; meta.xml:268-276); текстуры per-type в стиле (styleSettings.txt:20-78); по умолчанию выключен.
- d) **dgsEdit: все четыре — есть**: undo/redo (client.lua:901-904; undoHistory/redoHistory edit.lua:239-241, лимит historyMaxRecords :1230-1231; экспортной undo-функции нет), маска (masked+maskText, edit.lua:20-21; dgsEditSetMasked meta.xml:496), placeholder (+6 placeHolder*-пропсов, edit.lua:24-30; meta.xml:515), maxLength (edit.lua:22; meta.xml:492-493). Бонусом autoComplete (meta.xml:517-520) и readOnly (edit.lua:31). Горизонтального скролла у edit нет — панорамирование за кареткой, как в DXUI.
- e) **dgsGridList**: сортировка есть (autoSort/sortColumn/sortEnabled/defaultSortFunctions/defaultSortIcons, gridlist.lua:4, 21-22, 45, 47-48; API meta.xml:760-767), мультивыделение есть (multiSelection gridlist.lua:26, selectionMode :45, режимы :128-130; meta.xml:756, 715-716), **ресайз колонок мышью — нет** (только dgsGridListSetColumnWidth gridlist.lua:1112 и AutoSizeColumn :1147).
- f) **dgsMemo**: горизонтальный скролл есть (scrollBarState memo.lua:1494-1496, скроллбар :1396-1397, SetHorizontalScrollPosition :1534; meta.xml:540).
- g) **dgsLabel: autosize — нет** (в репо единственный autosize — dgsGridListAutoSizeColumn, gridlist.lua:1147); ручные dgsLabelGetTextSize/GetTextExtent/GetFontHeight (meta.xml:601-603). У DXUI autoSize=true по умолчанию (label.lua:14) — плюс DXUI.
- h) **Слайдера в DGS нет** (Core/slider.lua отсутствует, тип dgs-dxslider не регистрируется; ближайшее — switchbutton, own 24). У DXUI слайдер есть (slider.lua) — плюс DXUI.

### 6.5 Честные границы аудита

Не проверено: эмпирика live-переключения стиля (только статический анализ); серверная часть G2D (G2DManager_s.lua); рендер-цикл customCursor за пределами заголовков (customCursor.lua:8-68); построчное чтение styleSettings.txt ниже :120 (счёт ключей — regex-скриптом, формат сверен на секции button: сошлось); undo/redo в memo (механика найдена только в edit.lua).