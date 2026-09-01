--[[
    values.lua — DXUI V3

    Value objects + color numerics. Pure Lua 5.1, no MTA dependency.

    Color : packed 0xAARRGGBB int, exposed as a cached proxy per (node, key)
            so `button.color.r = 255` works while render stays on the packed
            int (renderer normalizes with Color.toInt, cheap cached field).
    Point : maps to node properties x / y  (node.position)
    Size  : maps to node properties width / height (node.size)

    All proxies are cached per node (never allocated per access). Writes go
    through the same mutation layer as property-style writes (node:_set), so
    invalidation/owner bookkeeping are identical.

    Color parse/repack is a COLD-path operation (used on property writes via
    the spec transform and by theme compilation). Render never parses.
]]

DXUI = DXUI or {}

-- ---------------------------------------------------------------------
-- Pack / parse
-- ---------------------------------------------------------------------

--- Packs r,g,b,a (0-255) into 0xAARRGGBB.
function DXUI.color(r, g, b, a)
    return (a or 255) * 0x1000000 + (r or 0) * 0x10000 + (g or 0) * 0x100 + (b or 0)
end

--- Clamps a byte value to the 0-255 range.
local function clampByte(v)
    return (v < 0) and 0 or ((v > 255) and 255 or v)
end

--- Resolves a color into packed 0xAARRGGBB.
-- Accepts: number (packed), "#RGB", "#RRGGBB", "#RRGGBBAA" (alpha at the
-- END), "0xRRGGBB" (alpha 255), "0xAARRGGBB", {r,g,b,a} table, or a Color
-- proxy. Unknown strings raise (dev-safe; never silently transparent).
function DXUI.resolveColor(c)
    if c == nil then return nil end
    local t = type(c)
    if t == "number" then return c end
    if t == "table" then
        -- Color proxy fast path
        local packed = rawget(c, "_packed")
        if packed ~= nil then return packed end
        local r, g, b, a = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0, c.a or c[4] or 255
        return DXUI.color(r, g, b, a)
    end
    if t == "string" then
        local hex = c:match("^#(.*)$")
        if hex then
            -- #RGB shorthand: each hex digit is doubled
            if #hex == 3 then
                local function dup(ch) return ch:sub(1, 1) .. ch:sub(1, 1) end
                return 0xFF000000
                    + (tonumber(dup(hex:sub(1, 1)), 16) or 0) * 0x10000
                    + (tonumber(dup(hex:sub(2, 2)), 16) or 0) * 0x100
                    + (tonumber(dup(hex:sub(3, 3)), 16) or 0)
            end
            local r = tonumber(hex:sub(1, 2), 16) or 0
            local g = tonumber(hex:sub(3, 4), 16) or 0
            local b = tonumber(hex:sub(5, 6), 16) or 0
            local a = (#hex >= 8) and (tonumber(hex:sub(7, 8), 16) or 255) or 255
            return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
        end
        local lhex = c:match("^0x(.*)$")
        if lhex then
            -- 0xRRGGBB (alpha defaults to 255)
            if #lhex == 6 then
                return 0xFF000000
                    + (tonumber(lhex:sub(1, 2), 16) or 0) * 0x10000
                    + (tonumber(lhex:sub(3, 4), 16) or 0) * 0x100
                    + (tonumber(lhex:sub(5, 6), 16) or 0)
            end
            -- 0xAARRGGBB (same layout as the packed int)
            if #lhex == 8 then
                return (tonumber(lhex:sub(1, 2), 16) or 255) * 0x1000000
                    + (tonumber(lhex:sub(3, 4), 16) or 0) * 0x10000
                    + (tonumber(lhex:sub(5, 6), 16) or 0) * 0x100
                    + (tonumber(lhex:sub(7, 8), 16) or 0)
            end
        end
        error("resolveColor: unsupported color string: " .. c, 2)
    end
    error("resolveColor: unsupported color type: " .. t, 2)
end

--- Fast render-path normalizer: packed int in, packed int out; a Color
-- proxy reads its cached packed value (invalidated on write). Never parses.
function DXUI.ColorToInt(c)
    if type(c) == "number" then return c end
    if type(c) == "table" then
        local packed = rawget(c, "_packed")
        if packed ~= nil then return packed end
        return DXUI.resolveColor(c)
    end
    return c
end

--- Interpolates two packed colors per channel (animation path).
---@param from number packed 0xAARRGGBB
---@param to number packed 0xAARRGGBB
---@param t number progress, 0..1
---@return number packed
function DXUI.lerpColor(from, to, t)
    local fa = math.floor(from / 0x1000000) % 256
    local fr = math.floor(from / 0x10000) % 256
    local fg = math.floor(from / 0x100) % 256
    local fb = from % 256
    local ta = math.floor(to / 0x1000000) % 256
    local tr = math.floor(to / 0x10000) % 256
    local tg = math.floor(to / 0x100) % 256
    local tb = to % 256
    return DXUI.color(
        math.floor(fr + (tr - fr) * t),
        math.floor(fg + (tg - fg) * t),
        math.floor(fb + (tb - fb) * t),
        math.floor(fa + (ta - fa) * t))
end

-- ---------------------------------------------------------------------
-- Color proxy
-- ---------------------------------------------------------------------

local colorMt = {
    --- Reads a color channel (r/g/b/a) or the packed value from the proxy.
    __index = function(self, key)
        local packed = rawget(self, "_packed")
        if packed == nil then
            local node = rawget(self, "_node")
            if node and not node._destroyed then
                packed = DXUI.ColorToInt(node._data[rawget(self, "_key")])
            end
        end
        if packed == nil then return nil end
        if key == "r" then return math.floor(packed / 0x10000) % 256 end
        if key == "g" then return math.floor(packed / 0x100) % 256 end
        if key == "b" then return packed % 256 end
        if key == "a" then return math.floor(packed / 0x1000000) end
        if key == "value" then return packed end
        return nil
    end,
    --- Writes a color channel, repacking through node:_set.
    __newindex = function(self, key, value)
        local node = rawget(self, "_node")
        local prop = rawget(self, "_key")
        local packed = rawget(self, "_packed")
        if packed == nil then packed = DXUI.ColorToInt(node._data[prop]) end
        local r = math.floor(packed / 0x10000) % 256
        local g = math.floor(packed / 0x100) % 256
        local b = packed % 256
        local a = math.floor(packed / 0x1000000)
        if key == "r" then r = clampByte(value)
        elseif key == "g" then g = clampByte(value)
        elseif key == "b" then b = clampByte(value)
        elseif key == "a" then a = clampByte(value)
        else
            error("Color: unknown field '" .. tostring(key) .. "'", 2)
        end
        node:_set(prop, DXUI.color(r, g, b, a))
    end,
    --- Formats the color as "#RRGGBBAA".
    __tostring = function(self)
        local packed = rawget(self, "_packed")
        if packed == nil then packed = DXUI.ColorToInt(rawget(self, "_node")._data[rawget(self, "_key")]) end
        return string.format("#%02X%02X%02X%02X",
            math.floor(packed / 0x1000000),
            math.floor(packed / 0x10000) % 256,
            math.floor(packed / 0x100) % 256,
            packed % 256)
    end,
}

--- Creates (or reuses) the cached Color proxy for (node, propKey).
-- Writes repack through node:_set. Proxy._packed caches the last value;
-- Node:_set invalidates it on any write to propKey.
function DXUI.ColorProxy(node, propKey)
    local values = node._values
    if not values then values = {}; rawset(node, "_values", values) end
    local proxy = values[propKey]
    if proxy ~= nil then return proxy end
    proxy = setmetatable({}, colorMt)
    rawset(proxy, "_node", node)
    rawset(proxy, "_key", propKey)
    rawset(proxy, "_packed", node._data[propKey])
    values[propKey] = proxy
    return proxy
end

--- Invalidates the proxy cache for a property (called by Node:_set).
function DXUI.ColorProxyInvalidate(node, propKey)
    local v = node._values
    if v and v[propKey] then
        rawset(v[propKey], "_packed", nil)
    end
end

-- ---------------------------------------------------------------------
-- Point / Size proxies (value objects over plain node properties)
-- ---------------------------------------------------------------------

--- Point: fields x/y over node props {xProp, yProp}.
-- Size:   fields width/height over node props {wProp, hProp}.
-- Each proxy accepts ONLY its own two fields (a Point has no width, a Size
-- has no x); unknown fields raise.
local function vec2Mt(keys)
    local k1, k2 = keys[1], keys[2]
    return {
        --- Reads one of the two mapped fields from the node.
        __index = function(self, key)
            if key == k1 then return rawget(self, "_node")._data[k1] end
            if key == k2 then return rawget(self, "_node")._data[k2] end
            return nil
        end,
        --- Writes one of the two mapped fields through node:_set.
        __newindex = function(self, key, value)
            local node = rawget(self, "_node")
            if key == k1 then return node:_set(k1, value) end
            if key == k2 then return node:_set(k2, value) end
            error("Vec2: unknown field '" .. tostring(key) .. "'", 2)
        end,
    }
end

local pointMt = vec2Mt({ "x", "y" })
local sizeMt  = vec2Mt({ "width", "height" })

--- Cached Point proxy over node.x / node.y.
function DXUI.PointProxy(node)
    local values = node._values
    if not values then values = {}; rawset(node, "_values", values) end
    local proxy = values["@point"]
    if proxy ~= nil then return proxy end
    proxy = setmetatable({}, pointMt)
    rawset(proxy, "_node", node)
    values["@point"] = proxy
    return proxy
end

--- Cached Size proxy over node.width / node.height.
function DXUI.SizeProxy(node)
    local values = node._values
    if not values then values = {}; rawset(node, "_values", values) end
    local proxy = values["@size"]
    if proxy ~= nil then return proxy end
    proxy = setmetatable({}, sizeMt)
    rawset(proxy, "_node", node)
    values["@size"] = proxy
    return proxy
end