# DXUI V4 — RELEASE MASTER PROMPT

<!-- INTERNAL PROCESS DOCUMENT — not user/contributor documentation.
     This is the release-planning prompt that drove V4 development:
     it records the phase plan, the "Definition of Done", process rules
     (e.g. the owner requirement that tests/ stay out of the repo) and
     internal agent notes. Consumers and contributors should read
     README.md / readme/ / documents/ instead. It is kept in-tree only
     as the owner's design record. -->

## MTA:SA / Lua 5.1 / DX9 — Retained-mode UI engine

# 0. РОЛЬ И ЦЕЛЬ

Ты — Principal Lua 5.1 / MTA:SA / DX9 engineer + UI framework architect.

Проект: `github.com/acc-holo-dev/mta-dx-ui` (DXUI — retained-mode UI движок
для MTA:SA). Текущее состояние — V3 (ядро хорошее, «обвязка сырая»).
Задача: довести проект до **РЕЛИЗНОГО V4** — не переписать ядро, а
превратить полуфабрикат в законченный продукт: рабочие Translate/Theme/Edit/
Settings уровня DGS, перестроенные шейдеры и скругления, единая архитектура
имен, комментарии строго в LuaCATS, правильная структура репозитория,
прокачанный demo-ресурс, локальная wiki и полировка.

Ключевые источники (уже изучены, зафиксированы в `tests/notes/`):
- **Аудит V3**: `tests/notes/v4-audit-design.md` — все баги и решения.
- **DGS v3.522** (Thisdp): исследование API переведено в §6 — берём лучшие
  идеи (live language switch, style cascade, placeHolder/caret/masked
  свойства Edit, roundrect-шейдер с per-corner радиусами), НЕ копируем
  архитектуру (DGS — element-based immediate, DXUI — retained с деревом).
- **LuaCATS / lua-language-server**: `tests/notes/luacats-style.md` —
  точный синтаксис аннотаций. Только `---` три тире; `---@class`,
  `---@field`, `---@param`, `---@return`, `---@alias`, `---@see`,
  `---@private`. Никаких `--[[ file — DXUI Vn ]]` баннеров.

# 1. ЖЁСТКИЕ ПРАВИЛА

1. **Lua 5.1 строго** (MTA:SA): нет `goto`, `math.pow` только если он есть в
   5.1 (есть), `unpack` глобальный (есть), никакой 5.2+ лексики.
2. **Каждая фаза заканчивается зелёным** прогоном
   `tests\bin\lua5.1.exe tests\run.lua` — все сьюты + luac5.1 -p синтаксис
   гейт. Сьюты в `tests/` (gitignored, локально у агента).
3. **meta.xml = единственный источник порядка загрузки**; раннер парсит его.
4. **Тесты не в релизе**: `tests/` в `.gitignore` (требование владельца).
5. **Комментарии = только LuaCATS** (`---`). Никаких заголовков файла, ни
   одного указания версии/ресурса. Обычные `--` только «почему», своей
   строкой сверху. Проверка: ни одного `--[[` в `source/`.
6. **MTA API только в** `render/backend_mta.lua` + `init.lua` (+ мягкие
   guards `if dx… then` в resources/manager — как сейчас). Ядро — чистый
   Lua, загружается headless.
7. **Никаких вторых механик**: если механизм уже есть (dirty-флаги, владелец
   owner, пул списков, шина событий, Anim-менеджер) — переиспользовать его.
8. **Никаких спекулятивных фич**: каждый пункт этого PROMT либо реализуется,
   либо явно помечается в финальном отчёте как отложенный.
9. **Порядок**: understand → decide → structure → implement → verify →
   document. Документация после кода, но в том же релизе.
10. **Ветка main**: каждая фаза — один коммит с внятным сообщением.

# 2. СТРУКТУРА РЕПОЗИТОРИЯ V4

