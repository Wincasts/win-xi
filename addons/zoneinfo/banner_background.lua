-- One lazy, bounded image cache shared by the ImGui and GDI banner paths.
local M = {};

function M.valid_file(file)
    return type(file) == 'string' and #file <= 255 and file ~= ''
        and not file:find('[/\\:]') and not file:find('..', 1, true)
        and not file:find('[%z\1-\31]')
        and (file:lower():match('%.png$') or file:lower():match('%.jpg$')
            or file:lower():match('%.jpeg$') or file:lower():match('%.bmp$')) ~= nil;
end

-- Flag names come from data/region_flags.lua, never from what is typed in the settings.
function M.valid_flag(flag)
    return type(flag) == 'string' and flag:match('^[%l%d_]+$') ~= nil and #flag <= 64;
end

local function load(file)
    local ffi, d3d = require('ffi'), require('d3d8');
    local device = d3d.get_device();
    if device == nil then error('Direct3D device unavailable'); end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    local path = addon.path .. 'assets/backgrounds/' .. file;
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then
        error('Could not load ' .. file);
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    local desc = ffi.new('D3DSURFACE_DESC[1]');
    if texture.lpVtbl.GetLevelDesc(texture, 0, desc) ~= ffi.C.S_OK then error('Could not read image dimensions'); end
    return { texture = texture, handle = tonumber(ffi.cast('uint32_t', texture)),
        width = tonumber(desc[0].Width), height = tonumber(desc[0].Height) };
end

-- The file to show, under assets/backgrounds: a region's flag where there is one and flags are
-- wanted, otherwise the image chosen in the settings, otherwise nothing.
function M.wanted(d, flag)
    if flag and d.backgroundFlags[1] and M.valid_flag(flag) then return 'flags/' .. flag .. '.png'; end
    if d.backgroundEnabled[1] and d.backgroundFile[1] ~= '' then return d.backgroundFile[1]; end
    return nil;
end

function M.new(loader)
    local self = {};
    loader = loader or load;
    function self:clear()
        self.file, self.image, self.error, self.retry = nil, nil, nil, nil;
    end
    -- flag: the name of a bundled region flag, shown in place of the chosen image where it is given.
    function self:get(d, now, flag)
        local file = M.wanted(d, flag);
        if not file then self:clear(); return nil; end
        local bundled = file ~= d.backgroundFile[1];
        if self.file ~= file then self:clear(); self.file = file; end
        if not bundled and not M.valid_file(file) then self.error = 'Choose a PNG, JPG or BMP filename (no directories).'; return nil; end
        if self.image then return self.image; end
        if now < (self.retry or 0) then return nil; end
        self.retry = now + 5;
        local ok, image = pcall(loader, file);
        if ok and image and image.width > 0 and image.height > 0 then
            image.fit = bundled; -- A flag keeps its proportions; a chosen image fills the size given.
            self.image, self.error = image, nil;
        else
            self.error = 'Background unavailable: ' .. tostring(ok and 'invalid image' or image);
        end
        return self.image;
    end
    return self;
end

-- Background dimensions are independent of text, avoiding layout jumps between lines.
function M.bounds(d, screen_width, image)
    local width, height = d.backgroundSize[1], d.backgroundSize[2];
    local x = (d.centered[1] and screen_width / 2 or 0) + d.position[1];
    if d.alignment == 'center' then x = x - width / 2;
    elseif d.alignment == 'right' then x = x - width; end
    x = x + d.backgroundOffset[1];
    local y = d.position[2] + d.backgroundOffset[2];
    if image and image.fit then
        -- As large as the size given allows, in the middle of it, with the image's own proportions.
        local scale = math.min(width / image.width, height / image.height);
        local w, h = image.width * scale, image.height * scale;
        return x + (width - w) / 2, y + (height - h) / 2, w, h;
    end
    return x, y, width, height;
end

function M.draw_imgui(image, d, screen_width)
    local imgui = require('imgui');
    local x, y, width, height = M.bounds(d, screen_width, image);
    local draw = imgui.GetWindowDrawList();
    local io = imgui.GetIO();
    -- The image may extend outside the auto-sized text window, but not the screen.
    draw:PushClipRect({ 0, 0 }, { screen_width, io.DisplaySize.y or io.DisplaySize[2] }, false);
    local ok, err = pcall(function()
        draw:AddImage(image.handle, { x, y }, { x + width, y + height }, { 0, 0 }, { 1, 1 },
            imgui.GetColorU32({ 1, 1, 1, d.backgroundOpacity[1] }));
    end);
    draw:PopClipRect();
    if not ok then error(err, 0); end
end

local native;
function M.draw_gdi(sprite, image, d, screen_width, alpha)
    local ffi, d3d = require('ffi'), require('d3d8');
    if not native then
        native = { rect = ffi.new('RECT'), scale = ffi.new('D3DXVECTOR2'), position = ffi.new('D3DXVECTOR2') };
    end
    local x, y, width, height = M.bounds(d, screen_width, image);
    native.rect.left, native.rect.top, native.rect.right, native.rect.bottom = 0, 0, image.width, image.height;
    native.scale.x, native.scale.y = width / image.width, height / image.height;
    native.position.x, native.position.y = x, y;
    sprite:Draw(image.texture, native.rect, native.scale, nil, 0.0, native.position,
        d3d.D3DCOLOR_ARGB(math.floor(255 * alpha * d.backgroundOpacity[1] + .5), 255, 255, 255));
end

return M;
