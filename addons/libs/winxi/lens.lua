-- The lens plugin's warp, for anything placed over the world by the flat projection. lens draws the
-- game's world through a Panini or cylindrical projection and publishes what it is doing in a block
-- (LENS-WARP); an overlay that works out a screen point from the view and projection moves it to where
-- the warp shows that point with Point. Without lens, or with its warp off, points are left as they are.
--
-- The mapping mirrors plugins/lens/src/warp.h: SourceOf gives where a screen point reads the flat
-- picture, ScreenOf the reverse, each as fractions 0 to 1 across the picture and the screen.
local ffi = require('ffi')

ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, Frame, WarpedFrame, Mode;
        float Strength, TanH, TanV;
    } lens_warp_t;
]]

local M = { Panini = 0, Cylindrical = 1 }

local sin, cos, tan, atan, acos, sqrt, abs = math.sin, math.cos, math.tan, math.atan, math.acos, math.sqrt, math.abs

function M.PaniniX(phi, d) return (d + 1) * sin(phi) / (d + cos(phi)) end

local function paniniInverse(px, py, d)
    local k = px * px / ((d + 1) * (d + 1))
    local disc = k * k * d * d - (k + 1) * (k * d * d - 1)
    local c = (-k * d + sqrt(disc > 0 and disc or 0)) / (k + 1)
    if c > 1 then c = 1 end
    if c < 1e-6 then c = 1e-6 end
    local phi = (px < 0 and -1 or 1) * acos(c)
    local s = (d + 1) / (d + c)
    return tan(phi), (py / s) / c
end

-- The azimuth of the cylindrical view's edge: phi / cos phi = tanH. Kept for the last tanH asked.
local edgeFor, edgeValue = nil, 0
function M.CylinderEdge(tanH)
    if tanH == edgeFor then return edgeValue end
    local lo, hi = 0, atan(tanH)
    for _ = 1, 60 do
        local mid = (lo + hi) / 2
        if mid / cos(mid) < tanH then lo = mid else hi = mid end
    end
    edgeFor, edgeValue = tanH, lo
    return lo
end

function M.SourceOf(s, t, tanH, tanV, mode, strength)
    if mode == M.Panini then
        local xEdge = M.PaniniX(atan(tanH), strength)
        local yEdge = xEdge * tanV / tanH
        local tx, ty = paniniInverse(xEdge * (2 * s - 1), yEdge * (2 * t - 1), strength)
        return 0.5 + 0.5 * tx / tanH, 0.5 + 0.5 * ty / tanV
    end
    local phiE = M.CylinderEdge(tanH)
    local phi, y = phiE * (2 * s - 1), phiE * tanV / tanH * (2 * t - 1)
    local tx, ty = tan(phi), y / cos(phi)
    return s + strength * (0.5 + 0.5 * tx / tanH - s), t + strength * (0.5 + 0.5 * ty / tanV - t)
end

function M.ScreenOf(s0, t0, tanH, tanV, mode, strength)
    if mode == M.Panini then
        local xEdge = M.PaniniX(atan(tanH), strength)
        local yEdge = xEdge * tanV / tanH
        local phi = atan((2 * s0 - 1) * tanH)
        local height = (2 * t0 - 1) * tanV * cos(phi)
        local scale = (strength + 1) / (strength + cos(phi))
        return 0.5 + 0.5 * scale * sin(phi) / xEdge, 0.5 + 0.5 * scale * height / yEdge
    end
    local s, t = s0, t0
    local h = 1e-5
    for _ = 1, 12 do
        local us, vs = M.SourceOf(s, t, tanH, tanV, mode, strength)
        local fu, fv = us - s0, vs - t0
        if abs(fu) < 1e-9 and abs(fv) < 1e-9 then break end
        local ua, va = M.SourceOf(s + h, t, tanH, tanV, mode, strength)
        local ub, vb = M.SourceOf(s, t + h, tanH, tanV, mode, strength)
        local a, b, c, d = (ua - us) / h, (ub - us) / h, (va - vs) / h, (vb - vs) / h
        local det = a * d - b * c
        if abs(det) < 1e-12 then break end
        s = s - (d * fu - b * fv) / det
        t = t - (a * fv - c * fu) / det
    end
    return s, t
end

-- The block, while lens is loaded; looked for again at most once a second, and again after a reload.
local MAGIC = '4C454E532D5741525000000000000000' -- "LENS-WARP" and zeros, all 16 bytes
local block, base, looked = nil, nil, -1
local function find()
    local ok, loaded = pcall(function () return AshitaCore:GetPluginManager():IsLoaded('lens') end)
    if not (ok and loaded) then block, base = nil, nil; return nil end
    local current = ashita.memory.get_base('lens.dll')
    if current ~= base then block, base, looked = nil, current, -1 end
    if not current or current == 0 then return nil end
    if block == nil then
        if os.clock() - looked < 1 then return nil end
        looked = os.clock()
        local address = ashita.memory.find('lens.dll', 0, MAGIC, 0, 0)
        if not address or address == 0 then return nil end
        local found = ffi.cast('lens_warp_t*', address)
        if found.Version ~= 1 or found.Size ~= ffi.sizeof('lens_warp_t') then return nil end
        block = found
    end
    return block
end

-- The warp as it is this frame: { mode, strength, tanH, tanV }, or nil when lens is not loaded or
-- did not warp the last frame or two. Ask once a frame and hand it to Point.
function M.Current()
    local b = find()
    if b == nil or b.WarpedFrame == 0 or b.Frame - b.WarpedFrame > 2 or b.TanH <= 0 or b.TanV <= 0 then return nil end
    return { mode = tonumber(b.Mode), strength = b.Strength, tanH = b.TanH, tanV = b.TanV }
end

-- Where the warp shows the point (x, y) of a width by height screen, by the flat projection. The
-- warp covers the whole screen, so any pixels across it serve: the back buffer's, imgui's or the
-- window's. Left as it is without a warp.
function M.Point(warp, x, y, width, height)
    if warp == nil or width <= 0 or height <= 0 then return x, y end
    local s, t = M.ScreenOf(x / width, y / height, warp.tanH, warp.tanV, warp.mode, warp.strength)
    return s * width, t * height
end

return M
