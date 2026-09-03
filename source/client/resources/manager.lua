---Resource Manager: textures, fonts, shaders — with automatic caching
---(identical resources created once: no "font per label").
---
---    local tex  = ui:texture("icons/x.png")   -- cached
---    local font = ui:font("assets/Roboto.ttf", 12)  -- cached (FILE PATH)
---    local sh   = ui:shader(code)              -- cached
---
---Ownership: caches are SHARED process-wide. The ACTIVE theme owns
---the set of assets it references; switching themes sweeps obsolete assets
---(released) while shared ones remain. Hard release happens on the
---runtime resource stop (releaseResources).
---
---Outside MTA (tests): textures pass through as path placeholders, fonts/
---shaders return nil (default font) — deterministic and testable.

DXUI = DXUI or {}

local textureCache = {}
local fontCache = {}
local shaderCache = {}

-- failed loads are cached as `false`; a retry is allowed after FAIL_TTL ms
-- so a transient failure (file not yet written, hot-reload) recovers
local FAIL_TTL = 5000
local failAt = {}

local function clock()
    return getTickCount and getTickCount() or 0
end

--- Whether a cached `false` failure is still within its retry TTL.
local function withinFailTtl(key)
    local t = failAt[key]
    return t ~= nil and (clock() - t) < FAIL_TTL
end

-- ---------------------------------------------------------------------
-- Alpha-hit masks (pixel-perfect hit testing; see input/hit_test.lua)
-- ---------------------------------------------------------------------

-- Bit-packed 1-bit masks, ≤256 per side (≤8 KB per material), keyed by
-- the material (path or texture handle). `false` = failed → the hit
-- test falls back to the plain rect (no per-frame retries: pixel reads
-- are expensive).
local alphaMasks = {}
local alphaMaskCount = 0
local ALPHA_MASK_CAP = 64

--- Builds the bit-packed alpha mask of a material, or nil on failure.
local function buildAlphaMask(material)
    if not dxGetTexturePixels or not dxGetPixelColor or not dxGetMaterialSize then
        return nil
    end
    local tw, th
    local ok, w, h = pcall(dxGetMaterialSize, material)
    if ok and w and w > 0 then tw, th = w, h end
    if not tw or not th or tw <= 0 or th <= 0 then return nil end
    local okPix, pixels = pcall(dxGetTexturePixels, material)
    if not okPix or not pixels then return nil end
    local mw = math.min(tw, 256)
    local mh = math.min(th, 256)
    local stride = math.ceil(mw / 8)
    local buf = {}
    for i = 1, stride * mh do buf[i] = 0 end
    -- strided nearest-sample; one-time cost per material
    for row = 0, mh - 1 do
        local ty = math.floor(row * th / mh)
        local base = row * stride
        for col = 0, mw - 1 do
            local tx = math.floor(col * tw / mw)
            local okC, r, g, b, a = pcall(dxGetPixelColor, pixels, tx, ty)
            if okC and a and a > 8 then
                local bi = base + math.floor(col / 8) + 1
                buf[bi] = buf[bi] + 2 ^ (col % 8)
            end
        end
    end
    for i = 1, #buf do buf[i] = string.char(buf[i]) end
    return {
        data = table.concat(buf),
        mw = mw, mh = mh, stride = stride,
        tw = tw, th = th,
    }
end

--- Returns the cached alpha-hit mask of a material:
--- { data, mw, mh, stride, tw, th } | false (failed: rect fallback) |
--- nil (no material). The cache is capped; on overflow it is wiped and
--- rebuilt on demand (masks are tiny and rebuilds are rare).
function DXUI.alphaMask(material)
    if material == nil or material == "" then return nil end
    local m = alphaMasks[material]
    if m ~= nil then return m end
    m = buildAlphaMask(material)
    if not m then
        if DXUI._warn then
            DXUI._warn("alphaMask: no readable pixels for " .. tostring(material)
                .. "; hit test falls back to the rect")
        end
        m = false
    end
    alphaMaskCount = alphaMaskCount + 1
    if alphaMaskCount > ALPHA_MASK_CAP then
        alphaMasks = {}
        alphaMaskCount = 0
    end
    alphaMasks[material] = m
    return m
end

