# DXUI v4-next — отчёт о выполненном релизе

Исполнение `.document/dxui-release-plan.md` (волны W0–W6), все 29 основных задач закрыты.
Проверка: полный синтаксис-проход по 51 Lua-файлу `source/` — 0 ошибок (luaparse, Lua 5.1); `loadstring` в коде отсутствует (одно док-упоминание в translate.lua), `guiCreate*` отсутствует — инварианты соблюдены. Коммитов нет (по правилу проекта — команда на ваш суд).

## Сводка diff (git diff --stat)

40 файлов изменено (+2997 / −331) + 1 новый файл (`source/client/widgets/memo.lua`, ~560 строк) + `meta.xml` подключение memo. В diff входит и пакет правок первого ревью (до релиз-плана).

Крупнейшие: gridlist.lua +629 · manager.lua +244 · dispatcher.lua +279 · effects.lua +187 · edit.lua +314 · api/ui.lua +124.

## Волны и задачи

**W0 — E1 Страж системного ввода** ✅ — `systemInputBlocked()` (чат/консоль/окно MTA/меню) первым в onClientKey/onClientCharacter (init.lua). Edit больше не ловит символы, идущие в чат; Tab-цикл не дёргается при открытом чате.

**W1 — быстрые победы** ✅
- E2 DXT/mipmaps/edge: `ui:texture(path, {format, mipmaps, edge})`, опции в ключе кэша (manager.lua); дефолт байт-в-байт argb.
- E3 quality шрифтов: `ui:font(path, size, {quality})`, спека `"path:size:quality"`, theme-префикс `font:` (theme.lua).
- A1 Rich text: `Label.rich` — #RRGGBB коды рендер и wrap/ellipsis (text.lua, ключ кэша `|r`).
- A2 hover-stay + стационарный hover: `Dispatcher:update(now, hitRebuilt)` из tick — событие hover-stay (hoverStayDelay=400), hover при mount под курсором.
- A3 Tooltip delay: `attach(target, anchor, {delay=N})`.
- A4 Multi-click: click несёт count, `doubleclick` при 2 в doubleClickInterval=300, clickCooldown.
- A5 Tab-навигация: cycleFocus по painter order, wrap-around, модаль замкнута.
- A6 `ui:setEach/ui:animateEach` + групповой onDone (плюс фикс: синхронные нулевые анимации больше не теряют onDone).
- A7 Slider step + клавиатура (arrow_l/arrow_r/home/end — имена по wiki Key_names; попутно исправлен ранее неверный `left/right`).
- A8 Label shadowOffsetX/Y.
- A9 Image rotation/rotationCenter (центр = по умолчанию центр квадры; hit остаётся AABB).
- E4 Blend RT-групп: контент RT — `modulate_add`, композит — `add` (state.lua, groupDepth-счётчик).

**W2 — крупные виджеты** ✅
- B4 Edit undo/redo: ring с коалесценцией 300 мс, лимит `editHistoryLimit` (64), ctrl+z/ctrl+y.
- B1 GridList v2: колонки (headers, сортировка по клику, sort-марк), мультивыделение ctrl/shift, клавиатура (стрелки/pgup/pgdn/home/end, ctrl+a), `_ensureVisible`, `get/setSelectedIndices`, API `sort(col, dir)`. Сортировка in-place — выделение сохраняется по идентичности строк.
- B5 Текстуры Button/Panel: `texture`/`textureSection`, theme-states подхватывают; fail не кэшируется (FAIL_TTL жив).
- B3 Memo — новый виджет: многострочный ввод, перенос, selection, undo/redo, v-скролл колёсиком, Enter/строка, Ctrl+Enter/submit.
- B6 Edit autoComplete: `autoComplete` (таблица|функция), popup-сиблиинг LAYER.POPUP, arrow_u/d/enter/tab/escape, вставка с записью в историю.
- B2 RT content-cache: opt-in `cacheContent` у GridList — persistent RT (backend_mta: beginPersistentGroup/endPersistentGroup/compositePersistentGroup), покой = 1 композит-драв; скролл внутри полувысотного окна = dxDrawImageSection-сдвиг; ребейк по сигнатуре контента/выходу из окна.

**W3 — взаимодействие** ✅
- C2 Пиксель-хит: `Image.pixelHit` — бит-маска альфы (≤256/сторона, ≤8 КБ/материал, кэш ≤64 с вайпом), любые размеры текстуры через стрид-сэмплинг; fail → rect+warn; rotation → rect (документ).
- C1 Drag&Drop: `node.dragData` (спека базового Node) — источник; таргеты = узлы с `drag-over/drop` хендлерами (`_dropTargets`, rebuild вместе с `_interactive`); события drag-over/drag-out/drop/drag-cancel; reachable() (модальный контракт) действует.
- C3 Scroll inertia: `defaults.scrollInertia=0` (off); флик скролла = velocity по последним дельтам + Anim на scrollY ("out"), новый notch прерывает.

