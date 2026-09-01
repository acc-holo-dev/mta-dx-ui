--[[
    dispatcher.lua — DXUI V3

    Per-instance input state machine. Input arrives in DESIGN space (the
    runtime converts screen -> design before calling). The dispatcher owns
    the correlation state: hover, focus, pressed, drag, modal stack, popups.

    Events (emitted via the bubbling bus):
        hover-start / hover-end   (mouse entering/leaving a node)
        mousedown / mouseup       (raw press/release, bubbles)
        click                     (press+release on the same node, no drag)
        drag-start / drag-move / drag-end
        scroll                    (wheel; bubbles up to an Edit/ScrollPanel)
        key                       (focus target receives keys)
        focus / blur              (focusable nodes)

    Rules:
      - modal stack: while a modal is open, only nodes inside it receive
        input; opening a modal locks hover/focus to it.
      - popup management: any click outside current popups dismisses the
        topmost popup (popup nodes are tracked as they open).
      - drag: press starts a potential drag; movement beyond DRAG_THRESHOLD
        fires drag-start once and marks the press as a drag (click is then
        suppressed on release). Drag events route to the pressed node and
        bubble; capture ends on release.
]]

DXUI = DXUI or {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

-- design units
Dispatcher.DRAG_THRESHOLD = 6

--- Creates a fresh input state for an instance.
function Dispatcher.new(instance)
    return setmetatable({
        instance = instance,
        hover = nil,
        focus = nil,
        -- node under the pressed button
        pressed = nil,
        pressButton = nil,
        pressX = nil,
        pressY = nil,
        -- drag-start already fired
        dragging = false,
        -- movement exceeded threshold (suppresses click)
        dragged = false,
        -- open modal stack (topmost last)
        modals = {},
        -- open popups, topmost last
        popups = {},
    }, Dispatcher)
end

-- ---------------------------------------------------------------------
-- Modal + popup management
-- ---------------------------------------------------------------------

--- Opens a modal (blocks input to everything outside it, including lower
-- modals' areas). Returns the new modal depth.
function Dispatcher:openModal(node)
    local modals = self.modals
    if not modals then
        modals = {}
        self.modals = modals
    end
    modals[#modals + 1] = node
    self:setFocus(node)
    return #modals
end

--- Closes a modal. With `node`, removes THAT modal wherever it sits in the
--- stack (closing a mid-stack modal keeps the others intact); without one,
--- pops the topmost. Focus is released so the next topmost layer wins.
function Dispatcher:closeModal(node)
    local modals = self.modals or {}
    if #modals > 0 then
        if node ~= nil then
            for i = #modals, 1, -1 do
                if modals[i] == node then
                    table.remove(modals, i)
                end
            end
        else
            table.remove(modals)
        end
    end
    self:setFocus(nil)
end

--- Registers an open popup (its root). Outside clicks close popups.
function Dispatcher:openPopup(node)
    self.popups[#self.popups + 1] = node
end

--- Removes a popup from the open-popup list.
function Dispatcher:closePopup(node)
    for i = #self.popups, 1, -1 do
        if self.popups[i] == node then table.remove(self.popups, i) end
    end
end

--- Closes every open popup, emitting popup-close on each.
function Dispatcher:closeAllPopups()
    local popups = self.popups
    for i = #popups, 1, -1 do
        local p = popups[i]
        if p.emit then
            p:emit("popup-close")
        end
    end
    self.popups = {}
end

--- Whether `node` is reachable for input right now: not blocked by a
-- modal, and not outside an open popup chain.
function Dispatcher:reachable(node)
    local modals = self.modals
    if modals and #modals > 0 then
        local m = modals[#modals]
        local n = node
        while n do
            if n == m then return true end
            n = n._parent
        end
        return false
    end
    return true
end

-- ---------------------------------------------------------------------
-- Focus
-- ---------------------------------------------------------------------

--- Moves focus to node, emitting blur on the old target and focus on the new.
function Dispatcher:setFocus(node)
    if self.focus == node then return end
    local old = self.focus
    if old and old.emit and not old._destroyed then
        old:emit("blur")
    end
    self.focus = node
    if node and node.emit and not node._destroyed then
        node:emit("focus")
    end
end

-- ---------------------------------------------------------------------
-- Pointer state
-- ---------------------------------------------------------------------

--- Whether node is ancestor or a descendant of it.
local function containsAncestor(ancestor, node)
    local n = node
    while n do
        if n == ancestor then return true end
        n = n._parent
    end
    return false
end

--- Updates hover and drag state for a pointer move at design coords.
function Dispatcher:mouseMove(x, y)
    local target = DXUI.HitTest.topAt(self.instance, x, y)
    -- hover transitions
    if target ~= self.hover then
        local old = self.hover
        if old and old.emit and not old._destroyed then
            old:emit("hover-end")
        end
        self.hover = target
        if target and target.emit then
            target:emit("hover-start")
        end
    end
    -- drag progress
    local pressed = self.pressed
    if pressed and pressed.emit and not pressed._destroyed then
        if not self.dragged and self.pressX and self.pressY then
            local dx, dy = x - self.pressX, y - self.pressY
            if math.abs(dx) > self.DRAG_THRESHOLD or math.abs(dy) > self.DRAG_THRESHOLD then
                self.dragged = true
                self.dragging = true
                pressed:emit("drag-start", x, y)
            end
        end
        if self.dragging then
            pressed:emit("drag-move", x, y)
        end
    end
end

--- Starts a press on the topmost reachable node at design coords.
function Dispatcher:mouseDown(button, x, y)
    self:closePopupsOutside(x, y)
    local target = DXUI.HitTest.topAt(self.instance, x, y)
    if target and target.emit and not target._destroyed and self:reachable(target) then
        self.pressed = target
        self.pressButton = button
        self.pressX, self.pressY = x, y
        self.dragged, self.dragging = false, false
        target:emit("mousedown", button, x, y)
        target:emit("press", button, x, y)
        if target.focusable then self:setFocus(target) end
    else
        self.pressed = nil
    end
end

--- Releases the press, emitting click or drag-end as appropriate.
function Dispatcher:mouseUp(button, x, y)
    local pressed = self.pressed
    self.pressed = nil
    if pressed and pressed.emit and not pressed._destroyed then
        pressed:emit("mouseup", button, x, y)
        pressed:emit("release", button, x, y)
        if self.dragging then
            pressed:emit("drag-end", x, y)
        elseif not self.dragged then
            -- click: same target still under the cursor?
            pressed:emit("click", button, x, y, pressed)
        end
    end
    self.dragging, self.dragged = false, false
    self.pressX, self.pressY = nil, nil
end

--- Closes popups when clicking outside them (before routing).
function Dispatcher:closePopupsOutside(x, y)
    local popups = self.popups
    if #popups == 0 then return end
    -- keep popups containing the point; close the topmost chain that does not
    local keep = {}
    for i = #popups, 1, -1 do
        local p = popups[i]
        local inside = p.worldX ~= nil and x >= p.worldX and y >= p.worldY
            and x < p.worldX + p.width and y < p.worldY + p.height
        if inside then
            keep[#keep + 1] = i
        else
            break
        end
    end
    for i = #popups, 1, -1 do
        local p = popups[i]
        local keepIt = false
        for j = 1, #keep do
            if keep[j] >= i then keepIt = true end
        end
        if not keepIt then
            table.remove(popups, i)
            if p.emit then p:emit("popup-close") end
        end
    end
end

--- Routes a wheel event to the nearest scroll handler, bubbling up.
function Dispatcher:scroll(wheel, x, y)
    local target = DXUI.HitTest.topAt(self.instance, x, y) or self.hover or self.focus
    if target and not self:reachable(target) then return false end
    local n = target
    while n do
        if DXUI.Events.has(n, "scroll") then
            n:emit("scroll", wheel, x, y)
            return true
        end
        n = n._parent
    end
    return false
end

--- Routes a key event to the focused node, bubbling up.
function Dispatcher:key(keyName, pressed2, ...)
    local target = self.focus
    if not target then return false end
    if not self:reachable(target) then return false end
    if DXUI.Events.has(target, "key") then
        target:emit("key", keyName, pressed2, ...)
        return true
    end
    local n = target._parent
    while n do
        if DXUI.Events.has(n, "key") then
            n:emit("key", keyName, pressed2, ...)
            return true
        end
        n = n._parent
    end
    return false
end

--- Routes a printable character to the focused node (text input).
function Dispatcher:character(ch)
    local target = self.focus
    if not target then return false end
    if not self:reachable(target) then return false end
    if DXUI.Events.has(target, "character") then
        target:emit("character", ch)
        return true
    end
    local n = target._parent
    while n do
        if DXUI.Events.has(n, "character") then
            n:emit("character", ch)
            return true
        end
        n = n._parent
    end
    return false
end

--- Node destroyed: drop it from all input state (runtime calls on destroy).
function Dispatcher:nodeDestroyed(node)
    if self.hover == node then self.hover = nil end
    if self.focus == node then self.focus = nil end
    if self.pressed == node then self.pressed = nil end
    for i = #self.popups, 1, -1 do
        if self.popups[i] == node then table.remove(self.popups, i) end
    end
    local modals = self.modals
    if modals then
        for i = #modals, 1, -1 do
            if modals[i] == node then table.remove(modals, i) end
        end
    end
end

--- Called when a node mounts/changes in the tree (hook for future cursor
-- tracking: re-evaluate hover when the cursor is stationary over a new
-- node). The dispatcher eagerly updates hover on mouseMove, so this is a
-- no-op by default.
function Dispatcher:_updateNodeState() end

DXUI.Dispatcher = Dispatcher