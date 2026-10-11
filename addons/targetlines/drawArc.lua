local d3d8dev        = require('d3d8').get_device();
local ffi            = require('ffi');
local C              = ffi.C;

local helpers        = require('helpers');
local matrixMultiply = helpers.matrixMultiply;
local width          = helpers.width;
local height         = helpers.height;
local getTexture     = helpers.getTexture;

local Bezier3D_2     = require('Bezier3D_2');

ffi.cdef [[
    #pragma pack(1)
    struct VertFormatFFFFUFF
    {
        float x;
        float y;
        float z;
        float rhw;
        unsigned int diffuse;
        float u;
        float v;
    };
]]

local vertFormatMask  = bit.bor(C.D3DFVF_XYZRHW, C.D3DFVF_DIFFUSE, C.D3DFVF_TEX1);
local vertFormat      = ffi.new('struct VertFormatFFFFUFF');

-- Every arc of a frame is written into the one buffer, one after another, and they are all drawn
-- together at the end of the frame. An arc takes at most maxArcVertices: two for each of its segment
-- samples and its two ends, and four for its orb. If a frame has more arcs than the buffer holds, what
-- is in it is drawn and it is filled again from the start.
local maxSegments     = 39;
local maxArcVertices  = (maxSegments + 2) * 2 + 4;
local bufferArcs      = 32;
local bufferVertices  = maxArcVertices * bufferArcs;

local _, vertexBuffer = d3d8dev:CreateVertexBuffer(
    bufferVertices * ffi.sizeof(vertFormat),
    C.D3DUSAGE_WRITEONLY,
    vertFormatMask,
    C.D3DPOOL_MANAGED);

-- The buffer while it is locked for writing, the next free vertex in it, and the arcs written so far:
-- where each one's ribbon starts, how many triangles it has, and where its orb starts (false for none).
local lockedData      = nil;
local nextVertex      = 0;
local batchCount      = 0;
local batchStart, batchTriangles, batchOrb = {}, {}, {};

local arcTex, orbTex;

-- Camera state and render-state bookkeeping shared by every arc drawn in one frame
local frameView, frameViewProj, frameZoom;
local statesApplied = false;

local lineWidth = 3;
local lineOpacity = 0.9; -- 1 is solid; 0.9 leaves the lines 10% transparent. Set each frame from the settings.
local baseOrbRadius = 8; -- half the on-screen size of the orb at the arc's tip, in pixels, at 100% scale
local orbRadius = baseOrbRadius; -- set each frame from the settings

-- Whether the lines are hidden where something in the game's picture is in front of them, and what
-- the game had the depth test set to before the lines were drawn, to be put back after
local depthTest = false;
local keptZEnable, keptZFunc = nil, nil;

-- How far a line bows out from the straight way between its ends: 1 is as it has always been drawn,
-- less is flatter, more is rounder
local arcCurve = 1;

-- Call once per frame before drawing arcs. opacity (0-1, optional) is how solid the lines are drawn;
-- orbScale (optional) multiplies the size of the orb, 1 being its normal size. occlude is whether the
-- lines are hidden behind what is in front of them. curve (optional) multiplies how far they bow.
local function beginFrame(opacity, orbScale, occlude, curve)
    depthTest = occlude and true or false;
    arcCurve = curve and math.max(0.1, curve) or 1;
    if (opacity) then
        lineOpacity = math.max(0, math.min(1, opacity));
    end
    if (orbScale) then
        orbRadius = baseOrbRadius * math.max(0, orbScale);
    end

    local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW);
    local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION);

    frameView = view;
    frameViewProj = matrixMultiply(view, projection);
    frameZoom = (2.8 - projection._11) * 0.47619047619;
    statesApplied = false;

    -- Left over only if the last frame was cut short by an error: start clean
    if (lockedData) then
        vertexBuffer:Unlock();
        lockedData = nil;
    end
    batchCount = 0;
    nextVertex = 0;
end

-- World position to screen x, y and depth, using this frame's combined view-projection matrix
local function project(x, y, z)
    local m = frameViewProj;
    local rhw = 1 / (m._14 * x + m._24 * y + m._34 * z + m._44);

    return math.floor(((m._11 * x + m._21 * y + m._31 * z + m._41) * rhw + 1) * 0.5 * width),
        math.floor((1 - (m._12 * x + m._22 * y + m._32 * z + m._42) * rhw) * 0.5 * height),
        (m._13 * x + m._23 * y + m._33 * z + m._43) * rhw;
end

local function offScreen(x, y, z)
    return x > width or x < 0 or y > height or y < 0 or z > 1 or z < 0;
end

-- The screen-space curve being drawn: P(t) = a + b*t + c*t^2, and the unit normal of its plane (n).
-- Kept in locals so sampling the curve allocates nothing.
local ax, ay, az, bx, by, bz, cx, cy, cz, nx, ny, nz;

