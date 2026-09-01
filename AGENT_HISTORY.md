# AGENT_HISTORY.md — DXUI V3 handoff (complete, round 8)

> Цель файла: если вы — новый агент и получили задачу «продолжить работу над
> mta-dx-ui», сложите этот файл рядом с PROMT.md (пользователь склеит их в один
> промпт) и работайте по нему. Здесь: точное состояние репозитория, что сделано
> по PROMT.md, что НЕ сделано, как запускать тесты, какие ограничения среды и
> что делать дальше. Раунды ниже = итерации основного агента в одном сеансе.

---

## 0. Проект и репозиторий

- **Workspace**: `D:\File\Developer\Project\mta-dx-ui`
- **Git**: `main`, remote `origin = https://github.com/acc-holo-dev/mta-dx-ui.git`
- **Последний коммит**: `341e3c9` (round 8) — запушен в GitHub
  (`2411237..341e3c9 main -> main`). Рабочее дерево чистое (0 изменений).
- **Что это**: DXUI V3 — retained-mode UI-фреймворк для MTA:SA (Lua 5.1 /
  DX9). Полная перезапись V2 по мастер-промпту `PROMT.md`.
- **Запись прогресса (память)**: OpenViking
  `viking://user/default/memories/entities/software_project/mta-dx-ui_v3_notes.md`
  — там же история раундов 1–8.

## 1. Статус PROMT.md — фазы

| Фаза | Статус | Где |
|------|--------|-----|
| Аудит V2 | ✅ | `readme/ai/001-v2-audit.md` |
| Дизайн V3 + структура | ✅ | `readme/ai/002-v3-contracts.md` (контракты, авторитетные), `readme/documents/ARCHITECTURE.md` |
| CORE (values/node/widget/part/settings) | ✅ | `source/client/core/*` |
| Подсистемы (text/translation/easing/animation/manager) | ✅ | `source/client/{text,translation,animation/easing,animation/animation,resources}` |
| STYLE (tokens/theme/defaults) | ✅ | `source/client/style/*` |
| LAYOUT (dimension/flex/layout) | ✅ | `source/client/layout/*` |
| RENDER (list/state/renderer/effects/backend_mta/pass) | ✅ | `source/client/render/*` |
| INPUT (events/hit_test/dispatcher) | ✅ | `source/client/input/*` |
| API (runtime/ui/exports/diagnostics) | ✅ | `source/client/api/*` |
| WIDGETS (18 шт.) | ✅ | `source/client/widgets/*` |
| Интеграция (init.lua bootstrap, meta.xml) | ✅ | `source/client/init.lua`, `meta.xml` |
| Проверка: headless-тесты | ✅ | `readme/tests/` — **245 ассертов, 0 failed** |
| Проверка: живой MTA | ⚠️ НЕ СДЕЛАНО | только fake-MTA боот (smoke_boot). Нужен реальный клиент MTA |
| Перф-замеры | ✅ (headless) | `readme/ai/004-v3-perf.md` |
| Документация/примеры/ADR/README | ✅ | `readme/documents/`, `readme/examples/`, README/ARCHITECTURE (V3), ADR-001..009 |
| Самопроверка §82/§85/§86 | ✅ | `readme/ai/003-v3-verification.md` |

**Главный незакрытый пункт**: реальная проверка в MTA:SA-клиенте (dx-бэкенд,
живой ввод). Всё остальное по PROMT.md закрыто; код написан, контракты
выполнены, тесты зелёные.

## 2. Что случилось в последние полчаса (прерывание) — раунд 8

Начал раунд 8 (перф-ресурс + API-регрессия), нашёл и починил:

1. **БАГ (движок, runtime.lua)**: baseline zero-work синкался ДО проходов в
   том же тике → ложное срабатывание assert «layout ran without layoutDirty»
   на первом грязном кадре после `enableZeroWork`. Исправлено: синк
   `_prevLayoutRuns/_prevRebuilds` перенесён в КОНЕЦ tick (после проходов).
2. **БАГ (движок, node.lua)**: `Node:on(eventName, fn, id)` не передавал id в
   `Events.add` — `removeForOwner` не работал через node:on (и id "dxui-states"
   от wireStates не попадали в реестр). Исправлено: id пробрасывается.
