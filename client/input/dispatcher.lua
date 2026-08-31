--[[
    dispatcher.lua — DXUI V2

    Central input dispatcher: one per context, not per-node MTA handlers.
    The global bridge (init.lua) calls these methods.

    State model: hovered / focused / pressed / captured (drag).
    A global model instead of local state on each widget.

    Stage 7 adds:
      - drag-capture (beginDrag/endDrag) — dragging windows/thumbs/selections;
      - modal stack — focus lock + input trap;
      - popup stack — dismiss on outside click.

    Flow: MTA event → Context:onXxx → Dispatcher → HitTest → target →
    EventBus.emit (bubble).
]]

DXUI = DXUI or {}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher.new(context)
    local self = setmetatable({}, Dispatcher)
    self.context = context
    self.hoveredNode = nil
    self.pressedNode = nil
    self.focusedNode = nil

    -- Stage 7: drag-capture
    self.dragMove = nil
    self.dragEnd = nil

    -- Stage 7: modal stack (focus lock + input trap)
    self.modalStack = {}

    -- Stage 7: popup stack (dismiss on outside click)
    self.popupStack = {}

    return self
end

-- =======================================================================
-- Drag-capture (Stage 7)
-- =======================================================================

--- Capture the cursor for dragging. fnMove(x, y) fires on each onCursorMove;
-- fnEnd() fires on the first mouseup (anywhere). A new beginDrag replaces.
function Dispatcher:beginDrag(fnMove, fnEnd)
    self.dragMove = fnMove
    self.dragEnd = fnEnd
end

--- End drag immediately (no mouseup). Calls fnEnd.
-- M25: hit/x/y (drop target + release point) pass through to fnEnd.
function Dispatcher:endDrag(hit, x, y)
    local f = self.dragEnd
    self.dragMove = nil
    self.dragEnd = nil
    self._dragOverTarget = nil
    if f then f(hit, x, y) end
end

--- M25: nearest alive drop target (self or ancestor) of a hit node.
function Dispatcher:_findDropTarget(node)
    local cur = node
    while cur do
        if cur._dropTarget and not cur._destroyed then return cur end
        cur = cur._parent
    end
    return nil
end

-- =======================================================================
-- Modal (Stage 7): focus lock + input trap
-- The stack keeps NODE REFERENCES (V2 object model, not numeric ids).
-- =======================================================================

