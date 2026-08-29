# ADR Index

Архитектурные решения DXUI. Каждое ADR — контекст, решение, последствия.

| ADR | Тема |
|-----|------|
| [ADR-001](ADR-001.md) | Dirty-bitmask invalidation: один бит на подсистему |
| [ADR-002](ADR-002.md) | SoA (Structure of Arrays) вместо AoS |
| [ADR-003](ADR-003.md) | Dirty-очередь за кадр: dirtyList без дублей |
| [ADR-004](ADR-004.md) | RT-кэширование: FLAG_STATIC / FLAG_PINNED_RT |
| [ADR-005](ADR-005.md) | Handle/ID система: id стабильны, slot двигаются |
| [ADR-006](ADR-006.md) | Числовые константы в hot path, строки — только в публичном API |
| [ADR-007](ADR-007.md) | Layout: local→world каскад, LAY_ABS/REL/CENTER + anchor + margin |
| [ADR-008](ADR-008.md) | Anchors: 9 точек привязки, численные |
| [ADR-009](ADR-009.md) | Clip/Opacity/Blur: dirty-driven clip-глубина + регион, driver state |
| [ADR-010](ADR-010.md) | Animation: AnimationPool (SoA) + единый tick, без per-node таймеров |
| [ADR-011](ADR-011.md) | RT Manager: единый владелец offscreen RT, пул по размерам, clip-стек |
| [ADR-012](ADR-012.md) | M9 Optimization: slot dirtyList, итеративный layout, DIRTY_POS |
| [ADR-013](ADR-013.md) | M10 Production: Profiler OFF by default, zero overhead в проде |
| [ADR-014](ADR-014.md) | M10 Debug-система: инспекция дерева, bounds-overlay, dirty-визуализация |
