--[[
    ui.lua — DXUI V2

    Public entry point. Global coordinator: context creation,
    theme, design resolution, color utilities.

        local ui = DXUI.createContext()
        local win = ui:window({ ... })   -- Stage 6

    The public API doesn't import widget internals directly —
    only through Context.
]]

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Context creation
-- ---------------------------------------------------------------------

-- Registry of active contexts (global coordinator renders them all).
DXUI._contexts = DXUI._contexts or {}

--- Creates an isolated UI context. backend is optional (tests).
function DXUI.createContext(backend)
    local ctx = DXUI.Context.new(backend)
    DXUI._contexts[#DXUI._contexts + 1] = ctx
    return ctx
end

-- ---------------------------------------------------------------------
-- Theme / design resolution (global, Stages 5/9)
-- ---------------------------------------------------------------------

--- Sets the design resolution. UI is designed in design space;
-- render scales it to the screen (renderer mapping), input events
-- convert back (event.x/y are design coords, consistent with worldX).
-- mode: "stretch" (default — independent axes) | "fit" (uniform + letterbox).
function DXUI.setDesignResolution(w, h, mode)
    DXUI.designW, DXUI.designH = w, h
    DXUI.designScaleMode = mode or "stretch"
end

-- Color (DXUI.color / DXUI.resolveColor) — in utils/color.lua.