```
./
├── source/                     # движок (клиент)
│   ├── settings.lua            # ПЕРЕНЕСЁН из source/client/ (владелец)
│   ├── core/values.lua, node.lua, widget.lua, part.lua
│   ├── text/text.lua
│   ├── translate.lua
│   ├── style/tokens.lua, theme.lua, themes.lua   # themes = встроенные пресеты
│   ├── animation/easing.lua, animation.lua
│   ├── resources/manager.lua
│   ├── layout/dimension.lua, flex.lua, layout.lua
│   ├── render/render_list.lua, state.lua, renderer.lua,
│   │        effects.lua, backend_mta.lua, pass.lua
│   ├── input/events.lua, hit_test.lua, dispatcher.lua
│   ├── api/runtime.lua, ui.lua, exports.lua, diagnostics.lua
│   ├── widgets/*.lua           # 17 виджетов + builders
│   └── init.lua                # MTA-glue, грузится ПОСЛЕДНИМ
├── demo/                       # автономный демо-ресурс: скопировал → запустил
│   ├── meta.xml                # <include resource="dxui"/> + client.lua
│   └── client.lua              # прокаченный showcase (только публичный API)
├── documents/                  # локальная wiki (статический HTML-сайт)
│   ├── index.html, styles.css, nav.js, search.js, страницы (см. §9)
├── readme/                     # человеческие доки репозитория
│   ├── ARCHITECTURE.md         # карта архитектуры V4 (+ выжимка решений)
│   └── CODE_STYLE.md           # LuaCATS-конвенция + правила кода V4
├── tests/                      # GITIGNORED: bin/lua5.1.exe, run.lua,
│   │                           # harness.lua, suites/, notes/ (агентская память)
├── meta.xml
├── README.md                   # лицо продукта (V4)
├── .luarc.json                 # LuaLS настройки: runtime 5.1, globals MTA
└── PROMT.md                    # этот план
```

Удаляется: `readme/ai/` (история → `tests/notes/legacy/`), `readme/examples/`
(→ demo/), `readme/tests/` (→ tests/), `readme/documents/ADR.md`
(живые решения вливаются в ARCHITECTURE.md; исторический лог не нужен).

# 3. ФАЗОВЫЙ ПЛАН (каждая фаза = коммит + зелёные тесты)

## P0 — Реструктуризация
- `source/client/settings.lua` → `source/settings.lua`; meta.xml порядок
  обновить; `runtime.lua` load-путь из тестов больше не хардкодит список
  (раннер уже парсит meta.xml — уже сделано в этой сессии).
- git mv demo/, tests/ (gitignore), удалить readme/{ai,examples,tests},
  перенести ADR-выжимку.
- Сьюты портированы в tests/suites/ (уже: core/style/basic/composite/api/
  perf/boot, 260 ok).
- Гейт: 260/0 + все пути в meta.xml существуют.

## P1 — Settings V4 («настроки для реального использования»)
- `source/settings.lua`: каждый ключ ДОЛЖЕН потребляться движком:
  - `dev` → config.dev (есть);
  - `errorPolicy` → потребляется DXUI._warn / ошибками ("error"|"warn"|"ignore");
  - `defaultTheme` = "light" → активация при старте (init.lua) и в applySettings;
  - `designResolution` → дефолт design для новых UI-инстансов;
  - `defaults.font` → дефолтный шрифт текстовых примитивов;
  - `defaults.animationDuration/Easing` → Anim (есть);
  - `defaults.caretBlinkInterval` → Edit (P5);
  - `defaults.scrollWheelStep` → ScrollPanel/GridList;
  - `performance.screenCulling` → pass (есть);
  - `performance.maxInteractiveScan` → hit-test cap (внедрить);
  - `performance.renderPriority` → приоритет addEventHandler onClientRender;
  - `resourcePolicy.autoRelease` → releaseResource при stop (внедрить);
- API: `DXUI.applySettings(t)` merge + `ui:applySettings` shortcut.
- Гейт: новый сьют `settings` — каждый ключ проверен в поведении.

## P2 — Translate V4 (по образцу DGS Multi Language)
- Словари: `ui:addLocale(lang, dict)` / `DXUI.addLocale` (есть) +
  `ui:addTranslation` алиас нет — одно имя: `addLocale`.
- **`textKey` — реальное свойство Widget** (объявлено в spec): присвоение
  `btn.textKey = "menu.save"` биндит и сразу применяет; смена локали
  переприменяет всем биндам. Старый `:setTextKey(key, prop)` остаётся
  (метод вызывает свойство).
- `ui:tr(key, ...)` — публичный шорткат; подстановка `%1..%N` (есть,
  мульти-цифровые + литеральный `%` в значениях — тестами закреплено).
- Цепочка фолбэка: точная локаль → базовая (`ru-RU`→`ru`) → ключ как есть.
- **Пер-UI локаль**: `ui:setLocale(lang)` — инстанс может отличаться от
  глобальной (DXUI.setLocale — глобаль по умолчанию). Виджет хранит
  контекст → applyTranslation берёт локаль инстанса, иначе глобальную.
