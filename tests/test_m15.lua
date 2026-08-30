--[[
    test_m15.lua -- Edit 2.0 (ADR-018/019): composite, ввод, спец-клавиши,
    selection, clipboard, multiline, placeholder, readonly, maxChars,
    публичный API (getText/setText/getSelection/...). Паттерн test_m12.
]]

dofile("loader.lua")

local Kernel = DXUI.Kernel
local C = DXUI.Constants
local passed, failed = 0, 0

local function check(name, cond)
    if cond then
        passed = passed + 1
        print("[OK]   " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name)
    end
end

local function newUI()
    local k = Kernel.new({
        setBlendMode = function() end,
        pushClip = function() end,
        popClip = function() end,
        setOpacity = function() end,
        setBlur = function() end,
        drawRect = function() end,
        drawImage = function() end,
        drawText = function() end,
    })
    local ui = DXUI.UI.new(k)
    k:setScreenSize(1280, 720)
    return k, ui
end

-- 1. Composite-структура: base + text + ph + cursor = 4 узла
do
    local k, ui = newUI()
    local before = k.storage.count
    local edit = ui:edit({ x = 0, y = 0, w = 100, h = 24 })
    check("edit: composite = 4 узла (base+text+ph+cursor)", k.storage.count - before == 4)
    check("edit: parts.text/ph/cursor живы",
        edit._parts.text:isAlive() and edit._parts.ph:isAlive() and edit._parts.cursor:isAlive())
    check("edit: parts.base == сам узел", edit._parts.base == edit)
    check("edit: focusables реестр (M20)", k.focusables[edit.id] == true)
end

-- 2. getText/setText roundtrip + cursor
do
    local k, ui = newUI()
    local edit = ui:edit()
    check("edit: getText пусто", edit:getText() == "")
    edit:setText("hello")
    check("edit: setText/getText", edit:getText() == "hello")
    check("edit: cursor в конце после setText", edit:getCursor() == 5)
    edit:setCursor(2)
    check("edit: setCursor/getCursor", edit:getCursor() == 2)
    edit:setCursor(999)
    check("edit: setCursor clamp к #text", edit:getCursor() == 5)
end

-- 3. Ввод текста через dispatcher (focus + EVENT_TEXT)
do
    local k, ui = newUI()
    local edit = ui:edit()
    k.dispatcher:setFocus(edit.id)
    check("edit: фокус установлен", k.dispatcher:getFocus() == edit.id)
    k.dispatcher:onKeyDown("a", "down", "", "a")
    k.dispatcher:onKeyDown("b", "down", "", "b")
    check("edit: ввод 'ab'", edit:getText() == "ab")
    check("edit: cursor после ввода", edit:getCursor() == 2)
end

-- 4. Backspace / Delete
do
    local k, ui = newUI()
    local edit = ui:edit()
    k.dispatcher:setFocus(edit.id)
    edit:setText("ab")
    edit:setCursor(2)
    k.dispatcher:onKeyDown("backspace", "down", "", nil)
    check("edit: backspace удалил 'b'", edit:getText() == "a")
    edit:setText("ab")
    edit:setCursor(0)
    k.dispatcher:onKeyDown("delete", "down", "", nil)
    check("edit: delete удалил 'a'", edit:getText() == "b")
end

-- 5. Навигация: arrow_l/r, home/end
do
    local k, ui = newUI()
    local edit = ui:edit()
    k.dispatcher:setFocus(edit.id)
    edit:setText("abc")
    edit:setCursor(3)
    k.dispatcher:onKeyDown("arrow_l", "down", "", nil)
    check("edit: arrow_l -> cursor 2", edit:getCursor() == 2)
    k.dispatcher:onKeyDown("home", "down", "", nil)
    check("edit: home -> cursor 0", edit:getCursor() == 0)
    k.dispatcher:onKeyDown("end", "down", "", nil)
    check("edit: end -> cursor 3", edit:getCursor() == 3)
end

-- 6. Selection: setSelection/getSelection + ctrl+a
do
    local k, ui = newUI()
    local edit = ui:edit()
    edit:setText("hello")
    edit:setSelection(1, 4)
    local s, e = edit:getSelection()
    check("edit: setSelection/getSelection (1,4)", s == 1 and e == 4)
    k.dispatcher:setFocus(edit.id)
    k.dispatcher:onKeyDown("a", "down", "ctrl", nil) -- select all
    local s2, e2 = edit:getSelection()
    check("edit: ctrl+a выделяет всё (0,5)", s2 == 0 and e2 == 5)
