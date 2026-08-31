# ADR-004: Style Ownership Guards (_themeApplied + _userSet)

## Context
Нужно различать "значение установлено пользователем" и "значение пришло из темы", чтобы переключение style не затирало ручные настройки.

## Decision
Введён механизм ownership:
- applyThemeDefaults() помечает поля флагом _themeApplied[key] = true.
- Если пользователь явно пишет свойство вне applyTheme, _set() помечает _userSet[key] = true.
- applyStyle(name) сбрасывает только те поля, которые были _themeApplied и не были _userSet.
- Флаг _applyingTheme подавляет _userSet во время bulk-применения стиля.

## Consequences
+ Ручные настройки цвета/шрифта сохраняются при смене style.
+ Тема может меняться динамически после создания виджета.
− Немного больше book-keeping в _set().

## Status
Accepted, implemented.
