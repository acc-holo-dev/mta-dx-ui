--[[
    color.lua — DXUI V2

    Утилиты цвета (§6): number (packed 0xAARRGGBB) | "#RRGGBB[AA]" |
    {r,g,b,a}. Cold path — строки и аллокации допустимы.
]]

DXUI = DXUI or {}

--- color(r, g, b, a) -> packed 0xAARRGGBB (MTA tocolor).
function DXUI.color(r, g, b, a)
    return (a or 255) * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

--- Разрешает цвет: number (packed) | "#RRGGBB[AA]" | {r,g,b,a}.
function DXUI.resolveColor(c)
    if c == nil then return nil end
    if type(c) == "number" then return c end
    if type(c) == "string" then
        local hex = c:match("^#(.*)$") or c
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    if type(c) == "table" then
        -- именованные поля {r=,g=,b=,a=} или позиционные {r, g, b, a}
        local r = c.r or c[1] or 0
        local g = c.g or c[2] or 0
        local b = c.b or c[3] or 0
        local a = c.a or c[4] or 255
        return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
    end
    error("resolveColor: unsupported color type: " .. type(c))
end