-- Writes the two ribbon vertices at t. Returns the point on the curve.
local function writePair(vdata, pair, total, reversed, t, u, color)
    local t2 = t * t;
    local px = ax + t * bx + t2 * cx;
    local py = ay + t * by + t2 * cy;
    local pz = az + t * bz + t2 * cz;

    -- tangent, then the in-plane normal to it
    local tx = 2 * cx * t + bx;
    local ty = 2 * cy * t + by;
    local tz = 2 * cz * t + bz;
    local ox = ny * tz - nz * ty;
    local oy = nz * tx - nx * tz;
    local oz = nx * ty - ny * tx;
    local scale = lineWidth * (ox * ox + oy * oy + oz * oz) ^ (-0.5);
    ox = ox * scale;
    oy = oy * scale;

    local first, second = pair * 2, pair * 2 + 1;
    if (reversed) then
        first, second = total - 1 - first, total - 1 - second;
    end

    local vertex = vdata[first];
    vertex.x, vertex.y, vertex.z, vertex.rhw = px + ox, py + oy, pz, 1;
    vertex.diffuse, vertex.u, vertex.v = color, u, 0;

    vertex = vdata[second];
    vertex.x, vertex.y, vertex.z, vertex.rhw = px - ox, py - oy, pz, 1;
    vertex.diffuse, vertex.u, vertex.v = color, u, 0.5;

    return px, py, pz;
end

local function writeVertex(vdata, index, x, y, z, color, u, v)
    local vertex = vdata[index];
    vertex.x, vertex.y, vertex.z, vertex.rhw = x, y, z, 1;
    vertex.diffuse, vertex.u, vertex.v = color, u, v;
end

-- Rotation of the arc's control point about the line between its ends, by pi/16 one way or the other
local rotateSin, rotateCos = math.sin(-math.pi / 16), math.cos(-math.pi / 16);
local rotateSinFlip, rotateCosFlip = math.sin(math.pi / 16), math.cos(math.pi / 16);

local applyStates;

-- Draws every arc written since the buffer was last emptied, and empties it
local function flush()
    if (lockedData) then
        vertexBuffer:Unlock();
        lockedData = nil;
    end

    if (batchCount > 0) then
        applyStates();

        -- all the ribbons, then all the orbs, so the texture is only changed once
        d3d8dev:SetTexture(0, arcTex);
        for i = 1, batchCount do
            d3d8dev:DrawPrimitive(C.D3DPT_TRIANGLESTRIP, batchStart[i], batchTriangles[i]);
        end

        local orbTextureSet = false;
        for i = 1, batchCount do
            local orbStart = batchOrb[i];
            if (orbStart) then
                if (not orbTextureSet) then
                    orbTex = orbTex or getTexture(addon.path .. 'assets/orb.png');
                    d3d8dev:SetTexture(0, orbTex);
                    orbTextureSet = true;
                end
                d3d8dev:DrawPrimitive(C.D3DPT_TRIANGLESTRIP, orbStart, 2);
            end
        end

        -- The depth test is left as the game had it: only the lines were to be drawn with this one.
        -- Should more be drawn this frame, the states are set again for it.
        if (keptZEnable ~= nil or keptZFunc ~= nil) then
            if (keptZEnable ~= nil) then
                d3d8dev:SetRenderState(C.D3DRS_ZENABLE, keptZEnable);
            end
            if (keptZFunc ~= nil) then
                d3d8dev:SetRenderState(C.D3DRS_ZFUNC, keptZFunc);
            end
            keptZEnable, keptZFunc = nil, nil;
            statesApplied = false;
        end
    end

    batchCount = 0;
    nextVertex = 0;
end