--- Loads a texture, cached by path (+ format options). opts (nil = engine
-- defaults): { format = "argb"|"dxt1"|"dxt3"|"dxt5", mipmaps = bool,
-- edge = "wrap"|"clamp" } — see dxCreateTexture (MTA wiki: dxt1 is 8x,
-- dxt3/dxt5 4x lighter in video memory). With default opts the plain
-- `path` cache key and the old call signature are kept (byte-for-byte
-- compatibility); non-default opts join the key so variants coexist.
-- Failed loads cached as `false` (marker; a nil value cannot be stored)
-- and returned as nil, with a TTL-bounded retry so a transient failure
-- does not degrade the UI for the whole session.
local TEX_FORMATS = { argb = true, dxt1 = true, dxt3 = true, dxt5 = true }
local TEX_EDGES = { wrap = true, clamp = true }

function DXUI.texture(path, opts)
    local format, mipmaps, edge
    if opts ~= nil then
        if type(opts) ~= "table" then
            DXUI._warn("texture: opts must be a table, got " .. type(opts))
        else
            format = opts.format
            if format ~= nil and not TEX_FORMATS[format] then
                DXUI._warn("texture: unknown format '" .. tostring(format) .. "', using argb")
                format = nil
            end
            mipmaps = opts.mipmaps
            if mipmaps ~= nil and type(mipmaps) ~= "boolean" then
                DXUI._warn("texture: mipmaps must be a boolean, using default")
                mipmaps = nil
            end
            edge = opts.edge
            if edge ~= nil and not TEX_EDGES[edge] then
                DXUI._warn("texture: unknown edge '" .. tostring(edge) .. "', using wrap")
                edge = nil
            end
        end
    end
    local custom = (format ~= nil) or (mipmaps ~= nil) or (edge ~= nil)
    local key = path
    if custom then
        key = tostring(path) .. "|" .. tostring(format or "argb") .. "|"
            .. tostring(mipmaps ~= false) .. "|" .. tostring(edge or "wrap")
    end
    local cached = textureCache[key]
    if cached ~= nil then
        if cached ~= false then return cached end
        if withinFailTtl(key) then return nil end
    end
    local tex
    if dxCreateTexture then
        local ok, result
        if custom then
            ok, result = pcall(dxCreateTexture, path,
                format or "argb", mipmaps ~= false, edge or "wrap")
        else
            -- defaults: the pre-opts call signature, unchanged
            ok, result = pcall(dxCreateTexture, path)
        end
        tex = ok and result or false
        if not ok or not result then
            DXUI._warn("texture: failed to load '" .. tostring(path) .. "'")
        end
    else
        -- outside MTA: pass-through placeholder
        tex = path
    end
    textureCache[key] = tex
    failAt[key] = (tex == false) and clock() or nil
    return tex ~= false and tex or nil
end

--- Valid dxCreateFont quality values (MTA wiki). The engine default is
--- "proof" and is NOT passed through (no behavior change without opts).
local FONT_QUALITIES = {
    default = true, draft = true, proof = true, nonantialiased = true,
    antialiased = true, cleartype = true, cleartype_natural = true,
}

