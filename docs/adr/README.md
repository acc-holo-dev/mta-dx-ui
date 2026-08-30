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
| [ADR-015](ADR-015.md) | M11: политика версии Lua — тесты только под 5.1 (lupa.lua51), запрет 5.2+ синтаксиса |
| [ADR-016](ADR-016.md) | M12: Window 2.0 — composite-proxy, drag-capture в Dispatcher, z-order, preventable close |
| [ADR-017](ADR-017.md) | M13: ScrollPanel — composite + wheel (bindKey) + drag scrollbar + virtualization + HitTest clip-aware + zero-size RECT skip |
| [ADR-018](ADR-018.md) | M14: Edit — text input + focus system + keyboard (onClientKey → focusedId) |
| [ADR-019](ADR-019.md) | M15: Edit 2.0 — selection (drag-select) + clipboard + multiline + placeholder render |
| [ADR-020](ADR-020.md) | M16: Modal — overlay + focus lock + input trap + наследование layer |
| [ADR-021](ADR-021.md) | M17: Tooltip + Popup + ContextMenu — hover-подсказка, dismiss по клику вне |
| [ADR-022](ADR-022.md) | M18: CheckBox + RadioButton + Slider + ProgressBar — input/display-контролы |
| [ADR-023](ADR-023.md) | M19: ComboBox + TabPanel + GridList — контейнерные виджеты (popup/scroll переиспользование) |
| [ADR-024](ADR-024.md) | M20: polish — ANIM_OPACITY (fade), Kernel:schedule (tooltip delay), modal auto-focus, slider click-to-jump/vertical |