3. **Доработка API (node.lua)**: `offProperty(key)` без fn теперь снимает ВСЕ
   слушатели пропа (как node:off(name)).
4. Исправления в ТЕСТАХ (не движок): `color(255,37,99)` = `0xFFFF2563`
   (alpha first в 0xAARRGGBB — мои ожидания были неверны); anchor — валидны
   только `tl/tc/tr/ml/mc/mr/bl/bc/br` («center» невалиден); сигнатура
   `Part.declare(class, names)`; `onProperty(fn(value, old, node))` — value
   ПЕРВЫЙ аргумент.
5. Новые сьюты: `smoke_api.lua` (100) и `smoke_perf.lua` (19) + отчёт
   `readme/ai/004-v3-perf.md`. Итог по всем сьютам: **245/245**.

Изменения закоммичены (`341e3c9`) и запушены — прерывание НЕ оставило
незавершённого состояния.

## 3. Как запускать тесты (обязательно перед любыми изменениями)

```bash
cd /d D:\File\Developer\Project\mta-dx-ui
pip install lupa          # Lua 5.5 embed для Python (движок теста)
python readme/tests/run.py            # все 7 сьютов
python readme/tests/run.py api perf   # выборочно
```

- Каждый сьют — свежий `LuaRuntime(unpack_returned_tuples=True)`, движок
  грузится в порядке `meta.xml` (список в `run.py → LOAD_ORDER`, 49 файлов,
  `init.lua` — только в boot под фейковым MTA).
- Харнесс даёт глобалы: `DXUI`, `eq(got,want,name)`, `expect(cond,name)`,
  `Backend()` (наблюдаемый бэкенд со счётчиками). Exit code 0 = зелёно.
- ВАЖНО: тесты вызывают движок так, как его применит MTA — добавляйте узлы,
  потом `ui:tick()` (layout) ДО ввода; события: `ui:mouseMove/Down/Up/scroll/key`
  принимают SCREEN-координаты (маппятся в дизайн через viewport).

## 4. Архитектура (карта за 30 секунд)

```
meta.xml (порядок загрузки) → settings → core/{values,node,widget,part} →
translation, text → style/{tokens,theme,defaults} → animation, resources →
layout/{dimension,flex,layout} → render/{list,state,renderer,effects,
backend_mta,pass} → input/{events,hit_test,dispatcher} →
api/{runtime,ui,exports,diagnostics} → widgets/ (Builders.register) →
init.lua (MTA-клей, ПОСЛЕДНИЙ)
```

Ключевые контракты (все протестированы):
- **Один слой мутации**: `Node:_set(key, value, owner)`; owner =
  `user|theme|system`; theme-запись ставит `_themeApplied[key]`, любая
  другая — снимает; style-apply не трогает user/system свойства.
- **Грязные флаги по категориям**: layout/render/order/interactive → 4 булевых
  на инстансе; `tick()` гоняет проход только по своему флагу
  (`Diagnostics.enableZeroWork` доказывает это ассертами).
- **Рендер**: персистентный плоский пул-список пересобирается ТОЛЬКО по
  dirty; `draw()` рисует кеш КАЖДЫЙ кадр (idle = 0 rebuild, не 0 draw).
  Сортировка при rebuild: (effLayer, zIndex, _id).
- **Тема**: компилированные карты на (theme, component, styleKey); цепочка
  variant(node.style) > component base > fallback > дефолты класса; токены
  резолвятся итеративно (cap 8, cycle-guard); `activate()` → reapplyAll по
  `DXUI._uis` (дерево ДОЛЖНО быть зарегистрировано — getUI; nodes вне дерева
  надо `_applyStyleState()` вручную).
- **Layout**: `Dimension.compile → {k=px|pct|auto|fill}`; `layoutMode`
  relative = x/y ДРОБИ (0..1), absolute = пиксели; `autoSize` меряет ТОЛЬКО
  свободный размер (нет владельца И raw nil/0 — дефолты пропсов это 0, не
  nil!); engine-размеры пишутся `_set(...,"system")` с same-value guard.