-- alpha (0-1, optional) fades the whole arc; omitted means fully opaque
local function drawArc(x1, y1, z1, x2, y2, z2, color, progress, orb, alpha)
    if (not frameViewProj) then
        beginFrame();
    end

    -- Every line is slightly see-through; fades scale down from there
    alpha = (alpha or 1) * lineOpacity;

    if (alpha < 1) then
        -- Rebuilt arithmetically so the ARGB value stays a positive number for the unsigned vertex field
        color = math.floor(math.max(alpha, 0) * math.floor(color / 0x1000000)) * 0x1000000 + color % 0x1000000;
    end

    local P0x, P0y, P0z = x1, z1, y1;
    local P2x, P2y, P2z = x2, z2, y2;

    -- Nothing to draw if both ends are off the same side of the screen
    local wx0, wy0, wz0 = project(P0x, P0y, P0z);
    local wx2, wy2, wz2 = project(P2x, P2y, P2z);

    if (
            (wz0 > 1 and wz2 > 1) or
            (wz0 < 0 and wz2 < 0) or
            ((wx0 > width or wx0 < 0) and (wx2 > width or wx2 < 0)) or
            ((wy0 > height or wy0 < 0) and (wy2 > height or wy2 < 0))
        ) then
        return;
    end

    local P1x, P1y, P1z = (x1 + x2) / 2, (z1 + z2) / 2 - 2, (y1 + y2) / 2;

    P1y = P1y - 2 * frameZoom;

    -- Distance from the camera to the arc's midpoint
    local view = frameView;
    local mx = view._11 * P1x + view._21 * P1y + view._31 * P1z + view._41;
    local my = view._12 * P1x + view._22 * P1y + view._32 * P1z + view._42;
    local mz = view._13 * P1x + view._23 * P1y + view._33 * P1z + view._43;
    local p1Distance = math.sqrt(mx ^ 2 + my ^ 2 + mz ^ 2)

    P1y = P1y + math.max(6 - p1Distance, 0) / 2 + progress

    -- Flatten the curve when the two entities are close together: full height from arcFullDistance
    -- apart, scaling down towards arcMinScale as they near each other.
    local arcFullDistance = 10;
    local arcMinScale = 0.2;
    local separation = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2);
    local arcScale = math.max(math.min(separation / arcFullDistance, 1), arcMinScale);
    local midY = (z1 + z2) / 2;
    P1y = midY + (P1y - midY) * arcScale * arcCurve;

    -- Rotate the control point (relative to the first end) about the unit vector along the line
    do
        local kx, ky, kz = P2x - P0x, P2y - P0y, P2z - P0z;
        local kScale = (kx * kx + ky * ky + kz * kz) ^ (-0.5);
        kx, ky, kz = kx * kScale, ky * kScale, kz * kScale;

        local vx, vy, vz = P1x - P0x, P1y - P0y, P1z - P0z;
        local sin, cos = rotateSin, rotateCos;
        if (not orb) then
            sin, cos = rotateSinFlip, rotateCosFlip;
        end

        local kvcos = (kx * vx + ky * vy + kz * vz) * (1 - cos);
        P1x = vx * cos + (ky * vz - kz * vy) * sin + kx * kvcos + P0x;
        P1y = vy * cos + (kz * vx - kx * vz) * sin + ky * kvcos + P0y;
        P1z = vz * cos + (kx * vy - ky * vx) * sin + kz * kvcos + P0z;
    end

    -- Clip the curve to the screen when one end is outside it, then project its control points
    local tMin = 0;
    local tMax = 1;
    local off0 = offScreen(wx0, wy0, wz0);
    local off2 = offScreen(wx2, wy2, wz2);

    if (off0 or off2) then
        local bcurve = Bezier3D_2:new({
            { P0x, P0y, P0z },
            { P1x, P1y, P1z },
            { P2x, P2y, P2z }
        });

        local p1, p2, p3;
        if (off0) then
            local _, tZero = bcurve:solveZeros(frameViewProj);

            if (not tZero) then return; end

            tMin = tZero;
            p1, p2, p3 = table.unpack(bcurve:subdivide(tZero)[2]);
        else
            local tZero = bcurve:solveZeros(frameViewProj);
            if (not tZero) then return; end

            tMax = tZero;
            p1, p2, p3 = table.unpack(bcurve:subdivide(tZero)[1]);
        end

        P0x, P0y, P0z = project(p1[1], p1[2], p1[3]);
        P1x, P1y, P1z = project(p2[1], p2[2], p2[3]);
        P2x, P2y, P2z = project(p3[1], p3[2], p3[3]);
    else
        P0x, P0y, P0z = wx0, wy0, wz0;
        P1x, P1y, P1z = project(P1x, P1y, P1z);
        P2x, P2y, P2z = wx2, wy2, wz2;
    end

    if (progress < tMin) then
        return;
    end

    -- Screen-space curve coefficients and the normal of the plane it lies in
    ax, ay, az = P0x, P0y, P0z;
    bx, by, bz = 2 * (P1x - P0x), 2 * (P1y - P0y), 2 * (P1z - P0z);
    cx, cy, cz = P0x - 2 * P1x + P2x, P0y - 2 * P1y + P2y, P0z - 2 * P1z + P2z;

    nx = (P2y - P0y) * (P1z - P0z) - (P2z - P0z) * (P1y - P0y);
    ny = (P2z - P0z) * (P1x - P0x) - (P2x - P0x) * (P1z - P0z);
    nz = (P2x - P0x) * (P1y - P0y) - (P2y - P0y) * (P1x - P0x);
    local nScale = (nx * nx + ny * ny + nz * nz) ^ (-0.5);
    nx, ny, nz = nx * nScale, ny * nScale, nz * nScale;

    -- Fewer segments for arcs that are short on screen: one per segmentPixels, between the two limits
    local segmentPixels = 8;
    local minSegments = 12;
    local screenLength = math.sqrt((P1x - P0x) ^ 2 + (P1y - P0y) ^ 2) + math.sqrt((P2x - P1x) ^ 2 + (P2y - P1y) ^ 2);
    local segments = math.max(minSegments, math.min(maxSegments, math.floor(screenLength / segmentPixels)));

    -- One pair at each end plus one per segment sample
    local total = (segments + 2) * 2;
    local reversed = P2z > P0z;

    local tSize = 1 / (tMax - tMin);
    local tAdjusted = (progress - tMin) * tSize;
    local tEnd = math.min(tAdjusted, 1);
    local tInterval = 0.95 * (tEnd) / (segments - 1);

    -- Make room, then write this arc after the last one. The buffer is locked for the first arc of a
    -- frame and stays locked until they are all drawn.
    if (nextVertex + maxArcVertices > bufferVertices) then
        flush();
    end
    if (not lockedData) then
        local _, ptr = vertexBuffer:Lock(0, 0, 0);
        lockedData = ffi.cast('struct VertFormatFFFFUFF*', ptr);
    end

    local base = nextVertex;
    local vdata = lockedData + base;

    writePair(vdata, 0, total, reversed, 0, tMin > 0 and 0.25 or 0, color);

    -- First and last samples are always the same length
    local t = 0.025;
    for pair = 1, segments do
        writePair(vdata, pair, total, reversed, t, 0.25 + t / 2, color);
        t = t + tInterval;
    end

    t = t + 0.025 - tInterval;
    local ex, ey, ez = writePair(vdata, segments + 1, total, reversed, t, tMax < tAdjusted and 0.75 or 1, color);

    if (tMax >= tAdjusted and progress < 1) then
        orb = orb and true;
        writeVertex(vdata, total, ex - orbRadius, ey - orbRadius, ez, color, 0, 0);
        writeVertex(vdata, total + 1, ex + orbRadius, ey - orbRadius, ez, color, 1, 0);
        writeVertex(vdata, total + 2, ex - orbRadius, ey + orbRadius, ez, color, 0, 1);
        writeVertex(vdata, total + 3, ex + orbRadius, ey + orbRadius, ez, color, 1, 1);
    else
        orb = false;
    end

    arcTex = arcTex or getTexture(addon.path .. 'assets/beam.png');

    batchCount = batchCount + 1;
    batchStart[batchCount] = base;
    batchTriangles[batchCount] = total - 2;
    batchOrb[batchCount] = orb and base + total or false;
    nextVertex = base + total + 4;
