# ADR-001: AoS Public Node Objects (vs SoA Internal Storage)

## Context
Legacy DXUI использовало SoA (structure-of-arrays) + slot-индексацию: виджеты читали данные из центральных массивов (s.worldX[slot], s.w[slot]). Это оптимизировало кэш-локальность, но делало API нечитаемым и требовало от авторов виджетов знания внутреннего представления.

## Decision
V2 перешёл на AoS (array-of-structures): публичный API — обычная Lua-таблица (node.x, node.width, node.color). Внутреннее состояние хранится в node._data (таблица полей) и контролируется единым mutation-слоем _set(). Runtime (layout, render, input) работает с публичными полями через метатаблицу или прямой доступ.

## Consequences
+ API понятен без знания internals.
+ Property-style и method-style сходятся в одном _set().
+ Widget-авторы пишут чистый Lua.
− Немного больше памяти на объект (приемлемо для Lua-таблиц).
− Потенциально меньшая кэш-локальность при массовой обработке (компенсируется плоскими списками для render/input).

## Status
Accepted, implemented.
