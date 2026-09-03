---Dispatcher — per-instance input state machine. Input arrives in DESIGN
---space (the runtime converts screen -> design before calling). It owns
---the correlation state: hover, focus, pressed, drag, modal stack, popups.
---
---Events (emitted via the bubbling bus):
---    hover-start / hover-end   (mouse entering/leaving a node)
---    hover-stay            (hover held >= hoverStayDelay; one-shot)
---    mousedown / mouseup       (raw press/release, bubbles)
---    click                     (press+release, no drag; carries click count)
---    doubleclick               (second click within doubleClickInterval)
---    drag-start / drag-move / drag-end
---    drag-over / drag-out     (drop target under a data drag)
---    drop / drag-cancel       (data drag delivery / abort)
---    scroll                    (wheel; bubbles up to an Edit/ScrollPanel)
---    key                       (focus target receives keys)
---    "tab"                     (engine focus cycle, shift+tab = back)
---    focus / blur              (focusable nodes)
---
---Rules:
--- modal stack: while a modal is open, only nodes inside it receive
--- input; opening a modal locks hover/focus to it.
--- popup management: any click outside current popups dismisses the
--- topmost popup (popup nodes are tracked as they open).
--- drag: press starts a potential drag; movement beyond DRAG_THRESHOLD
--- fires drag-start once and marks the press as a drag (click is then
--- suppressed on release). Drag events route to the pressed node and
--- bubble; capture ends on release.

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
        -- last pointer position (design units): the stationary-cursor
        -- re-evaluation and the hover-stay payload use it
        lastX = nil,
        lastY = nil,
        -- hover-stay timing: hover-start timestamp (ms, instance clock)
        -- + one-shot flag
        hoverSince = nil,
        hoverStayFired = false,
        -- last click {node, t, count} for multi-click pairing
        lastClick = nil,
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
    -- the old hover target may now be blocked by this modal: end it now,
    -- so no widget keeps hover styling behind the modal until the next
    -- pointer move re-establishes hover under the new rules
    local old = self.hover
    if old and not self:reachable(old) then
        self:_setHover(nil)
    end
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

--- Hover transition: emits hover-end/hover-start and resets the
--- hover-stay timer. `target == self.hover` is a no-op — moving within
--- one node keeps the stay timer running (tooltip-friendly semantics).
function Dispatcher:_setHover(target)
    if target == self.hover then return end
    local old = self.hover
    if old and old.emit and not old._destroyed then
        old:emit("hover-end")
    end
    self.hover = target
    self.hoverSince = nil
    self.hoverStayFired = false
    if target and target.emit then
        target:emit("hover-start")
        local inst = self.instance
        self.hoverSince = (inst and inst.clock) and inst.clock() or 0
    end
end