- Живая смена: setLocale → re-apply всем живым биндам (есть) + слабые
  ссылки + игнор уничтоженных (есть). Событие `onLocaleChange` на UI.
- Гейт: сьют `translate` — textKey-свойство, фолбэк, пер-UI локаль, live switch.

## P3 — Theme V4 (стиль-система уровня DGS + лучше)
- **Реальный `extends`**: tokens + components глубоко мержатся по цепочке
  (child перекрывает точечно; таблицы мержатся, скаляры заменяются).
  Убрать дубль `Theme.current`/`_currentName` (одно поле истины).
- **Встроенные темы** (`source/style/themes.lua`, грузится после defaults):
  `light` (дефолт, сегодняшняя Fluent-Lite), `dark`, `green` и density-
  варианты: `light-compact`, `dark-compact`, `green-full` … = тема
  {tokens.color.*} × {tokens.spacing.*: compact|normal|full} — паддинги
  компонентов берут `@spacing.control` и т.п. Итог: минимум 6 пресетов.
- **Ремонт бага монтирования**: повторное применение стиля при attach
  (`_setContextRecursive` → `_applyStyleState`) — нода, созданная до смены
  темы, при монтировании получает актуальную тему.
- **Кастомные темы из ресурса потребителя**: `ui:defineTheme(name, tbl)` +
  `ui:setTheme(name|tbl)` (tbl → анонимная тема + activate). Живая смена
  пере-применяет ко ВСЕМ смонтированным виджетам (лучше DGS — там смена
  стиля НЕ пере-красит созданные виджеты).
- **Ассеты в темах**: значения-токены `texture:<path>` → DXUI.texture при
  компиляции; `font:<path>:<size>` → DXUI.font. (кэш resources, headless —
  passthrough как сейчас).
- **Переходы состояний (opt-in)**: компонент может объявить
  `transition = { duration = 150, easing = "out" }` — смена state у ЖИВОГО
  нода анимирует числовые/цветовые свойства через Anim (цвета —
  поканально; конструктор/смена темы — мгновенно). Нет объявления —
  мгновенно, как сейчас.
- Гейт: сьют `theme` — extends-мерж, density-токены, live switch, кастом из
  таблицы, mount-ремонт, transition (есть/нет), ownership-guard не сломан.

## P4 — Render & Rounded V4 (полная перестройка шейдеров/скруглений)
- **Один шейдер на эффект** (rounded / blur / mask) — экземпляры не
  плодятся от размеров; параметры ставятся на draw с дедупликацией
  подряд идущих одинаковых (backend хранит last-params).
- **SDF-rounded шейдер с бордером в ОДНОМ draw**: float4 gRadius
  (per-corner!), float gBorderWidth, float4 gFillColor, float4
  gBorderColor. dist>0 discard; dist>-bw → border; иначе fill. AA через
  smoothstep 1px (ps_2_0). Поддержка `radius = n | {lt,rt,rb,lb}`.
- Item-форма: `rrect { x,y,w,h, radius (число|таблица), fill, border,
  borderWidth }` — один item на скруглённый бордер-виджет (было 2 draws).
- **`borderWidth` — свойство виджетов** (default 1, themeable) вместо
  хардкода 1 везде.
- Удалить: таблицы-эффекты округления (`Effects.round` кэш), identity-dedup
  эффектов, `Renderer:resolveEffect` (встроить в image-эмит), vestigial
  `Part.themeRole`. RT-группы (clip/blur/mask) остаются как есть.
- Headless: без шейдеров → flat rect, но ITEM несёт полный набор полей —
  тестовый backend верифицирует структуру (радиус, бордер, цвета).
- Гейт: новый сьют `render` (item shape), perf-suite зелёный, старые сьюты
  зелёные.

## P5 — Edit V4 (каретка, placeholder — по мотивам DGS placeHolder/caret)
Свойства (имена DGS-паритетные, camelCase):
- `placeholder`, `placeholderColor`, `placeholderVisibleWhenFocused`
  (default false — как DGS: плейсхолдер исчезает при фокусе, каретка видна
  СРАЗУ даже на пустом тексте);
- `caret` (позиция), `caretColor`, `caretWidth` (DGS caretThick),
  `caretMode = "blink"|"solid"|"off"` (blink default), `caretBlinkInterval`
  (default = settings.defaults.caretBlinkInterval = 500мс, как у DGS);
- мигание — по кадру из clock через **overlay-хук** (не таймер! не
  инвалидирует кэшированный render list; 1 draw когда видим);
