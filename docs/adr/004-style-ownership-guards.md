# ADR-004: Style Ownership Guards (_themeApplied + _userSet)

## Context
It is necessary to distinguish "value set by the user" from "value coming from the theme", so that switching styles does not overwrite manual settings.

## Decision
An ownership mechanism was introduced:
- applyThemeDefaults() marks fields with the flag _themeApplied[key] = true.
- If the user explicitly writes a property outside applyTheme, _set() marks _userSet[key] = true.
- applyStyle(name) resets only those fields that were _themeApplied and not _userSet.
- The flag _applyingTheme suppresses _userSet during bulk style application.

## Consequences
+ Manual color/font settings survive a style switch.
+ The theme can change dynamically after widget creation.
− Slightly more book-keeping in _set().

## Status
Accepted, implemented.
