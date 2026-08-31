# ADR-003: _effLayer Computed at Collect Time (vs Child Mutation)

## Context
При смене parent слой ребёнка наследовался от родителя через мутацию child.layer в setParent(). Это приводило к "застреванию" слоя: при отключении modal у Window дети оставались в MODAL, потому что их layer не сбрасывался.

## Decision
V2 отказался от мутации child.layer в setParent(). Вместо этого _effLayer вычисляется рекурсивно в _collectInteractive()/_collectRenderable() и записывается через rawset(node, "_effLayer", effLayer). Сортировка использует _effLayer, а не layer.

## Consequences
+ Родитель может менять layer (modal, popup), а дети автоматически получают эффективный слой без side effects на их собственные layer.
+ Нет риска "застрять" в MODAL после setModal(false).
− Небольшой оверхед O(N) на вычисление _effLayer при каждой перестройке списка.

## Status
Accepted, implemented.