- `maxLength`, `readOnly`, `masked`, `maskChar` (default `"*"`),
  `alignment` ("left"|"center"), `selectionFrom` + `selectionColor`
  (shift+Left/Right/Home/End, Backspace/Delete по селекции);
- клик ставит каретку по символу (обратный charX — бинарный поиск), Escape
  снимает фокус (починить враньё доков V3), текст скроллится чтобы каретка
  была видна при переполнении;
- `change`/`submit` события (есть).
Гейт: сьют `edit` — все режимы каретки, placeholder-логика, masked,
maxLength, readOnly, selection, click-position, escape, submit.

## P6 — Window V4 (drag + close, фикс модалок)
- `draggable` (default true): drag через header-part (dispatcher drag);
- **closeButton part** (реальный Button-part, `closeButtonText = "×"`,
  themeable) — клик эмитит `close`; свойство `closeButtonVisible`;
- Фикс стека модалок: `Dispatcher:closeModal(node)` удаляет ИМЕННО этот
  нода (не верхний);
- Tooltip:attach больше не трогает zIndex цели (починить).
Гейт: сьют composite дополнен (drag двигает окно, close-клик, стек).

## P7 — Унификация имён (единая архитектура кода)
- `DXUI.EASING` → `DXUI.Easing`; `DXUI.Anim` остаётся; убрать `DXUI._t`,
  `DXUI.Values`; `Dispatcher:key(keyName, isDown)`;
- pass.lua: имена фаз collect/sort/emitNode/emitGroupContents;
  `tx_is_separator`→`isSeparator`; `destroyIfElement(v)` без пустого `_`;
- **Фабрики ui:* генерируются из реестра `DXUI.Widgets`** (убрать
  хардкод списка — появится `ui:radiogroup`);
- все виджеты: `_build` до `Builders.register`; `container()` — единый
  accessor контент-парта у всех композитов;
- TabPanel: страницы парентятся в content-part (не в корень tabpanel).
Гейт: сьют api обновлён (radiogroup factory, переименования), все зелёные.

## P8 — Комментарии → LuaCATS по ВСЕМУ source/
- По каждому файлу: убрать баннеры `--[[ ]]`; модульная шапка `---`;
  `---@class DXUI.<Name>` + `---@field` на публичных неймспейсах;
  `---@param/@return` на всех функциях; `---@alias` для енумов
  (состояния, caretMode, dimensions); `---@private` на внутренних;
  inline `--` только «почему».
- `.luarc.json` в корень: runtime 5.1, castNumberToInteger, diagnostics
  globals для MTA.
- Гейт: `grep '\-\-\[\[' source/` пусто; luac -p зелёный; тесты зелёные
  (комменты не меняют поведение).

## P9 — init.lua полировка (MTA-glue)
- Один onClientRender handler (тик + viewport-check вместе);
- `getCursorPosition` guard (латентный краш wheel-пути);
- renderPriority из settings; тест wheel в сьюте boot.
Гейт: boot-сьют + новый wheel-тест.

## P10 — demo/ (автономный ресурс)
- meta.xml: include dxui; client.lua: showcase ВСЕГО: окна+drag+close,
  кнопки/чекбоксы/радио-группа, slider→progress, edit со всеми
  режимами каретки + masked + placeholder, gridlist, scrollpanel,
  tabpanel, combobox, contextmenu, modal, tooltip, анимации, переключатель
  тем (light/dark/green × compact), живая смена языка ru/en, панель
  настроек. Только публичный API, никаких DXUI.* внутренних.
Гейт: luac -p + ручная проверка соответствия API (тестами — где можно).

## P11 — documents/ wiki + readme/ + README.md
- Wiki: статический HTML-сайт (styles.css, nav.js, search.js c встроенным
  индексом; file:// без сервера): index, quickstart, concepts (node/
  properties/parts/events), widgets-референс (все, с таблицами свойств/
  методов/событий/примерами), theme, translate, edit, settings, layout,
  animation, render, diagnostics, faq, migration (V3→V4).
- readme/ARCHITECTURE.md (V4) + readme/CODE_STYLE.md (LuaCATS-редакция).
- README.md — лицо продукта: что это, быстрый старт, фичи, скрин-структура,
  миграция V3→V4 (все BREAKING rename списком).
Гейт: все ссылки валидны, примеры кода соответствуют реальному API
(сверка по сьютам), файлы открываются file://.

## P12 — Финальный свип
- Полный прогон тестов, luac -p по всем скриптам, grep-гейты
  (баннеры, TODO, мусор), git status чистый, все фазы закоммичены.