- **Ввод**: `Events.bc` бабблится target→ancestors (снапшот на уровень,
  `DXUI.STOP`); hit-test по флагам (interactive/focusable); Диспетчер владеет
  hover/focus/pressed/drag(6px)/modal stack/popups; click эмитится
  `(button, x, y, origin)` — 4-й аргумент = точка НАЖАТИЯ.
- **MTA-изоляция**: `init.lua` + `render/backend_mta.lua` — единственные
  файлы с dx*/event глобалами; бэкенд и текст-измеритель инжектятся.

## 5. Что делать дальше (приоритет, по возвращении)

1. **Живой MTA-свEEP (главное)**: взять `meta.xml` + `source/`, собрать
   ресурс, запустить в клиенте (желательно на сервере с admin для чат-выводов).
   Чек-лист:
   - `export function getUI` в meta.xml + `<dependency>`; проверить
     `exports.dxui:getUI` из другого ресурса.
   - Рендер: клик/хoвер меняют состояние; текст (шрифты, кириллица через
     translation), картинки (dxCreateTexture), скролл, модалка, поп-апы.
   - Замерить `DXUI.Diagnostics.describe(ui)` / `idleRatio` в живом цикле.
   - Мини-баг: проверить `init.lua` ensureViewport при смене разрешения.
2. **Пример-ресурс**: `readme/examples/demo.lua` ссылается на
   `exports.dxui:getUI` — при живом тесте сделать работающий демо-ресурс
   (можно добавить `readme/examples/meta.xml`).
3. **Опционально-полировка** (НЕ блокеры, §86 — не делать «код ради кода»):
   - gridlist: ширины колонок/динамические строки, если понадобится.
   - Бенчмарк на реальном MTA (изменить 004 если цифры разойдутся).
4. **Если пользователь пришёл с новыми требованиями** — контракты уже в
   `readme/ai/002-v3-contracts.md`; изменение контракта = правка этого файла
   + тесты.

## 6. Ограничения среды (важно для продолжения)

- ОС Windows; PowerShell через `pwsh` (каждый вызов — свежий процесс, cwd не
  сохраняется, используйте workdir).
- Агент запускается по раундам goal (сейчас: goal-c6b61df3, round 8/15).
  Продолжайте, не перезапуская цель. Блокер не требуется (работа идёт).
- Lua-тесты: lupa-gives Lua 5.5 (`load(src)` для compile-check); движок строго
  Lua 5.1: НЕЛЬЗЯ goto, присваивание переменных generic-for, голые
  `X and Y()` как statement, голый `obj:method` без вызова. Тесты это ловят.
- Sub-agents исторически ненадёжны (зависали) — писать код напрямую.
- В этом окружении НЕТ MTA: живая проверка — только вручную пользователем.

## 7. Репозиторий / гигиена

- `.gitignore`/`.gitattributes` в порядке; старый V2 (`client/`, `docs/`,
  `examples/`, `tests/`, `ROADMAP.md`) удалён из git в раунде 6 (в истории
  видно как D). Новый код: `source/client/` (~49 файлов).
- Коммиты: стиль «round N: …»; перед коммитом — `python readme/tests/run.py`
  зелёный + `git status` чистый.
- Изменения в `meta.xml` (порядок скриптов) должны повторять `LOAD_ORDER` в
  `run.py` — иначе тесты потеряют соответствие.

## 8. Изменения по раундам (кратко)

| Р | сделано | commit |
|---|---------|--------|
| 1–2 | аудит V2 | — |
| 3 | структура+контракты+core+подсистемы | — |
| 4 | render/layout/input | — |
| 5 | dispatcher/api/init, интеграция | — |
| 6 | style+18 виджетов, meta.xml, удаление V2 | — |
| 7 | диагностика, boot-проверка, тест-ресурс, доки | `8b2a303` |
| 8 | api-регрессия, перф-контракт, фиксы zero-work/id | `341e3c9` |

Источники правды: `readme/ai/002-v3-contracts.md` (контракты),
`readme/ai/003-v3-verification.md` (журнал), `readme/ai/004-v3-perf.md`
(цифры), OpenViking-заметка (раунды 1–8).