**W4 — полировка и i18n** ✅
- D1 Пер-локальные шрифты: словарное `{text=…, font="path:size"}` — applyTranslation пишет текст+шрифт через общий кэш.
- D2 Плюрализации: `pluralFor(locale, n)` — ru one/few/many, en one/other; `tr(key, n)` форма+подстановка; БЕЗ loadstring. Проверка правил (ru): 0→many · 1→one · 2→few · 5→many · 11→many · 21→one · 101→one · 111→many. en: 1→one, остальное→other.
- D3 Перевод items: `{textKey=…}` у GridList (одноколоночный режим) и ComboBox; смена локали — ребилд строк через слабый реестр биндингов, head ComboBox обновляется.
- D5 Switch: `variant="switch"` (или theme-вариант `style="switch"`, пример в defaults.lua) — track+тумблер, позиция анимируется через Anim (switchT), длительность из theme transition.
- D6 Хоткеи окна: `window.hotkeys = {[key]=fn}` — матчинг в Dispatcher:key (после E1/A5, до focus-цепочки), активны при фокусе в поддереве, `false` от хендлера = fall-through; дефолтов нет.
- D4 Курсор: `defaults.cursor = {enabled=false, scale, color, types={arrow/text/hand}}` — рисуется после overlays; тип по hover-узлу; без текстуры → системный; enabled=false — ноль затрат. Ассеты — ваши (§5).

**W5 — визуал** ✅
- E6 Градиенты: ОДИН общий шейдер + дедуп param-таблиц (effects.lua); `gradient={from,to,angle}` у Panel/Button/Image заменяет заливку (квадратные углы; бордер сверху); states подхватывают. Отступ от карточки: без отдельного .fx-файла — inline-код по образцу rounded/blur/mask.
- E5 backdropBlur: `backdropBlur` у Window/Modal — ленивый half-res screen source, dxUpdateScreenSource раз в кадр и ТОЛЬКО в кадрах с видимым backdrop-узлом; crop по экранному прямоугольнику окна через blur-шейдер; нет узлов → источник не существует (zero-work).

## Смоук-сценарии (проверяются в игре)

1. **B4/B6**: печать → ctrl+z×3 → ctrl+y×2 (выделение восстановлено); список подсказок фильтруется, enter вставляет, escape закрывает.
2. **B1**: 3 колонки × 200 строк — сортировка по клику хедера, ctrl/shift-выделение, стрелки, ctrl+a; одноколоночный режим — регресс нет.
3. **B2**: `cacheContent=true` на 200-ряд листе — `stats.draws` (api/diagnostics.lua describe) в покое ≈1 draw вместо ~30 — **замер у вас, §5.2**.
4. **B3**: многострочный ввод с переносом, Enter/Ctrl+Enter, выделение мышью, колёсико, undo.
5. **C2**: PNG с прозрачностью — клики в прозрачных местах не попадают; без pixelHit — rect как раньше.
6. **C1**: dragData-строка → перенос на drop-панель (drag-over highlight, drop(data, source)); отпускание мимо → drag-cancel; клики не сломаны.
7. **C3**: `defaults.scrollInertia=250` — флик прокатывается и затухает; 0 — как раньше.
8. **D1–D3**: смена локали на лету — текст/шрифт/плюрализации/items GridList+ComboBox переключаются.
9. **D5**: `variant="switch"` — тумблер скользит при клике; обычный чекбокс без изменений.
10. **D6**: хоткеи окна работают при фокусе внутри, молчат вне окна.
11. **E4**: текст в clipMode="rt"-контейнере — **визуальная сверка у вас, §5.1**; при спорном результате откат на "blend" в StateCache (state.lua, BLEND_RT_CONTENT).
12. **E6**: 3 панели gradient angle 0/45/90 из темы; без gradient — прежний вид.
13. **E5**: Modal/Window c backdropBlur=2..4 — за окном заблюренный мир; закрыть все — источник не обновляется.

## Отклонения от плана (все — инженерные решения)

- **B2**: инкрементальность = margin-window blit (сдвиг секцией RT + ребейк по сигнатуре/выходу из окна), а НЕ пер-ряд redraw (self-copy RT небезопасен на DX9). RT = width×2×height — держите узел ≲1000 px высотой, иначе создание RT провалится → graceful degradation (прямой рендер). In-place правки текста строк НЕ детектируются — переустановите `items`.
- **C2**: маска строится стрид-сэмплингом для ЛЮБОГО размера текстуры (карта: «>256 → fallback» читалась как ограничение источника; ограничение применено к МАСКЕ, иначе фича мертва для 512+ текстур). fail-кэш без TTL (пиксель-риды дороги).
- **E6**: шейдер inline (без .fx/<file>) — консистентно с остальными эффектами.
- **E5**: источник в effects.lua (рядом с blur), не в manager.lua; разрушается clearCaches.
- **C3**: инерция на ScrollPanel (карточка); GridList-инерция — следующая очередь (его wheel-хендлер другой).
- **D5**: включение и по `variant="switch"`, и по theme-варианту `style="switch"` (одним пропом можно и рисовать, и красить).
- **A7/C-memo**: исправлен пребаг с именами клавиш (`left/right` → `arrow_l/arrow_r`) — wiki Key_names.

## Известные ограничения (по плану §3, перенос в док)

- Hit при rotation остаётся AABB (A9/C2) — повёрнутые картинки ловятся по прямоугольнику.
- DXT-форматы требуют предконверта в .dds (лаги загрузки при конверсии «на лету»); quality шрифтов — quality MTA по умолчанию ("proof") сохранён.
- B2: RT-кэш и blur/mask на одном узле — blur/mask выигрывает (cacheContent игнорируется).
- D4: без ассетов — системный курсор; скрытие системного курсора (showCursor) — решение ресурса.