end

-- The arcs of one frame are drawn back to back, so the shared state is only set once
applyStates = function()
    if (not statesApplied) then
        statesApplied = true;

        d3d8dev:SetStreamSource(0, vertexBuffer, ffi.sizeof(vertFormat));

        d3d8dev:SetTextureStageState(0, C.D3DTSS_COLOROP, C.D3DTOP_BLENDTEXTUREALPHA);
        d3d8dev:SetTextureStageState(0, C.D3DTSS_COLORARG1, C.D3DTA_TEXTURE);
        d3d8dev:SetTextureStageState(0, C.D3DTSS_COLORARG2, C.D3DTA_DIFFUSE);
        -- Texture alpha scaled by the vertex alpha, which is 255 except while fading
        d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAOP, C.D3DTOP_MODULATE);
        d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAARG1, C.D3DTA_TEXTURE);
        d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAARG2, C.D3DTA_DIFFUSE);

        if (depthTest) then
            -- Every point of a line carries how deep in the picture it is. With the test on, the
            -- graphics card leaves out each pixel of a line that the game has already drawn something
            -- nearer over: a wall, the ground, a character.
            local _, zEnable = d3d8dev:GetRenderState(C.D3DRS_ZENABLE);
            local _, zFunc = d3d8dev:GetRenderState(C.D3DRS_ZFUNC);
            keptZEnable, keptZFunc = zEnable, zFunc;
            d3d8dev:SetRenderState(C.D3DRS_ZENABLE, 1);
            d3d8dev:SetRenderState(C.D3DRS_ZFUNC, C.D3DCMP_LESSEQUAL);
        else
            d3d8dev:SetRenderState(C.D3DRS_ZENABLE, 0);
        end
        d3d8dev:SetRenderState(C.D3DRS_ALPHABLENDENABLE, 1);
        d3d8dev:SetRenderState(C.D3DRS_SRCBLEND, C.D3DBLEND_SRCALPHA);
        d3d8dev:SetRenderState(C.D3DRS_DESTBLEND, C.D3DBLEND_INVSRCALPHA);

        d3d8dev:SetVertexShader(vertFormatMask);
    end
end

return {
    beginFrame = beginFrame,
    draw = drawArc,
    endFrame = flush
};
