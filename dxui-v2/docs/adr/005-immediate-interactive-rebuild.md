# ADR-005: Immediate Interactive List Rebuild on Node Destroy

## Context
При уничтожении узла interactiveList перестраивался только по dirty-флагу в следующем кадре. Если между destroy и следующим renderFrame вызывались события (mousedown), в списке оставался уничтоженный узел с nil width/height, что ломало hit-test (арифметика на nil).

## Decision
Context:_onNodeDestroyed() немедленно вызывает self:_rebuildInteractiveList(). Это гарантирует, что interactiveList всегда согласован с живым деревом.

## Consequences
+ Исключены stale entries в interactiveList.
+ Hit-test не падает на уничтоженных узлах.
− O(N) перестройка при каждом destroy (cold path, приемлемо).

## Status
Accepted, implemented.