--- Builds the font cache key. DEFAULT inputs (bold ~= true, quality nil
--- or unknown — mirroring DXUI.font's validation) keep the plain
--- "name:size" key, byte-for-byte compatible with the pre-opts era and
--- the theme keep-set sweep (Theme.keepFont); valid custom opts append
--- "|bold|quality". Single source of truth for the key format.
function DXUI.fontCacheKey(name, size, opts)
    local bold, quality
    if type(opts) == "table" then
        bold, quality = opts.bold, opts.quality
        if bold ~= true then bold = nil end
        if quality ~= nil and not FONT_QUALITIES[quality] then quality = nil end
    end
    if bold or quality then
        return tostring(name) .. ":" .. tostring(size)
            .. "|" .. tostring(bold == true) .. "|" .. tostring(quality or "")
    end
    return tostring(name) .. ":" .. tostring(size)
end

--- Creates a font, cached by (path, size[, bold, quality]). `name` is a
-- FILE PATH (or "default" for the built-in font), not a family name.
-- nil = default font. opts: { bold = bool (default false), quality =
-- one of FONT_QUALITIES } — see dxCreateFont (MTA wiki; creation may
-- fail on video memory — failures are FAIL_TTL-cached like textures).
-- With no opts the call signature, cache key and behavior are unchanged.
function DXUI.font(name, size, opts)
    local bold, quality
    if type(opts) == "table" then
        bold, quality = opts.bold, opts.quality
    elseif opts ~= nil then
        DXUI._warn("font: opts must be a table, got " .. type(opts))
    end
    if bold ~= nil and type(bold) ~= "boolean" then
        DXUI._warn("font: bold must be a boolean, using default")
        bold = nil
    end
    if quality ~= nil and not FONT_QUALITIES[quality] then
        DXUI._warn("font: unknown quality '" .. tostring(quality)
            .. "', using engine default")
        quality = nil
    end
    local custom = (bold == true) or (quality ~= nil)
    local key = DXUI.fontCacheKey(name, size, { bold = bold, quality = quality })
    local cached = fontCache[key]
    if cached ~= nil then
        if cached ~= false then return cached end
        if withinFailTtl(key) then return nil end
    end
    local font
    if dxCreateFont then
        local ok, result
        if custom then
            ok, result = pcall(dxCreateFont, name, size,
                bold == true, quality or "proof")
        else
            -- no opts: the pre-opts call signature, unchanged
            ok, result = pcall(dxCreateFont, name, size)
        end
        font = ok and result or false
        if not ok or not result then
            DXUI._warn("font: failed to load '" .. tostring(name) .. "'")
        end
    end
    fontCache[key] = font
    failAt[key] = (font == false) and clock() or nil
    return font ~= false and font or nil
end

--- System-wide fallback font (settings.defaults.font): the font behind
--- every text draw whose node has no font (node font > themed font >
--- this > the engine "default"). Spec: "path", "path:size" or
--- "path:size:quality" (quality per dxCreateFont; unknown values warn
--- and fall back). Resolved once per spec change; outside MTA the spec
--- string rides as the handle (texture passthrough semantics) so
--- consumption is testable.
local sysFontHandle, sysFontSpec
function DXUI.systemFont()
    local spec = DXUI.Settings and DXUI.Settings.defaults
        and DXUI.Settings.defaults.font
    if spec ~= sysFontSpec then
        sysFontSpec = spec
        sysFontHandle = nil
        if spec ~= nil and spec ~= "" then
            local path, size, quality = spec:match("^(.*):(%d+):(%a[%w_]*)$")
            if not path then
                path, size = spec:match("^(.*):(%d+)$")
            end
            path = path or spec
            if dxCreateFont then
                sysFontHandle = DXUI.font(path, tonumber(size),
                    quality and { quality = quality } or nil)
            else
                sysFontHandle = spec
            end
        end
    end
    return sysFontHandle
end

--- Compiles a shader, cached by code.
function DXUI.shader(code)
    local cached = shaderCache[code]
    if cached ~= nil then
        if cached ~= false then return cached end
        if withinFailTtl(code) then return nil end
    end
    local sh
    if dxCreateShader then
        local ok, result = pcall(dxCreateShader, code)
        sh = ok and result or false
        if not ok or not result then
            DXUI._warn("shader: failed to compile")
        end
    end
    shaderCache[code] = sh
    failAt[code] = (sh == false) and clock() or nil
    return sh ~= false and sh or nil
end

-- ---------------------------------------------------------------------
-- Theme-asset ownership: the active theme references a keep-set;
-- sweeping releases obsolete cached assets, shared ones survive.
-- ---------------------------------------------------------------------

--- Destroys v if it is an MTA element (userdata).
local function destroyIfElement(_, v)
    if type(v) == "userdata" and isElement and isElement(v) then
        destroyElement(v)
    end
end

--- Releases every cached texture/font NOT in keep (string keys). Shaders
-- are deliberately NOT swept here: they are shared engine-wide effects
-- keyed by shader code (rounded/blur/mask), never per-theme assets, so a
-- theme switch must keep them.
-- The keep-set is built by the theme while it compiles (Resources.markUsed).
-- Returns the number of released assets (diagnostics).
function DXUI.releaseObsolete(keep)
    local freed = 0
    if keep then
        for k, tex in pairs(textureCache) do
            if tex ~= false and not keep["t:" .. k] then
                destroyIfElement(k, tex)
                textureCache[k] = nil
                freed = freed + 1
            end
        end
        for k, font in pairs(fontCache) do
            if font ~= false and not keep["f:" .. k] then
                destroyIfElement(k, font)
                fontCache[k] = nil
                freed = freed + 1
            end
        end
    end
    return freed
end

--- Fully release everything (runtime resource stop).
function DXUI.releaseResources()
    if isElement and destroyElement then
        for _, tex in pairs(textureCache) do destroyIfElement(nil, tex) end
        for _, font in pairs(fontCache) do destroyIfElement(nil, font) end
        for _, sh in pairs(shaderCache) do destroyIfElement(nil, sh) end
    end
    textureCache, fontCache, shaderCache = {}, {}, {}
    failAt = {}
    if DXUI.Text and DXUI.Text.clearCache then DXUI.Text.clearCache() end
    if DXUI.Effects and DXUI.Effects.releasePool then DXUI.Effects.releasePool() end
    if DXUI.Effects and DXUI.Effects.clearCaches then DXUI.Effects.clearCaches() end
end