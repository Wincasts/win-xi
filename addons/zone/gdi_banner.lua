-- Experimental Zonename-style full-string textures. No ImGui glyph/atlas access.
local bit = require('bit');
local background = require('banner_background');
local M = {};

local function argb(color)
    local function byte(n) return math.floor(math.max(0, math.min(1, n)) * 255 + .5); end
    return bit.bor(bit.lshift(byte(color[4]), 24), bit.lshift(byte(color[1]), 16),
        bit.lshift(byte(color[2]), 8), byte(color[3]));
end

function M.new(loader)
    local self = { objects = {}, styles = {} };

    -- Track applied values, not textures; the library owns device-reset invalidation.
    local function apply(obj, style, key, value)
        if style[key] ~= value then
            obj['set_' .. key](obj, value);
            style[key] = value;
        end
    end

    local diagnostics = loader == nil;
    local function checkpoint(stage, reset)
        if not diagnostics or not addon or not addon.path then return; end
        local file = io.open(addon.path .. 'gdi-diagnostic.txt', reset and 'w' or 'a');
        if file then file:write(stage .. '\n'); file:close(); end
    end
    loader = loader or function()
        -- A private instance, not require('gdifonts.include') shared with another backend.
        return dofile(addon.path .. 'gdifonts/include.lua');
    end;

    function self:library()
        if self.failed then error(self.failed, 0); end
        if not self.lib then
            checkpoint('Initialize private GDI library/manager/sprite', true);
            local ok, lib = pcall(loader);
            if not ok then
                self.failed = 'Experimental GDI initialization failed: ' .. tostring(lib);
                error(self.failed, 0);
            end
            self.lib = lib;
            lib:set_auto_render(false);
            checkpoint('Private GDI library ready');
        end
        return self.lib;
    end

    function self:draw(rows, d, width, title_color, detail_color, is_area, image, alpha)
        local lib = self:library();
        local x = (d.centered[1] and width / 2 or 0) + d.position[1];
        local y = d.position[2];
        local title_packed, detail_packed, outline_packed = argb(title_color), argb(detail_color), argb(d.outlineColor);
        -- Hide lines from the previous popup before enabling this popup's rows.
        for _, obj in pairs(self.objects) do obj:set_visible(false); end
        for _, row in ipairs(rows) do
            local obj = self.objects[row.key];
            if not obj then
                obj = lib:create_object({ visible = false, text = '', outline_width = 0 });
                self.objects[row.key] = obj;
                self.styles[row.key] = {};
            end

            local style = self.styles[row.key];
            local prefix = (is_area and 'area' or 'zone') .. (row.title and 'Title' or 'Detail');
            local family = d[prefix .. 'GdiFamily'][1];
            if not lib:get_font_available(family) then family = 'Arial'; end
            assert(lib:get_font_available(family), 'GDI font unavailable (including Arial fallback)');
            apply(obj, style, 'font_family', family);
            apply(obj, style, 'font_height', row.size);
            local bold = row.title and d.gdiTitleBold[1] or (not row.title and d.gdiDetailBold[1]);
            apply(obj, style, 'font_flags', bold and lib.FontFlags.Bold or lib.FontFlags.None);
            apply(obj, style, 'font_color', row.title and title_packed or detail_packed);
            apply(obj, style, 'outline_width', d.outline[1]);
            apply(obj, style, 'outline_color', outline_packed);
            apply(obj, style, 'font_alignment', d.alignment == 'left' and lib.Alignment.Left or
                (d.alignment == 'right' and lib.Alignment.Right or lib.Alignment.Center));
            apply(obj, style, 'text', row.words);

            -- Query the library every frame so native invalidation still takes effect.
            local rebuilding = obj.is_dirty;
            if rebuilding then checkpoint(('Rasterize %s: %s, %d px, %q'):format(row.key, family, row.size, row.words)); end
            local texture, rect = obj:get_texture();
            if rebuilding then checkpoint('Rasterize returned: ' .. row.key); end
            assert(texture and rect and rect.bottom > 0, 'GDI failed to rasterize banner line: ' .. row.key);
            obj:set_position_x(x);
            obj:set_position_y(y);
            obj:set_opacity(row.alpha);
            obj:set_visible(row.alpha > .01);
            -- Preserve space for delayed/expired rows, just as the ImGui renderer does.
            y = y + tonumber(rect.bottom) + d.spacing[1];
        end
        if image then
            lib:render(function(sprite) background.draw_gdi(sprite, image, d, width, alpha); end);
        else
            lib:render();
        end
        return true;
    end

    function self:shutdown()
        if self.lib then
            for _, obj in pairs(self.objects) do self.lib:destroy_object(obj); end
            self.lib:set_auto_render(false);
            self.lib:destroy_interface();
        end
        self.objects, self.styles, self.lib, self.failed = {}, {}, nil, nil;
    end
    return self;
end

return M;
