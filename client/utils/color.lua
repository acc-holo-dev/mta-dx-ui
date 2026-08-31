--[[
    color.lua — DXUI V2

    Color utilities: number (packed 0xAARRGGBB) | "#RRGGBB[AA]" |
    {r,g,b,a}. Cold path — strings and allocations are fine.
]]

DXUI = DXUI or {}

--- color(r, g, b, a) -> packed 0xAARRGGBB (MTA tocolor).
function DXUI.color(r, g, b, a)
    return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

--- Resolves a color: number (packed 0xAARRGGBB) | "#RRGGBB[AA]" | "#RGB" |
-- "0xRRGGBB" (alpha 255) | "0xAARRGGBB" | {r,g,b,a}. Unknown strings raise an
-- error instead of silently resolving to transparent black.
function DXUI.resolveColor(c)
    if c == nil then return nil end
    if type(c) == "number" then return c end
    if type(c) == "string" then
        local hex = c:match("^#(.*)$")
        if hex then
            -- #RGB — one digit per channel, doubled
            if #hex == 3 then
                local function dup(ch) return ch:sub(1, 1) .. ch:sub(1, 1) end
                local r = tonumber(dup(hex:sub(1, 1)), 16) or 0
                local g = tonumber(dup(hex:sub(2, 2)), 16) or 0
                local b = tonumber(dup(hex:sub(3, 3)), 16) or 0
                return 0xFF000000 + r * 0x10000 + g * 0x100 + b
            end
            -- #RRGGBB / #RRGGBBAA (AA at the END, documented)
            local r = tonumber(hex:sub(1, 2), 16) or 0
            local g = tonumber(hex:sub(3, 4), 16) or 0
            local b = tonumber(hex:sub(5, 6), 16) or 0
            local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
            return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
        end
        local lhex = c:match("^0x(.*)$")
        if lhex then
            -- 0xRRGGBB (α = 255) / 0xAARRGGBB (packed, like the number form)
            if #lhex == 6 then
                local r = tonumber(lhex:sub(1, 2), 16) or 0
                local g = tonumber(lhex:sub(3, 4), 16) or 0
                local b = tonumber(lhex:sub(5, 6), 16) or 0
                return 0xFF000000 + r * 0x10000 + g * 0x100 + b
            end
            if #lhex == 8 then
                local a = tonumber(lhex:sub(1, 2), 16) or 255
                local r = tonumber(lhex:sub(3, 4), 16) or 0
                local g = tonumber(lhex:sub(5, 6), 16) or 0
                local b = tonumber(lhex:sub(7, 8), 16) or 0
                return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
            end
        end
        error("resolveColor: unsupported color string: " .. c)
    end
    if type(c) == "table" then
        -- named fields {r=,g=,b=,a=} or positional {r, g, b, a}
        local r = c.r or c[1] or 0
        local g = c.g or c[2] or 0
        local b = c.b or c[3] or 0
        local a = c.a or c[4] or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    error("resolveColor: unsupported color type: " .. type(c))
end