- Финальный отчёт владельцу: что сделано/отложено, как проверить.

# 4. ПАРКЕТ API (публичная поверхность V4 — фиксируется сьютом api)

- `exports.dxui:getUI(name?, opts?)` → UI-хэндл (per-resource владение).
- UI: фабрики виджетов (реестр) + `ui:widget(name)` + value-фабрики
  `color/percent/auto/fill/texture/font/shader` + `add/remove` +
  `tr/addLocale/setLocale/getLocale` + `defineTheme/setTheme` +
  `applySettings` + `setViewport/tick/mouse*/scroll/key/character/destroy`.
- Node/Widget: свойства (props), `on/off/emit`, `animate`, `destroy`,
  `setState/getState`, `setPosition/setSize/setVisible/show/hide/
  setEnabled/setZIndex/setOpacity/setMargin/setPadding/setAnchor/
  setLayer/setMode`, `addChild/removeFromParent`, `setPart/getPart`,
  `bringToFront/sendToBack`, `textKey` (P2).
- События: click/press/release/mousedown/mouseup/hover-start/hover-end/
  drag-start/drag-move/drag-end/scroll/key/focus/blur/change/submit/
  select/popup-close/close/localeChange + DXUI.STOP.
- DXUI-глобали: DXUI.tr/addLocale/setLocale/getLocale, DXUI.Theme.*
  (define/activate/setTheme/list/getCurrent), DXUI.Tokens.*,
  DXUI.Settings + applySettings, DXUI.Diagnostics.*, DXUI.getUI,
  DXUI.releaseResource, DXUI.bootstrap.
- BREAKING V3→V4 (журнал миграции в README): `cursor`→`caret` (Edit),
  `DXUI.EASING`→`DXUI.Easing`, фабрики из реестра (+radiogroup),
  `Theme.getComponentStyle` контракт rrect-итема, тема `default`→`light`.

# 5. DGS-ПАРИТЕТ (что взяли — проверено по исходникам DGS v3.522)

| DGS | DXUI V4 |
|---|---|
| dgsSetTranslationTable + авто-attach + live switch | addLocale/setLocale + textKey-свойство + live re-apply (лучше: пере-красит живые виджеты) |
| словари: имя → таблица | локаль → таблица + per-UI локаль (DGS не умеет пер-инстанс язык) |
| styleSettings.txt + dgsAddStyle/dgsSetStyle из ресурса | ui:defineTheme/ui:setTheme(name|table), themes.lua встроенные, deep-merge extends (DGS: wholesale) |
| style живой смена НЕ перекрашивает созданные | Theme.activate перекрашивает всё дерево (mount-fix P3) |
| placeHolder/caretPos/caretThick/masked/maxLength/readOnly | placeholder/caret/caretWidth/masked/maskChar/maxLength/readOnly + caretMode (у DGS — фиксированный таймер 500мс) |
| dgsCreateRoundRect (shader, per-corner, border, AA) | SDF per-corner + border в один draw, ps_2_0, без плагина |
| dgsAnimTo (люби-свойство) | animate (числа/цвета поканально) |
| dgsSetLayer/BringToFront | node.layer/zIndex/bringToFront |
| dgsAddMoveHandler (drag окна) | Window.draggable + header-part |
| dgsSetSystemFont | settings.defaults.font |
| renderPriority | settings.performance.renderPriority |

# 6. Definition of Done

- [ ] Все фазы P0–P12 выполнены, каждая закоммичена.
- [ ] tests: все сьюты зелёные (старые 260 + новые settings/translate/theme/
      render/edit — суммарно 320+), luac -p чист.
- [ ] Ни одного `--[[` баннера в source/; каждый файл начинается с `---`
      модульной шапки; LuaCATS на всех функциях.
- [ ] demo/ — копипаст-ресурс: meta.xml + client.lua, только public API.
- [ ] documents/ — wiki открывается локально, страницы полные.
- [ ] README.md/readme/ — актуальны, содержат миграцию V3→V4.
- [ ] tests/ — gitignored, в релиз не попадает.
- [ ] Рабочее дерево чистое, история коммитов по фазам.

# 7. ПРИОРИТЕТ ПОЛИРОВКИ

Если время/объём давит — порядок сохранения: корректность > тесты >
документация API (wiki) > demo-прокачка > переходы состояний (transition)
> селекция в Edit. Отложенное честно фиксируется в финальном отчёте
и в tests/notes/deferred.md.