end

-- 7. Clipboard: copy / cut / paste
do
    local k, ui = newUI()
    local edit = ui:edit()
    k.dispatcher:setFocus(edit.id)
    edit:setText("hello")
    k.dispatcher:onKeyDown("a", "down", "ctrl", nil) -- select all
    k.dispatcher:onKeyDown("c", "down", "ctrl", nil) -- copy
    check("edit: ctrl+c скопировал 'hello'", k.clipboard == "hello")
    k.dispatcher:onKeyDown("arrow_r", "down", "", nil) -- collapse к концу
    k.dispatcher:onKeyDown("v", "down", "ctrl", nil)   -- paste
    check("edit: ctrl+v вставил в конец", edit:getText() == "hellohello")

    local edit2 = ui:edit()
    k.dispatcher:setFocus(edit2.id)
    edit2:setText("world")
    k.dispatcher:onKeyDown("a", "down", "ctrl", nil)
    k.dispatcher:onKeyDown("x", "down", "ctrl", nil) -- cut
    check("edit: ctrl+x вырезал", k.clipboard == "world" and edit2:getText() == "")
end

-- 8. Multiline: enter вставляет \n; single-line: onEnter
do
    local k, ui = newUI()
    local edit = ui:edit({ multiline = true })
    k.dispatcher:setFocus(edit.id)
    edit:setText("ab")
    k.dispatcher:onKeyDown("enter", "down", "", nil)
    check("edit: multiline enter -> 'ab\n'", edit:getText() == "ab\n")

    local entered = 0
    local edit2 = ui:edit({ onEnter = function() entered = entered + 1 end })
    k.dispatcher:setFocus(edit2.id)
    k.dispatcher:onKeyDown("enter", "down", "", nil)
    check("edit: single-line enter -> onEnter", entered == 1)
end

-- 9. Placeholder
do
    local k, ui = newUI()
    local edit = ui:edit({ placeholder = "Type..." })
    check("edit: placeholder виден (пусто, не в фокусе)", edit._parts.ph:isVisible())
    k.dispatcher:setFocus(edit.id)
    check("edit: placeholder скрыт в фокусе", not edit._parts.ph:isVisible())
end

-- 10. Readonly
do
    local k, ui = newUI()
    local edit = ui:edit({ readonly = true })
    k.dispatcher:setFocus(edit.id)
    k.dispatcher:onKeyDown("a", "down", "", "a")
    check("edit: readonly игнорирует ввод", edit:getText() == "")
    edit:setReadonly(false)
    k.dispatcher:onKeyDown("a", "down", "", "a")
    check("edit: setReadonly(false) принимает ввод", edit:getText() == "a")
end

-- 11. maxChars
do
    local k, ui = newUI()
    local edit = ui:edit({ maxLength = 3 })
    k.dispatcher:setFocus(edit.id)
    k.dispatcher:onKeyDown("a", "down", "", "a")
    k.dispatcher:onKeyDown("b", "down", "", "b")
    k.dispatcher:onKeyDown("c", "down", "", "c")
    k.dispatcher:onKeyDown("d", "down", "", "d")
    check("edit: maxChars обрезает до 3", edit:getText() == "abc")
end

-- 12. onChange колбэк
do
    local k, ui = newUI()
    local changes = 0
    local edit = ui:edit({ onChange = function() changes = changes + 1 end })
    k.dispatcher:setFocus(edit.id)
    k.dispatcher:onKeyDown("a", "down", "", "a")
    check("edit: onChange вызван", changes == 1)
end

-- 13. destroy: focusables очищен + пул освобождён
do
    local k, ui = newUI()
    local poolBefore = k.proxy.poolCount
    local edit = ui:edit()
    local id = edit.id
    k:destroy(edit)
    check("edit: destroy снял focusables", k.focusables[id] == nil)
    check("edit: destroy вернул >=4 proxy", k.proxy.poolCount - poolBefore >= 4)
end

print(string.format("test_m15: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
