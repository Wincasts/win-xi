local function WriteItemArray(input, file, depth)
    local resMgr = AshitaCore:GetResourceManager();
    for _,v in ipairs(input) do
        local resource = resMgr:GetItemById(v);
        file:write(string.rep(' ', depth));
        file:write(v);
        file:write(',');
        if resource then
            file:write(' --' .. resource.Name[1]);
        else
            file:write(' --Resource Lookup Failed')
        end
        file:write('\n');
    end
end

local function WriteNumericArray(input, file)
    local first = true;
    for _,v in ipairs(input) do
        if not first then
            file:write(', ');
        end
        file:write(v);
        first = false;
    end
end

local function SaveFunction(self, characterSpecific)
    if not self.Path then
        print(chat.header(addon.name) .. chat.error('No path is set.  Could not save settings.'));
    end
    self:CreateDirectories(('%sconfig\\addons\\%s\\input\\'):fmt(AshitaCore:GetInstallPath(), addon.name));
    self:CreateDirectories(('%sconfig\\addons\\%s\\output\\'):fmt(AshitaCore:GetInstallPath(), addon.name));
    local file = io.open(self.Path, 'w');
    file:write('--Automatically generated settings file for: ' .. addon.name .. '\n');
    file:write('local settings = {\n');
    if characterSpecific then
        file:write('    CharacterSpecific = ' .. tostring(self.CharacterSpecific) .. ',\n');
    end
    file:write(string.format('    Scale=%f,\n', self.Scale));
    file:write(string.format('    DetailScale=%f,\n', self.DetailScale));
    file:write(string.format('    Alpha=%f,\n', self.Alpha));
    file:write(string.format('    DetailView=%s,\n', self.DetailView and 'true' or 'false'));
    if (self.Color) then
        file:write(string.format('    Color={%f,%f,%f,%f}\n,\n', self.Color[1], self.Color[2], self.Color[3], self.Color[4]));
    end
    file:write(string.format('    Padding=%d,\n', math.floor(tonumber(self.Padding) or 10)));
    file:write(string.format('    GrowFrom=\'%s\',\n', tostring(self.GrowFrom or 'TopLeft')));
    for _, key in ipairs({ 'BackgroundColor', 'BorderColor' }) do
        local color = self[key];
        if (type(color) == 'table') then
            file:write(string.format('    %s={%f,%f,%f,%f},\n', key, color[1], color[2], color[3], color[4]));
        end
    end
    file:write(string.format('    MobFormat=\'%s\',\n', self.MobFormat:gsub('\'', '\\\'')));
    file:write(string.format('    PlayerFormat=\'%s\',\n', self.PlayerFormat:gsub('\'', '\\\'')));
    file:write(string.format('    NPCFormat=\'%s\',\n', self.NPCFormat:gsub('\'', '\\\'')));
    file:write(string.format('    PetFormat=\'%s\',\n', self.PetFormat:gsub('\'', '\\\'')));
    file:write(string.format('    NothingFormat=\'%s\',\n', self.NothingFormat:gsub('\'', '\\\'')));
    file:write('};\n\n');
    file:write('return settings;');
    file:close();
end

local defaultSettings = {
    CharacterSpecific = true,
    Scale = 1.2,
    Alpha = 0.8,
    DetailScale = 1,
    DetailView = false,
    Color = nil,
    BackgroundColor = { 0.08, 0.08, 0.08, 0.8 }, -- every window's background (Appearance tab)
    BorderColor = { 0.69, 0.68, 0.78, 1.0 },     -- every window's border, and the tint of its controls
    Padding = 10, -- space between the border and the content of the bar and detail view (Appearance tab)
    GrowFrom = 'TopLeft', -- the corner of the bar and detail view that stays put as they change size (Appearance tab)
    MobFormat = '$name$joblevel $aggro$LB$physmagic',
    PlayerFormat = '$name$joblevel Id:$id $position1',
    NPCFormat = '$name Index:$index Id:$id $position1',
    PetFormat = '$name($owner) Id:$id $position1',
    NothingFormat = ''
};

local settingsManager = require('settingsmanager'):New();
settingsManager.Save = SaveFunction;
settingsManager:InitializeWithGui(defaultSettings, require('gui'));
return settingsManager;