function Dispatcher:pushModal(window, overlay)
    self.modalStack[#self.modalStack + 1] = { window = window, overlay = overlay }
end

function Dispatcher:popModal(window)
    for i = #self.modalStack, 1, -1 do
        if self.modalStack[i].window == window then
            table.remove(self.modalStack, i)
            break
        end
    end
end

function Dispatcher:getTopModal()
    return self.modalStack[#self.modalStack]
end

function Dispatcher:isModalActive()
    return #self.modalStack > 0
end

--- node is a descendant of ancestor (or equals it). Walks the parent chain.
function Dispatcher:isDescendant(node, ancestor)
    local cur = node
    while cur do
        if cur == ancestor then return true end
        cur = cur._parent
    end
    return false
end

--- node is inside the top modal (window / descendant / overlay). No modal — everything allowed.
function Dispatcher:isInsideModal(node)
    local top = self:getTopModal()
    if not top then return true end
    if node == nil then return false end
    if node == top.overlay then return true end
    return self:isDescendant(node, top.window)
end

-- =======================================================================
-- Popup (Stage 7): dismiss on outside click. The stack keeps node references.
-- =======================================================================

function Dispatcher:pushPopup(node, dismissFn)
    self.popupStack[#self.popupStack + 1] = { node = node, dismissFn = dismissFn }
end

function Dispatcher:popPopup(node)
    for i = #self.popupStack, 1, -1 do
        if self.popupStack[i].node == node then
            table.remove(self.popupStack, i)
            break
        end
    end
end

function Dispatcher:getTopPopup()
    return self.popupStack[#self.popupStack]
end

function Dispatcher:isInsidePopup(node)
    local top = self:getTopPopup()
    if not top then return false end
    if node == nil then return false end
    return self:isDescendant(node, top.node)
end

-- =======================================================================
-- Mouse
-- =======================================================================

function Dispatcher:onCursorMove(x, y)
    x, y = self.context:toLocal(x, y) -- screen → design
    -- drag consumes movement; hover frozen until mouseup
    if self.dragMove then
        self.dragMove(x, y)
        -- M25: drop-target hover tracking during drag
        local target = self:_findDropTarget(DXUI.HitTest.pick(self.context, x, y))
        if target ~= self._dragOverTarget then
            local old = self._dragOverTarget
            self._dragOverTarget = target
            if old and old:isAlive() then
                DXUI.EventBus.emit(old, "dragleave", { x = x, y = y })
            end
            if target then
                DXUI.EventBus.emit(target, "dragenter", { x = x, y = y })
            end
        end
        return
    end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: hover outside the window is suppressed
    if self:isModalActive() and not self:isInsideModal(hit) then
        hit = nil
    end

    if hit ~= self.hoveredNode then
        local old = self.hoveredNode
        if old then
            DXUI.EventBus.emit(old, "mouseleave", { x = x, y = y })
        end
        self.hoveredNode = hit
        if hit then
            DXUI.EventBus.emit(hit, "mouseenter", { x = x, y = y })
        end
        self:_updateNodeState(old)
        self:_updateNodeState(hit)
    end
end

function Dispatcher:onMouseDown(x, y, button)
    x, y = self.context:toLocal(x, y) -- screen → design
    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- popup dismiss: click outside the top popup closes it (consumes the click)
    local topPopup = self:getTopPopup()
    if topPopup and not self:isInsidePopup(hit) then
        self:popPopup(topPopup.node)
        if topPopup.dismissFn then topPopup.dismissFn() end
        self.pressedNode = nil
        return
    end

    -- modal: input trap — events outside the window are blocked
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedNode = nil
        return
    end

    local oldPressed = self.pressedNode
    self.pressedNode = hit
    self:setFocus(hit)
    if hit then
        DXUI.EventBus.emit(hit, "mousedown", { x = x, y = y, button = button })
    end
    if oldPressed ~= hit then
        self:_updateNodeState(oldPressed)
        self:_updateNodeState(hit)
    end
end

function Dispatcher:onMouseUp(x, y, button)
    x, y = self.context:toLocal(x, y) -- screen → design
    -- drag ends on mouseup anywhere; drop target is the node under the cursor
    if self.dragMove then
        local hit = DXUI.HitTest.pick(self.context, x, y)
        local target = self:_findDropTarget(hit)
        local old = self._dragOverTarget
        self._dragOverTarget = nil
        if old and old ~= target and old:isAlive() then
            DXUI.EventBus.emit(old, "dragleave", { x = x, y = y })
        end
        self:endDrag(target, x, y)
    end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: input trap
    if self:isModalActive() and not self:isInsideModal(hit) then
        self.pressedNode = nil
        return
    end

    if hit then
        DXUI.EventBus.emit(hit, "mouseup", { x = x, y = y, button = button })
    end
    -- click counts only when mouseup is over the SAME node as mousedown
    if hit and hit == self.pressedNode then
        DXUI.EventBus.emit(hit, "click", { x = x, y = y, button = button })
    end
    local oldPressed = self.pressedNode
    self.pressedNode = nil
    if oldPressed then
        self:_updateNodeState(oldPressed)
    end
end

function Dispatcher:onMouseWheel(x, y, dz)
    x, y = self.context:toLocal(x, y) -- screen → design
    if self.dragMove then return end

    local hit = DXUI.HitTest.pick(self.context, x, y)

    -- modal: input trap — wheel outside the window is ignored
    if self:isModalActive() and not self:isInsideModal(hit) then return end

    if hit then
        DXUI.EventBus.emit(hit, "wheel", { x = x, y = y, dz = dz })
    end
end

-- =======================================================================
-- Keyboard / Focus
-- =======================================================================

--- Keyboard foundation: key/text events go to the focused node.
-- key — key name (MTA key map), state — "down"/"up", mods — "ctrl"/"shift",
-- text — character (for the text event). Target events (no bubbling).
function Dispatcher:onKeyDown(key, state, mods, text)
    if not self.focusedNode then return end
    if state == "down" and text and text ~= "" then
        DXUI.EventBus.emit(self.focusedNode, "text", { text = text }, false)
    end
    DXUI.EventBus.emit(self.focusedNode, "key", {
        key = key, state = state, mods = mods or "", text = text,
    }, false)
end

--- Set focus (emit blur on the old node + focus on the new). Target events
-- (no bubbling — focus/blur don't bubble, like in the DOM). Modal: focus lock.
-- A click on the overlay does NOT change focus (the input under it keeps it).
function Dispatcher:setFocus(node)
    if node == self.focusedNode then return end
    if self:isModalActive() then
        local top = self:getTopModal()
        if node == top.overlay then return end
        if node == nil or not self:isInsideModal(node) then
            return -- focus lock: only inside the modal
        end
    end
    local old = self.focusedNode
    if old then
        DXUI.EventBus.emit(old, "blur", {}, false)
    end
    self.focusedNode = node
    if node then
        DXUI.EventBus.emit(node, "focus", {}, false)
    end
    self:_updateNodeState(old)
    self:_updateNodeState(node)
end

function Dispatcher:getFocus()
    return self.focusedNode
end

-- =======================================================================
-- State (M22): visual state tracking (hover/pressed/focused/disabled)
-- =======================================================================

--- Computes a node's visual state. Priority: disabled > pressed > hover >
-- focused > normal.
function Dispatcher:_computeState(node)
    if not node.enabled then return "disabled" end
    if node == self.pressedNode then return "pressed" end
    if node == self.hoveredNode then return "hover" end
    if node == self.focusedNode then return "focused" end
    return "normal"
end

--- Recomputes and applies a node's state (no-op if unchanged).
function Dispatcher:_updateNodeState(node)
    if not node or node._destroyed then return end
    node:setState(self:_computeState(node))
end

--- Clear references to a destroyed node (called by Context:_onNodeDestroyed).
function Dispatcher:_onNodeDestroyed(node)
    if self.hoveredNode == node then self.hoveredNode = nil end
    if self.pressedNode == node then self.pressedNode = nil end
    if self.focusedNode == node then self.focusedNode = nil end
    -- Stage 7: clean modal/popup stacks (safety net; widgets clean up themselves)
    for i = #self.modalStack, 1, -1 do
        local m = self.modalStack[i]
        if m.window == node or m.overlay == node then
            table.remove(self.modalStack, i)
        end
    end
    for i = #self.popupStack, 1, -1 do
        if self.popupStack[i].node == node then
            table.remove(self.popupStack, i)
        end
    end
end

DXUI.Dispatcher = Dispatcher
