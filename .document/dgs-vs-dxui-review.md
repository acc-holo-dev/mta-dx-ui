# Ревью DGS (thisdp/dgs) и сравнение DGS vs DXUI

**База ревью:** клон `https://github.com/thisdp/dgs`, ветка `master`, HEAD `554dd719` (2026-08-29, «fix/scrollbar lockup (#149)»), версия ресурса **3.524**, min MTA 1.6.0. Анализ по коду, не по документации; ключевые механизмы проверены чтением исходника, ссылки — `файл:строка` внутри `D:\File\Developer\Project\dgs`.

**Масштаб:** 67 Lua-файлов, **33 853 строк**, 796 экспортируемых функций (meta.xml 949 строк), ресурс целиком 1.51 МБ (из них 1.4 МБ — Lua). Крупнейшие файлы: `Core/gridlist.lua` 3306, `client.lua` 2124, `Core/memo.lua` 1992, `classlib.lua` 1713, `Core/edit.lua` 1493, `Core/combobox.lua` 1198.

**Для сравнения:** DXUI V4 — 50 файлов, **7 739 строк**, 1 экспорт (`exports.dxui:getUI`), 19 виджетов, ресурс 0.30 МБ.

**Второй проход (глубокий):** четыре параллельных анализа — дозакрытие архитектуры, инвентаризация плагинов, per-frame перф-аудит, целевой bug-hunt — с последующей личной сверкой каждого ключевого заявления по коду. Все находки ниже верифицированы чтением исходника.

---

## 1. Архитектура DGS — как это устроено на самом деле

**Модель — элементы MTA.** Каждый виджет — реальный client-элемент; состояние — в плоских таблицах `dgsElementData[element][key]` (O(1) доступ) и `dgsElementType[element]`. Уничтожение виджета = `destroyElement` → `onClientElementDestroy` (client.lua:1718, приоритет «low») → `dgsCleanElement` (client.lua:1579): blur фокуса, hover-leave, снятие клика, detach от gridlist, рекурсивное уничтожение детей, `autoDestroyList`, ветки специфики (combobox-стрелка, табы), остановка анимаций, снятие из слой-таблиц, 3D-таблиц, BackEndTable, списка переводов и `boundResource`.

**Рендер.** `dgsCoreRender` на `onClientRender` с параметром приоритета (client.lua:66, 713); 3D — на `onClientPreRender` (:748), хендлер снимается, когда 3D-виджетов не остаётся (`dgsCore3DStopRender`, :1677-1683). Порядок: BackEnd → 3D-world → 3D-screen → Bottom → Center → Top (client.lua:202-271). Хит-тест **встроен в проход рендера**: `renderGUI` во время отрисовки проверяет коллайдер каждого виджета (`dgsCollider[тип]`, client.lua:608) и пишет `MouseData.hit` — отдельного прохода по дереву для хит-теста нет. Поддерживаются **пиксель-перфект** области (DetectArea с per-pixel проверкой через `dxGetPixelColor`, client.lua:570-606). Есть гейт на пустоту: если все шесть слой-таблиц пусты, тяжёлый блок пропускается (client.lua:202). Виджеты с эффектом хукаются до/после рендера (`functionRunBefore`/`functions`, client.lua:556-561, 650-655). Снап к целым пикселям (`PixelInt`, :563) против смаза текста. Текст рисуется через обёртку `dgsDrawText` (utility.lua:990-1026) — тонкую (2-3 проверки + 1 dxDrawText), но тени множат стоимость: 1 shadow = 2 вызова dxDrawText, outline-1 = 5, outline-2 = 9 (:1008-1024), плюс `gsub`-аллокация на слой при colorCoded (:1005); для шрифтов типа «dgs-dxsmartfont» вызывается `dgsSmartFontRequestSize`, которой **не существует во всём репо** (единственный хит — место вызова, :993) — латентный nil-call. `dgsDrawImage` не существует — виджеты зовут `dxDrawImage` напрямую (button.lua:306 и др.). Внутри рендер-циклов исполняется пользовательский код: `onDgsElementRender` (:692-693, opt-in через `renderEventCall`), хуки `functions` (:556-561, 650-655), loadstring-код customRenderer в BackEnd-цикле (:215-218) — см. дефект №1 bug-hunt.

**Свойства.** `dgsSetData` — плоское хранилище с no-op скипом и реактивными хендлерами `dgsOnPropertyChange[type][key]` (manager.lua:680-698); `dgsSetProperty` поддерживает **batch на таблицу элементов** (:796-802), карту деприкейшнов с автобэкпортом и предупреждением (:753-792) и `loadstring` для свойства `functions` (:817). `dgsGetProperty` — прямой доступ (manager.lua:836-839). `dgsSetPropertyInherit` — НЕ динамическое наследование, а one-shot рекурсивная запись key/value во всё поддерево с независимыми копиями у потомков (manager.lua:868-880); последующие правки родителя не распространяются. Property-listener'ы → событие `onDgsPropertyChange` (manager.lua:696). **Валидации значений нет** — опечатка в ключе или элементе молча создаёт мёртвое свойство; реальный пример в самом DGS: plugin/cmd.lua:27 `dgsSetData(cmdmemo,...)` (вместо `cmdMemo`) молча `return false`, свойство `enableCommandInfo` никогда не применяется.

**Анимации.** Единая очередь `animQueue` (`dgsAnimTo`/`dgsMoveTo`/`dgsSizeTo`/`dgsAlphaTo`, animation.lua:191-252): O(n) по активным анимациям, `pcall` вокруг записи свойства (:230), кастомные easing-функции (регистрируются `dgsAddEasingFunction`), анимация табличных значений (векторы x,y), delay/reversed, события `onDgsStopAniming/Moving/Sizing/Alphaing`.

**Инпут.** `onClientCursorMove` лишь запоминает позицию (functions.lua:834); всё остальное — per-frame: `dgsCheckHit` (client.lua:1105) по хит-результату из рендера даёт `onDgsMouseEnter/Leave/Hover/Move/Stay/Drag`, multi-click интервалы, focus/blur цепочка (functions.lua:719-752), эмуляция key-repeat для edit/memo (client.lua:293-314). Модификатор-клавиши кэшируются событием вместо поллинга (`keyStateMap`, utility.lua:1208-1230). Edit/memo вводят через **скрытые нативные `guiEdit`/`guiMemo`** элементы (edit.lua:102-140, memo.lua:104-131) — бесплатные IME, буфер обмена и раскладки ценой «нативных» артефактов; вставка — через CEF-страницу (plugin/pasteHandler).

**Парентинг, z-порядок, фокус.** `dgsSetParent` (manager.lua:219-263): координаты ребёнка — относительно контент-области родителя (titleHeight/tab-полосы вычитаются, client.lua:1216-1228); порядок сиблингов = индекс в массиве `children`, дети рисуются поверх родителя (client.lua:695-709). `dgsBringToFront` поднимает всю цепочку предков в конец их массивов (manager.lua:265-379), `dgsMoveToBack` — в индекс 1 (:382-402). **Generic clipping детей нет** — 0 хитов scissor/clipChild по репо; обрезка только внутри RT-контейнеров (scrollpane/gridlist/tabpanel/effectview). Фокус — один элемент + цепочка до корня с дифф-событиями onDgsFocus/onDgsBlur (functions.lua:697-761); **Tab-навигации нет** (в DXUI V4 тоже). Курсорные типы переключаются по хит-элементу (sizing/text/pointer, client.lua:1384-1443), multi-click 250 мс (:1919-1936), clickCoolDown (:1862-1874).

**Стили.** `styleManager/Default/styleSettings.txt` — Lua-таблица (590 строк): весь дефолтный скин, включая кастомные курсоры (с поворотами/масштабом), `sharedTexture`/`sharedFont` (дедупликация текстур/шрифтов), системный шрифт; паки стилей — отдельный репозиторий DGS-Styles. `dgsAddStyle/dgsLoadStyle` регистрируют и парсят стили как sandbox-Lua (styleManager.lua:282-341), `dgsUnloadStyle` корректно уничтожает созданные стилем текстуры/шрифты/шейдеры (:357-376). **Ключевой предел:** `dgsSetStyle` лишь ставит `using` (:343-350) — стили читаются ТОЛЬКО при создании виджета как дефолты аргументов (button.lua:83-95, window.lua:100-140 и все dgsCreate*); live-переоформление уже созданных виджетов НЕ существует. У DXUI наоборот: `Theme.setTheme` пере-применяет стиль ко всем смонтированным виджетам (style/theme.lua:252, 289-296).

**i18n.** `dgsAttachToTranslation` вешает ключ перевода на text-свойство (functions.lua:1004); per-type хендлеры `dgsOnTranslationUpdate` реактивно обновляют текст при смене таблицы (manager.lua:691-694; Core/*.lua). Событие `onDgsTranslationTableChange` (functions.lua:992).

**Серверная часть.** DGS — клиентская библиотека; на сервере: конфиг (server.lua, `config.txt` грузится как Lua-исходник через `loadstring` с проверкой прав, server.lua:43-46), QRCode-прокси (server.lua:123) и **G2D** (G2DManager_s.lua, 800 строк) — консольный миграционный инструмент: `g2d add|remove|list|start|stop|crawl` массово конвертирует ресурсы с нативного `gui-*` на DGS: convertor — статическая перезапись через собственный Lua-лексер; hooker — **инжект loadstring-заглушки в первый клиентский скрипт с «guiCreate» с бэкапом** (G2DManager_s.lua:447-473), в рантайме переименовывает `gui*`→`_gui*` и перепривязывает имена к dgs (dgsExportedFunction.lua:144-150); `crawl` генерирует автодополнение. Сервер также уведомляется о клиентских edit/combo/tab через `-C` события (G2DManager_s.lua:371-374).

**OOP (опционально).** classlib.lua — классы с extends/deepCopy/`preInstantiate`/`init`, инстансы регистрируются и авто-вычищаются при destroy элемента (classlib.lua:91, 131); потребитель пишет императивно или через `dgsImportOOPClass`.

**Апдейтер.** fetchRemote `update.cfg` с raw.githubusercontent.com, периодические проверки, `/updatedgs` применяет обновление, с бэкапом meta.xml и стилей (update.lua:24-52; настройки в meta.xml:1012-1018). В коде прямо предупреждает: «If you don't trust dgs — disable it in config.txt» (update.lua:2).

**Интеграция из чужих ресурсов.** `dgsImportFunction` (dgsExportedFunction.lua:10-75) генерирует call-through прокси: в ресурсе-потребителе `dgsCreateButton(...)` работает как **нативная локальная функция** (без `exports.dgs:`), с захватом file:line для трейсера и авто-реимпортом при рестарте DGS.

---

## 2. Реальные оптимизации в DGS (проверено по коду)

1. **RT-кэширование контента виджетов.** Gridlist рисует колонки и строки в `columnRT`/`rowRT` и за кадр выводит их как 1-2 `dxDrawImage` (gridlist.lua:3167, 3256); то же — memo/edit/combobox (`bgRT`), scrollpane/scalepane/effectview/3dinterface (`mainRT`), композиция в родительский RT (client.lua:493). Invalidate — реактивные хендлеры (флаг `retrieveRT`, gridlist.lua:3164).
2. **Late allocation RT.** `dgsGridListRecreateRenderTarget(gridlist, true)` — RT создаётся лениво при первом рендере (gridlist.lua:288-295).
3. **Куллинг в gridlist.** Невидимые колонки пропускаются (`columnStartX <= w and columnEndX >= 0`, gridlist.lua:3188), строки рендерятся только в видимом диапазоне `FromTo` (:3258).
4. **Преаллокация в горячих путях.** `renderArguments` — предсозданный массив (client.lua:551-553); per-instance `renderBuffer` у виджетов (gridlist render-буферы, window.lua:99); scratch-таблица `easingSettings` в аниматоре (animation.lua:211).
5. **Дедупликация ресурсов.** `sharedTexture`/`sharedFont` в стиле (styleSettings.txt:13-14).
6. **Событийный кэш модификаторов** вместо поллинга `getKeyState` (utility.lua:1208-1230).
7. **Гейт пустоты** — без виджетов тяжёлый блок цикла не выполняется (client.lua:202); **3D-хендлер снимается** при исчезновении 3D-виджетов (:1677-1683); **blur screen source** — глобальный с refcount (последний blurbox освобождает, :1666-1671).
8. **Hit-тест без отдельного прохода** — вычисляется в том же обходе, что и рендер (client.lua:569-619).
9. **No-op скип записи свойства** (manager.lua:686) — как в DXUI.
10. **Refcount-очистка** GlobalScreenSource; авто-destroy всего созданного через `dgsAttachToAutoDestroy` (все RT/шейдеры/текстуры зарегистрированы: gridlist:311,319; memo:301; edit:283; blurbox:69-118 и др.) — утечек на destroy нет.
11. Встроенный профайлер: `dgsRenderInfo` (frames, frameRenderTimeScreen/3D/Total, счётчик rendering по ресурсам) и режим `debugdgs` с хайлайтом хит-элементов и ABS/RLT оверлеем (client.lua:344-379).

**Цена этих оптимизаций (per-frame аудит, всё с точными строками):** каждый кадр — полная рекурсия всех видимых виджетов; `MouseData.WithinElements = {}` — свежая таблица каждый кадр (client.lua:227); **scrollbar — ещё 1 таблица мусора за кадр на инстанс** (`eleData.image or {}`, scrollbar.lua:406; `image` по умолчанию не сетится); hover считается покадрово, а не по движению; **edit — худший hot-path: безусловные `dxGetTextWidth(utf8Sub(text,0,caretPos))` и `text:reverse():find("%S")` КАЖДЫЙ кадр, без кэша и независимо от фокуса** (edit.lua:1438-1451) — O(N) CPU + GC на длинном тексте; button с `iconImage` меряет текст каждый кадр (:332-333); memo в статике O(1) от длины текста (RT-кэш с корректным dirty-гейтом :1762/1953), caret — O(колонка каретки)/кадр (:2090); gridlist — плоская плата за видимую ячейку без измерений в цикле (:3258-3428), но rowImageStyle=2 даёт O(строк×видимых_колонок×всех_колонок) через `dgsGridListGetColumnAllWidth` на каждую ячейку (:3329→1189-1222); сортировка — table.sort по всему массиву строк, O(n log n)/O(n²), user-компаратор (gridlist.lua:689-700); **pcall вокруг рендереров нет** (client.lua:631) — ошибка одного виджета рвёт кадр (в аниматоре pcall есть, animation.lua:230); глобальные `self`/`rt` в renderGUI (client.lua:550, 631). Чистые пути: label (label.lua:186-214), image (dxGetMaterialSize кэширован identity-чеком, image.lua:194-201), чекбоксы/радио (измерения только при изменении).

---

## 2b. Дефекты DGS — целевой bug-hunt (все подтверждены чтением кода)

**Majors:**

1. **Мутация слой-таблиц во время рендера.** Все циклы `for i=1,#Table` фиксируют границу один раз (client.lua:209-219, 231-271, 705-707), а внутри исполняется пользовательский Lua (`onDgsElementRender` :692-693, хуки `functions` :556-561/:650-655, loadstring-код customRenderer :215-218): уничтожение/репарентинг одного виджета в хендлере → хвост итерации читает nil → каскад attempt-to-index-nil каждый кадр.
2. **Цикл уничтожения детей спотыкается о 3D-элементы.** `dgsCleanElement` всегда читает `child[1]` (client.lua:1598-1606), но дети 3D-типов не вырезаются из родительского `children` (их ветка чистит только 3D-таблицы, :1675-1684), а `dgsSetParent` разрешает 3D под 2D без проверок (manager.lua:226-237) → родные сиблинги никогда не уничтожаются (живые сироты).
3. **Nil-deref по разрушенному родителю.** :1686-1697 читает `dgsElementData[parent].children` без `isElement(parent)` — уничтоженный родитель остаётся truthy-userdata с уже стёртыми данными (:1714) → падение очистки сирот (запускается дефектом №2).
4. **reversedProgress-анимации никогда не завершаются.** Тест завершения `rProgress == 1` стоит ПОСЛЕ разворота `1-rProgress` (animation.lua:205-206 → :240): обратная анимация навсегда остаётся в очереди, `onDgsStopAniming/Moving/Sizing` не приходят, `dgsIsAniming` блокирует повторный запуск.

**Minors:** 5) стейл Move/Scale после destroy в середине драга → клик второй кнопкой телепортирует новый виджет к курсору (сбросы :1300-1347 вложены в `if clickedElement` :1198; dgsCleanElement чистит только `click.*` :1592-1594); 6) `dgsStopAniming` с table-свойством пропускает элемент после `table.remove` — безусловный `index=index+1` (animation.lua:140) вместо else-инкремента строковой ветки (:103-118) → выживают конкурирующие анимации позиций; 7) `enteredElementType` читается на :1113 до `local` на :1124 → глобальный nil: сброс preSelect гридлиста при скрытии курсора не работает; 8) one-frame стейл тип курсора после enter (:1124 → :1169); 9) `onDgsMouseLeave` с nil-координатами (:187, :1589 — mx/my/hits там не определены); 10) `print()` в покадровом коде labelBlurEffect.lua:24; 11) мёртвый дубль-блок инвалидации memo (:1758-1761 повторяет :1738-1741).

**Hardening-заметки:** контракт `autoDestroyList` — индексы ниже −10 не проверяются, detach не видит негативные индексы (functions.lua:963-967, 974-975); глобальные `rt`/`self` в renderGUI (:550, :631) делают вложенные рендеры race-prone; вызов несуществующей `dgsSmartFontRequestSize` (utility.lua:993); `dgsSetData(cmdmemo,...)` — опечатка элемента, молча не применяется (plugin/cmd.lua:27).

**Проверено чисто:** стейл-ссылки фокуса/hover/KeyHolder/MouseHolder (все isElement-гвардированы), клики не стартуют внутри рендер-циклов, рекурсия сеттеров ограничена (depth 2), свежий фикс scrollbar lockup (#149) в штатных сценариях держится.

---

## 3. Списки: DGS vs DXUI

### 3.1 Функциональность

| Область | DGS | DXUI |
|---|---|---|
| Виджеты ядра | 29 типов: window, button, label, image, checkbox, radiobutton, **memo**, combobox, **selector**, switchbutton, edit, gridlist, tabpanel, progressbar, scrollbar, scrollpane, scalepane, menu, line, layout, browser, customRenderer, effectview, detectarea, customCursor, **3dinterface/3dtext/3dline/3dimage** | 19: panel, window, button, label, image, checkbox, radiobutton, progressbar, slider, scrollpanel, edit, combobox, tabpanel, gridlist, popup, contextmenu, modal, tooltip (+builders) |
| Плагины | 20: colorPicker, chart, gif, media (видео), svg, mask, nineSlice, gradient, blurBox, screenSource, remoteImage, QRCode, canvas, effect3D, dynamicShader, objectPreview, pasteHandler, cmd-консоль, tooltip, BasicShape (roundRect/circle/quad) | нет плагин-системы; встроено: blur/mask через пул RT (render/effects.lua), шейдеры через `ui:shader` |
| Rich text | да — inline `#RRGGBB` в строках (dgsCreateTextBuffer) | нет |
| Drag&drop | фреймворк: data-transfer, хендлеры, превью (meta.xml:262-266, client.lua:317-339) | drag-события виджета (dispatcher), data-transfer нет |
| IME/ввод CJK | да — через нативные guiEdit/guiMemo (edit.lua:102-140) + paste через CEF | нет — собственный caret/selection (widgets/edit.lua), событие `character` |
| События | 30+ generic (mouse/keyboard/property/scroll/drag/anim/translation) + widget-специфичные; серверные `-C`-хуки; всего 148 trigger-точек | 17 типов диспетчера (hover/click/press/release/drag/scroll/key/character/focus/blur...) + widget-специфичные (change/select/submit/close), подписка `node:on` |
| Анимации | dgsAnimTo/MoveTo/SizeTo/AlphaTo, кастомные easing, delay, события старта/стопа; пауза — нет | цепочки `node:animate(...).then(...)`, pause/resume, owner-guard, easing + spring |
| Темы | стили = Lua-файлы, load/unload/switch в рантайме; **переключение действует только на новые виджеты** (styleManager.lua:343-350) | темы = таблицы с `extends` и токенами; **live-переключение переоформляет все смонтированные виджеты** (theme.lua:289-296) |
| i18n | привязка ключей к text-свойствам, реактивное обновление | addLocale/setLocale/setTextKey, per-instance locale, `%1..%N` подстановка, событие localeChange |
| Масштабирование | relative-координаты + positionAlignment + scalepane | **design-viewport** (`design={width,height,mode}`) + percent/auto/fill sizing + flex grow |
| Layout | dgsCreateLayout (стек с сортировкой) | flex row/column с grow, auto-size, dimension-система |
| Модальность | нет отдельного примитива (окна + захват курсора) | **modal-стек** в диспетчере (блокирует инпут ниже по стеку), popup-слой, slop-click контракт |
| Изоляция ошибок | только аниматор | периметры pcalls: tick/handlers/style/translate/resources |
| Диагностика | dgsRenderInfo + /debugdgs 1-3 + creation tracer | Diagnostics (idleRatio, rebuilds, items) |
| Cross-resource | глобальное дерево на клиент + авто-destroy при остановке ресурса-владельца (boundResource) | **per-owner деревья**: каждому ресурсу — свой инстанс, авто-релиз при остановке (api/exports.lua:54-69) |
| Тестирование | test.lua — демо (1249 строк) | демо (281 строк); движок headless-тестируем (backend/clock/measer инъекции); автотестов в репо нет (решение владельца) |

**Итог по функциональности:** DGS — ~4.4× больше кода и на порядок шире покрытие (memo, браузер, 3D-UI, медиа, colorPicker, chart, svg, gif, QRCode...). DXUI закрывает основной набор «окна-формы-списки» и добавляет то, чего в DGS нет: модальный стек как примитив, flex, design-space, изоляция per-resource.

### 3.2 Скорость (обе библиотеки обязаны перерисовывать каждый кадр — это режим MTA dx)

**DGS сильнее в:**
- **Draw-call бюджете сложных виджетов.** Gridlist/memo/edit/combobox рендерят контент в RT и выводят одной текстурой за кадр — при 1000+ строк или длинном memo это кратно меньше `dxDrawText`-вызовов, чем прямая отрисовка.
- Куллинге контента (колонки/строки только видимые).
- Пиксель-точных хит-тестах без лишних проходов.

**DXUI сильнее в:**
- **CPU на кадр в статике.** Список рендера пересобирается только по dirty-флагам (render/pass.lua), layout/measure — двухпоколенческие кэши; на пустом кадре работа = эмит готового списка, без пересчёта позиций/выравниваний (в DGS positionAlignment и absSize пересчитываются в renderGUI каждый кадр, client.lua:509-537).
- **Инпуте:** hover/focus/click — событийный диспетчер, не покадровый пересчёт; hit-test по persistent списку с zIndex.
- **GC-дисциплине:** пул items/массивов/RT (render_list.lua, effects.lua) против постоянного мусора DGS (`WithinElements={}` за кадр, 1 таблица на scrollbar за кадр, `animItem[0]` в аниматоре, edit — O(N) подстроки+reverse за кадр).
- **Пути каретки/текста:** DXUI `Text.charX` → кэш measure двух поколений (text.lua:226-230, 233-236) — O(1) CPU после первого кадра (остаётся одна sub-аллокация префикса; overlay каретки рисуется только в фазе блинка у сфокусированного edit, edit.lua:257-269); DGS edit меряет префиксы текста без кэша каждый кадр (edit.lua:1438-1451).
- **Устойчивости:** pcall на каждом периметре — ошибка потребителя не рвёт кадр; в DGS ошибка в render-функции виджета валит весь проход (client.lua:631 без pcall).

**Общая оценка:** при обычных формах (десятки виджетов) разница несущественна — обе уложатся в кадр; расхождение проявляется на краях: огромные таблицы/мемо — DGS выигрывает за счёт RT; сложные сцены с частыми изменениями и строгим бюджетом кадра — DXUI за счёт кэшей и нулевого пересчёта в статике.

### 3.3 Легкость (для другого разработчика)

**DGS:**
- Плюс: naming в стиле MTA (`dgsCreateWindow` ≈ `guiCreateWindow`) — порог входа минимальный; `dgsImportFunction` даёт нативный синтаксис; 5-язычная вики (EN/AR/ZH/PL/TR), Discord, паки стилей, автокомплит для Notepad++/Sublime/VS Code, G2D-конвертер старых проектов, `/dgscmd`, `/debugdgs`.
- Минус: 796 функций — поверхностно просто, глубоко сложно; файлы по 2000-3300 строк нечитаемы для джуна; нет валидации аргументов на set-свойствах (тихие опечатки); глобальное состояние (`self`, `rt` в client.lua:550) требует «знать, где чьё».

**DXUI:**
- Плюс: одна точка входа (`getUI` → `ui:window({...})`), props-таблицы со спецификациями и дефолтами (опечатка в свойстве видна сразу), контрактные док-комментарии, файлы по 17-320 строк, события через `node:on`, демо на 281 строке покрывает всё.
- Минус: нет внешней вики/туториалов за пределами репо; API-философия (props + методы) непривычна для тех, кто пришёл с MTA GUI; меньше готовых «сходи и возьми» виджетов — придётся собрать из панелей/flex то, что в DGS есть готовым.

### 3.4 Фишки DGS (нет в DXUI)

1. Rich text `#RRGGBB` в любых строках.
2. 3D-интерфейсы (dgsCreate3DInterface/3DText/3DLine/3DImage) с dimension/interior-фильтрами (client.lua:231-249).
3. Пиксель-перфект hover-области (DetectArea, client.lua:570-606).
4. Плагины: colorPicker, chart (рендер через SVG, chart.lua:7-10), gif (**чистый Lua-декодер**, gif.lua:238), медиа-плеер (CEF HTML5, media.html), SVG, mask, nineSlice, remoteImage, QRCode, canvas, **cmd — встроенная игровая консоль** (read-only memo + скрытый edit, cmd.lua:11-29), **dynamicShader — сборка HLSL-исходника в рантайме** (dynamicShader.lua:8-30), scalepane zoom (LALT+wheel, scalepane.lua:352-361).
5. Кастомные курсоры (типы resize/move/text с поворотами, styleSettings.txt:20-70).
6. Drag&drop с data-transfer и превью.
7. G2D — серверный конвертер `gui-*` → DGS (G2DManager_s.lua).
8. `onDgsMouseStay` (задержка наведения) + multi-click interval (functions.lua:841-854).
9. Скрытые нативные guiEdit/guiMemo → IME/раскладки/вставка из ОС.
10. Встроенный апдейтер с версионными уведомлениями.

### 3.5 Фишки DXUI (нет в DGS)

1. Модальный стек + popup-слой с документированным контрактом инпута (input/dispatcher.lua).
2. Design-viewport: один layout под 800×600 растягивается на любой экран, `percent/auto/fill`.
3. Flex row/column с grow.
4. Темы-таблицы с `extends` и токенами, live-переключение; per-instance locale.
5. Анимационные цепочки с pause/resume и owner-guard (защита от перезаписи анимируемых свойств темой).
6. Спецификации свойств с валидацией и `invalidates`-картой.
7. Diagnostics: idleRatio/rebuilds/items.
8. Изоляция деревьев per-resource + авто-релиз при остановке ресурса.
9. Spring easing; событийный инпут (без покадрового пересчёта ховера).
10. Пул RT по точному размеру + двухпоколенческие кэши.

### 3.6 Безопасность и надёжность

- **DGS:** ACL-запросы `function.fetchRemote`, `function.loadstring`, `general.ModifyOtherObjects` (meta.xml:1001-1005); **не менее шести поверхностей динамической загрузки кода**: config.txt (server.lua:46), свойство `functions` (manager.lua:817), импортёр (dgsExportedFunction.lua:34), апдейтер (скачивает файлы с raw.githubusercontent.com с SHA1-сверкой, update.lua:108-184, без авто-рестарта — :215), G2D hooker (инжект loadstring-строки в чужие ресурсы с бэкапом, G2DManager_s.lua:456-472), canvas/detectarea (loadstring backend, canvas.lua:22-33, detectarea.lua:7). Все — осознанные решения с guard'ами прав, но для закрытых/параноидальных серверов это точка аудита. Лицензия DPL v1: нельзя перепубликовать/продавать (README.md:58-69). `test.lua` (автозапуск демо, test.lua:1311) и `/dgscmd` стоит выключать в проде через настройки meta.
- **DXUI:** ноль динамических загруз, ноль ACL-запросов; pcall на всех периметрах; идемпотентные teardown-контракты (проверено в прошлых раундах ревью). Лицензия — по усмотрению владельца.
- **Обе:** утечек на destroy не найдено (DGS: `autoDestroyList` покрывает все RT/шейдеры/текстуры — проверено грепом по всем Core-виджетам; DXUI: Events.clear + идемпотентные destroy, tooltip-teardown закрыт в раунде 3).

### 3.7 Зрелость и экосистема

- DGS: 6+ лет, ~149 PR, активные коммиты (2026-08), тысячи серверов, Discord, вики на 5 языках, стили сообщества. Обратная сторона: legacy-глобалы, вес 796 функций, loadstring-поверхности.
- DXUI: один владелец, строгая инженерия (спеки, пулы, кэши, контракты, headless-тестируемость), но нет внешних доков/сообщества, покрытие виджетов скромнее.

---

## 4. Что стоит позаимствовать в DXUI (по приоритету)

1. **RT-кэш контента тяжёлых виджетов.** У DXUI уже есть пул RT по размеру (render/effects.lua) — логично прогонять через него gridlist/edit при больших объёмах (десятки строк — прямой рендер, сотни — RT-кэш с invalidates по dirty-флагу). Ключевая идея DGS, которую инфраструктура DXUI поддержит без новых механизмов.
2. **Rich text `#RRGGBB`** в Text.measure/layout (токенизация в layout, сегменты цвета в draw) — частая просьба UI-разработчиков, ложится в существующий Text-кэш.
3. **`onDgsMouseStay`-аналог:** событие «наведение дольше N мс» в диспетчере (для тултипов/превью). Дёшево: в mouseMove уже есть hover-корреляция.
4. **Пакетные правки:** `ui:each({n1,n2,n3}, {alpha=0.5})` — в DGS это удобно для fade-аутов групп (manager.lua:796-802).
5. **Пиксель-перфект hit-области для Image** (прозрачные пиксели не ловят ховер) — collider-хук per-тип как в DGS (client.lua:608), опционально per-виджет.
6. **Drag&drop data-transfer** поверх существующих drag-событий (пресеты превью, drop-таргеты).
7. **Компат-карта при миграции мажоров** (DXUI уже прошёл V3→V4 с `cursor`→`caret`): карта старых имён + runtime-предупреждение, как manager.lua:753-792.
8. **Автокомплит-JSON/файл** для VS Code по публичному API `ui:*`.
9. **Внешняя вики/README-сайт** для потребителей вне репозитория (DXUI уже есть демо, не хватает reference-доков).
10. **Late allocation** RT-групп (DXUI создаёт RT пула сразу при эффекте) — отложить до первого реального рендера, как gridlist.lua:294-295.
11. **Tab-навигация фокуса** (Tab/Shift+Tab между focusable-виджетами) — нет ни в DGS, ни в DXUI: дешёвая доступность-фишка и дифференциатор.
12. **Multi-click interval + click cooldown** в диспетчере — UX-мелочь DGS, стоящая пары строк (client.lua:1862-1874, 1919-1936).

**Чего заимствовать НЕ надо:** глобальное состояние в стиле DGS (у DXUI контексты локализованы — это его главное читаемостное преимущество), loadstring-поверхности, файлы-монолиты.

---

## 5. Вердикт

**DGS** — функциональный рекордсмен MTA-экосистемы: широчайший набор виджетов и плагинов, реальные оптимизации в горячих путях (RT-кэш, куллинг, преаллокация), вылизанный годами lifecycle и первоклассный DX-обвес (импортёр, мигратор, вики, стили, апдейтер). Архитектурно — унаследованный «MTA-way»: глобальное состояние, элементы-виджеты, 796 плоских функций, гигантские файлы; валидации свойств нет, изоляции ошибок в рендере нет, динамический код — осознанный трейд-офф; bug-hunt добавил 4 major-дефекта (мутация таблиц рендер-цикла под юзер-кодом, сироты 3D-детей, nil-deref родителя, незавершающиеся reversed-анимации) и подтверждённый per-frame O(N)-хот-пат в edit — «прожитые» края, о которые спотыкается именно production при нестандартных сценариях (destroy в хендлерах, 3D+2D-миксы, длинные тексты).

**DXUI** — инженерно строгий движок нового поколения: спеки с валидацией, dirty-driven рендер-пасс, пулы и двухпоколенческие кэши, событийный инпут с модальным стеком, per-resource изоляция, изоляция ошибок на каждом периметре, headless-тестируемость. Покрытие виджетов — ядро, а не «всё»; экосистема (доки, сообщество, стили) — только зарождается.

**Сравнение честное, не приговор:** «быстро собрать богатый UI с медиа/3D/IME и не думать о бюджете кадра на слабых машинах» → DGS. «Долго живущий продукт, читаемость для команды, предсказуемость памяти и кадров, отсутствие чужого кода и loadstring» → DXUI. Они дополняют друг друга: список раздела 4 — конкретная программа импорта идей DGS в DXUI без потери его главных преимуществ.

*Отчёт основан на построчной проверке ~15 ключевых механизмов DGS (рендер, инпут, свойства, анимации, gridlist, lifecycle, стили, i18n, сервер, апдейтер, importer) и полной инвентаризации DXUI V4 из предыдущих раундов ревью.*