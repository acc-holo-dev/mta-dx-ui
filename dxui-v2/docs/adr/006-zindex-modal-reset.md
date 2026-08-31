# ADR-006: zIndex Reset on Modal Disable

## Context
Window:setModal(true) устанавливал node.zIndex = 1, чтобы окно было выше overlay внутри MODAL-слоя. При setModal(false) zIndex не сбрасывался, и окно "выпрыгивало" над всеми BASE-соседями.

## Decision
В setModal(false) добавлено self.zIndex = 0 (сброс к дефолту).

## Consequences
+ После отключения modal окно сортируется по id вместе с другими BASE-узлами.
+ Нет неожиданного перекрытия соседних виджетов.

## Status
Accepted, implemented.
