-- Player icons/mastery stars: selectable active DAT, bundled atlas, or custom PNG.
-- DAT artwork/mapping is cached and owned by Name, never borrowed from game memory.
local rectangles = require('assets.player-icons');
local bundledOverlays = require('assets.player-icon-overlays');
local icons = {};
icons.Sources = {
    { key = 'game', label = 'Game DATs' },
    { key = 'bundled', label = 'Bundled' },
    { key = 'custom', label = 'Custom' },
};
icons.CustomFile = 'player-icons-custom.png';
local bundledPlaces = {};
for byte, rect in pairs(rectangles) do
    bundledPlaces[byte] = { rect[1] / 256, rect[2] / 256, rect[3] / 256, rect[4] / 256 };
end
local outlineRadius, outlineOpacity, plates = 1, 1, nil;

-- Match text's screen/Lens/distance scaling, but never use its outline setting.
function icons.ConfigureOutline(options, size, scale, fit)
    local width = options.iconOutline and options.iconOutline[1] or 1;
    width = math.max(0, math.min(3, width));
    outlineRadius = width > 0 and math.max(1, math.floor(math.min(width, math.max(1, math.floor(size / 8 + 0.5))) * scale)) or 0;
    if outlineRadius > 0 and fit < 1 then
        outlineRadius = math.max(1, math.floor(outlineRadius * fit + 0.5));
    end
    outlineOpacity = math.max(0, math.min(100, options.iconOutlineOpacity and options.iconOutlineOpacity[1] or 100)) / 100;
end

-- All outlined icons go through this path; text, badges and mastery stars do not.
function icons.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, tight)
    plates = plates or require('winxi.nameplates');
    plates.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot,
        outlineRadius > 0 and outlineOpacity > 0, outlineOpacity, nil, tight, outlineRadius);
end

local handle, places, overlays = nil, bundledPlaces, bundledOverlays;
local selected, game, reader, problem, retry = nil, nil, nil, nil, 0;

function icons.ValidSource(source)
    for _, choice in ipairs(icons.Sources) do
        if choice.key == source then return true; end
    end
    return false;
end

local function loadGame()
    reader = reader or require('playerdat');
    return reader.Load();
end

-- The shared file loader handles owned PNG textures and throttles failed loads.
-- Game DAT failures retry at most every ten seconds; successful reads/uploads
-- happen only once per selection. Switching sources drops the owned DAT atlas.
function icons.Release()
    if game then reader.Release(game); end
    selected, game, problem, retry = nil, nil, nil, 0;
    handle, places, overlays = nil, bundledPlaces, bundledOverlays;
end

function icons.Begin(loadSheet, source, needed)
    if needed == false then icons.Release(); return false; end
    if not icons.ValidSource(source) then source = 'game'; end
    if source ~= selected then
        if game then reader.Release(game); end
        selected, game, problem, retry = source, nil, nil, 0;
    end
    handle, places, overlays = nil, bundledPlaces, bundledOverlays;
    if source == 'game' then
        if not game and os.clock() >= retry then
            retry = os.clock() + 10;
            local ok, loaded, why = pcall(loadGame);
            if ok and loaded then
                game, problem = loaded, nil;
            else
                problem = tostring(ok and why or loaded);
            end
        end
        if game then
            handle, places, overlays = game.address, game.places, game.overlays;
            return handle ~= nil and handle ~= 0;
        end
    elseif source == 'custom' and loadSheet then
        local loaded = loadSheet(icons.CustomFile);
        if loaded ~= nil and loaded ~= 0 then
            handle, problem = loaded, nil;
            return true;
        end
        problem = 'Could not load assets/' .. icons.CustomFile;
    end
    if loadSheet then
        local loaded = loadSheet('player-icons.png');
        handle = loaded ~= nil and loaded ~= 0 and loaded or nil;
    end
    return handle ~= nil;
end

function icons.Diagnostics()
    local actual = not handle and 'unavailable' or (game and 'game' or (problem and 'bundled fallback' or selected));
    local dimensions = game and game.width and ('; %dx%d'):format(game.width,game.height) or '';
    return ('selected %s; active %s%s%s'):format(selected or 'inactive',actual or 'inactive',dimensions,
        problem and '; source failure (details omitted)' or '');
end
function icons.Texture() return handle; end
function icons.Problem(source)
    return (source == nil or source == selected) and problem or nil;
end
function icons.Place(byte)
    return handle ~= nil and (places[byte] or false) or false;
end
-- Composite status badges use independent geometry, not another full-size cell.
function icons.Overlays(byte) return overlays[byte]; end

return icons;
