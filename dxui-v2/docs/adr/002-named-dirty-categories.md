# ADR-002: Named Dirty Categories (vs Legacy Bitmask)

## Context
Legacy использовала битовые маски (0x091) для dirty-флагов. Это компактно, но нечитаемо и хрупко при добавлении новых категорий.

## Decision
V2 использует именованные строковые категории (DIRTY_LAYOUT, DIRTY_RENDER, DIRTY_INPUT, DIRTY_STYLE, DIRTY_CHILDREN, DIRTY_VISIBILITY). Внутри Context они хранятся в boolean-флагах node._dirty[name]; внешний API никогда не видит числовых констант.

## Consequences
+ Читаемость: _set() инвалидирует ровно те категории, которые объявлены в spec.invalidates.
+ Расширяемость: новая категория добавляется одной строкой.
− Массив _dirty немного тяжелее bitmask (несущественно для Lua).

## Status
Accepted, implemented.