--- Updates hover and drag state for a pointer move at design coords.
function Dispatcher:mouseMove(x, y)
    self.lastX, self.lastY = x, y
    local target = DXUI.HitTest.topAt(self.instance, x, y)
    -- modal contract (file header): only nodes inside the top modal
    -- receive input — hover included. Without this check hover styling
    -- lights up widgets that a modal click can never reach (press/scroll/
    -- key already block them via reachable()).
    if target and not self:reachable(target) then target = nil end
    -- hover transitions
    self:_setHover(target)
    -- opt-in continuous position: widgets whose sub-structure is not a
    -- child node (GridList rows) set _hasPointerMove and receive every
    -- move while hovered; nobody else pays a thing
    if target and target._hasPointerMove then
        target:emit("pointer-move", x, y)
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
                -- drag & drop: the source carries data
                if pressed.dragData ~= nil then
                    self._dragData = pressed.dragData
                    self._dragOver = nil
                end
            end
        end
        if self.dragging then
            pressed:emit("drag-move", x, y)
            if self._dragData ~= nil then
                -- drop-target tracking (separate list; modal contract
                -- applies: reachable() filters the top modal's subtree)
                local t = DXUI.HitTest.topDropAt(self.instance, x, y)
                if t and not self:reachable(t) then t = nil end
                if t ~= self._dragOver then
                    local old = self._dragOver
                    self._dragOver = t
                    if old and old.emit and not old._destroyed then
                        old:emit("drag-out", self._dragData, pressed, x, y)
                    end
                    if t and t.emit then
                        t:emit("drag-over", self._dragData, pressed, x, y)
                    end
                end
            end
        end
    end
end

--- Starts a press on the topmost reachable node at design coords.
function Dispatcher:mouseDown(button, x, y)
    self:closePopupsOutside(x, y)
    -- a new press cancels any pending drag&drop state
    self._dragData = nil
    self._dragOver = nil
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
            -- drag & drop delivery: drop on the target, or drag-cancel on
            -- the source when released over nothing
            local data = self._dragData
            if data ~= nil then
                local over = self._dragOver
                self._dragData = nil
                self._dragOver = nil
                if over and not over._destroyed and over.emit then
                    over:emit("drop", data, pressed, x, y)
                elseif pressed.emit then
                    pressed:emit("drag-cancel", data)
                end
            end
        elseif not self.dragged then
            -- click: release with no drag past the threshold — slop-click
            -- semantics; no re-hit-test (a small pointer drift still clicks)
            local inst = self.instance
            local now = (inst and inst.clock) and inst.clock() or 0
            local d = DXUI.Settings and DXUI.Settings.defaults
            local interval = (d and d.doubleClickInterval) or 300
            local cooldown = (d and d.clickCooldown) or 0
            local lc = self.lastClick
            local count = 1
            -- pairing tracks the RAW sequence (same node, within the
            -- interval); count == 2 fires "doubleclick"
            if lc and lc.node == pressed and interval > 0
                and (now - (lc.t or 0)) < interval then
                count = (lc.count or 1) + 1
            end
            self.lastClick = { node = pressed, t = now, count = count }
            -- cooldown rate-limits EMISSIONS; pairing still advances, but a
            -- click closer than cooldown to the previous one emits nothing
            -- (a double-click pair faster than cooldown is swallowed too —
            -- keep cooldown 0 when doubleclicks matter)
            local suppressed = cooldown > 0 and lc ~= nil
                and (now - (lc.t or 0)) < cooldown
            if not suppressed then
                if count == 2 then
                    pressed:emit("doubleclick", button, x, y, pressed)
                end
                pressed:emit("click", button, x, y, pressed, count)
            end
        end
    end
    self.dragging, self.dragged = false, false
    self.pressX, self.pressY = nil, nil
end

--- Closes popups when clicking outside them (before routing).
-- Popups form a stack (topmost last). Close from the top down until the
-- first popup that contains the point; that popup and everything below it
-- stay open (a nested chain survives a click inside its topmost member).
function Dispatcher:closePopupsOutside(x, y)
    local popups = self.popups
    if #popups == 0 then return end
    local i = #popups
    while i >= 1 do
        local p = popups[i]
        local inside = p.worldX ~= nil and x >= p.worldX and y >= p.worldY
            and x < p.worldX + p.width and y < p.worldY + p.height
        if inside then break end
        table.remove(popups, i)
        if p.emit then p:emit("popup-close") end
        i = i - 1
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

--- Tab focus cycle: walks the interactive list in painter order, keeping
--- only reachable focusable nodes — an open modal confines the cycle to
--- its subtree (reachable). Wrap-around in both directions. Returns true
--- when the focus MOVED; a stationary tab (single candidate / none) falls
--- through to the normal key routing.
local function cycleFocus(self, backward)
    local inst = self.instance
    local list = inst and inst._interactive
    local count = list and inst._interactiveCount or 0
    if count == 0 then return false end
    local candidates = {}
    for i = 1, count do
        local n = list[i]
        if n and not n._destroyed and n.focusable and self:reachable(n) then
            candidates[#candidates + 1] = n
        end
    end
    local total = #candidates
    if total == 0 then return false end
    local idx = 0
    for i = 1, total do
        if candidates[i] == self.focus then idx = i break end
    end
    local nextIdx
    if backward then
        nextIdx = (idx > 1) and (idx - 1) or total
    else
        nextIdx = (idx < total) and (idx + 1) or 1
    end
    local target = candidates[nextIdx]
    if target == self.focus then return false end
    self:setFocus(target)
    return true
end

--- Routes a key event to the focused node, bubbling up. "tab" cycles the
--- focus first (shift+tab = backward) and never reaches user handlers
--- when the focus actually moved.
function Dispatcher:key(keyName, isDown, ...)
    if keyName == "tab" and isDown then
        if cycleFocus(self, select(1, ...) == true) then return true end
    end
    -- window hotkeys (D6): { [keyName] = handler } maps on ancestors of
    -- the focused node (windows mainly) match BEFORE the focus chain. A
    -- handler returning false falls through to the normal routing; any
    -- other result consumes the key.
    local hk = self.focus
    while hk do
        local map = rawget(hk, "hotkeys")
        if map ~= nil and type(map) == "table" then
            local fn = map[keyName]
            if fn ~= nil then
                local ok, consumed = pcall(fn, hk, keyName, isDown)
                if not ok then
                    DXUI._warn("hotkey '" .. tostring(keyName) .. "' failed: "
                        .. tostring(consumed))
                    return true
                end
                if consumed ~= false then return true end
            end
        end
        hk = hk._parent
    end
    local target = self.focus
    if not target then return false end
    if not self:reachable(target) then return false end
    if DXUI.Events.has(target, "key") then
        target:emit("key", keyName, isDown, ...)
        return true
    end
    local n = target._parent
    while n do
        if DXUI.Events.has(n, "key") then
            n:emit("key", keyName, isDown, ...)
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
    if self.hover == node then
        -- no hover-end into a destroying node (events stop at destroy)
        self.hover = nil
        self.hoverSince = nil
        self.hoverStayFired = false
    end
    if self.focus == node then self.focus = nil end
    if self.pressed == node then self.pressed = nil end
    if self._dragOver == node then self._dragOver = nil end
    local lc = self.lastClick
    if lc and lc.node == node then self.lastClick = nil end
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

--- Frame hook (Runtime:tick calls this every frame): (1) when the
--- interactive list was rebuilt this frame, re-establishes hover under a
--- STATIONARY cursor — a node mounted/unmounted under it without any
--- mouse move (node.lua's mount-time _updateNodeState cannot do this:
--- the hit list is still stale at mount); (2) fires the one-shot
--- "hover-stay" once the hover target is held >=
--- settings.defaults.hoverStayDelay (0 disables). Idle frames cost a
--- few field reads — the zero-work contract holds.
function Dispatcher:update(now, hitRebuilt)
    if hitRebuilt and self.lastX ~= nil and self.pressed == nil then
        local inst = self.instance
        if inst and not inst._destroyed and DXUI.HitTest then
            local target = DXUI.HitTest.topAt(inst, self.lastX, self.lastY)
            if target and not self:reachable(target) then target = nil end
            self:_setHover(target)
        end
    end
    local h = self.hover
    if h == nil or h._destroyed or self.hoverStayFired
        or self.hoverSince == nil then
        return
    end
    local d = DXUI.Settings and DXUI.Settings.defaults
    local delay = (d and d.hoverStayDelay) or 0
    if delay > 0 and (now - self.hoverSince) >= delay then
        self.hoverStayFired = true
        if h.emit then h:emit("hover-stay", self.lastX, self.lastY) end
    end
end

--- Called when a node mounts/changes in the tree. Deliberately a no-op:
-- at mount time the hit lists are STALE (the rebuild runs on the next
-- tick), so re-evaluating hover here would see the old geometry. The
-- stationary-cursor re-evaluation lives in Dispatcher:update(now,
-- hitRebuilt), driven by Runtime:tick right after the hit rebuild.
function Dispatcher:_updateNodeState() end

DXUI.Dispatcher = Dispatcher