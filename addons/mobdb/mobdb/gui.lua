require('common');

local imgui = require('imgui');
local style = require('style');
local ui = T{
    IsOpen = T{ false },
}

local SettingsGui = {
    IsOpen = { false },
    SubWindows = {};
    Theme = {
        Header = { 1.0, 0.75, 0.55, 1.0 },
        Command = { 0.0, 1.0, 0.2, 1.0 }
    }
};

local speedExplanation = 'Entity speed, displayed in format 100% 125% etc.';
local speedRelativeExplanation = 'Entity speed, displayed in format +12.5% -12.5% etc.'
if (ashita.addons_version < 2.2) then
    speedExplanation = 'Entity speed, displayed in format 100%% 125%% etc.';
    speedRelativeExplanation = 'Entity speed, displayed in format +12.5%% -12.5%% etc.'
end

local TokenHelpData = {
    { Token='$name', Explanation='The name of your current target.'},
    { Token='$index', Explanation='The zone-specific index of your current target.'},
    { Token='$hexindex', Explanation='The zone-specific index of your current target, in hex notation.'},
    { Token='$hexid', Explanation='The game-specific id of your current target, in hex notation.'},
    { Token='$id', Explanation='The game-specific id of your current target.'},
    { Token='$zone', Explanation='Your current zone\'s name.'},
    { Token='$job', Explanation='Your current target\'s job if available, ??? if not.'},
    { Token='$level', Explanation='Your current target\'s level if available, ??? if not.'},
    { Token='$joblevel', Explanation='Format [Lv33-37] [Lv33-37 WAR] [WAR35/SAM18] depending on available information.  Nothing if not available.'},
    { Token='$position1', Explanation='Position in the format "(X, Y) Z:Z" with 2 decimal places.'},
    { Token='$position2', Explanation='Position in the format "(X,Y) Z:Z" with no decimals.'},
    { Token='$position3', Explanation='Position in the format "X:X Y:Y Z:Z" with 2 decimal places.'},
    { Token='$position4', Explanation='Position in the format "X:X Y:Y Z:Z" with no decimals.'},
    { Token='$strength', Explanation='Graphical display of weapons and elements the mob is strong against.'},
    { Token='$weakness', Explanation='Graphical display of weapons and elements the mob is weak against.'},
    { Token='$physical', Explanation='Graphical display of weapon types the mob is strong or weak against.'},
    { Token='$magical', Explanation='Graphical display of elements the mob is strong or weak against'},
    { Token='$physmagic', Explanation='Graphical display of elements and weapons the mob is strong or weak against.'},
    { Token='$immunity', Explanation='Graphical display of debuffs that a monster is immune to.' },
    { Token='$hpp', Explanation='The target\'s current HP percentage.'},
    { Token='$dynamic', Explanation='Dynamic if the monster is a custom spawn, Static if it is a normal spawn.'},
    { Token='$aggro', Explanation='Graphical display indicating whether the target aggros, links, is a NM, and how it detects you.'},
    { Token='$speed', Explanation=speedExplanation},
    { Token='$speedrelative', Explanation=speedRelativeExplanation}, 
    { Token='$debugflags', Explanation='Show all flags for debug purposes.' },
    { Token='$debugimmunity', Explanation='Show all immunity icons for debug purposes.' },
    { Token='$direction', Explanation='Show the cardinal direction in which the target resides.' },
    { Token='$drops', Explanation='Show target drops as a comma-seperated line.' },
    { Token='$dropssplit', Explanation='Show target drops with each drop on a new line.' },
    { Token='$notes', Explanation='Any notes saved on the target in the database.  Multiple notes always take a new line.' }
};

function SettingsGui:Initialize(parent)
    self.Parent = parent;
    self.TokenEditor = {
        IsOpen = { false },
        Categories = { 'Mob', 'Player', 'NPC', 'Pet', 'Nothing' },
        Strings = {};
    };
    self.TokenHelper = {
        IsOpen = { false }
    };
    for _,category in pairs(self.TokenEditor.Categories) do
        self.TokenEditor.Strings[category] = { self.Parent[category .. 'Format'] };
    end
end

-- A colour picker for one of the window colours. The colour is changed in place as it is dragged, so
-- every window follows it at once, and is saved when the picker is let go.
function SettingsGui:ColorSetting(label, key, tooltip)
    local color = self.Parent[key];
    if (type(color) ~= 'table') then
        return;
    end

    local changed = imgui.ColorEdit4(label, color);
    if (tooltip and imgui.IsItemHovered()) then
        imgui.SetTooltip(tooltip);
    end

    -- builds without the "let go" test save on every change instead
    if (imgui.IsItemDeactivatedAfterEdit ~= nil) then
        if (imgui.IsItemDeactivatedAfterEdit()) then
            self.Parent:Save(self.Parent.CharacterSpecific);
        end
    elseif (changed) then
        self.Parent:Save(self.Parent.CharacterSpecific);
    end
end

function SettingsGui:RenderAppearance()
    imgui.TextColored(self.Theme.Header, 'Window Colors');
    self:ColorSetting('Background Color', 'BackgroundColor',
        'The background of every MobDB window.\nThe info bar\'s own Opacity setting (General tab) replaces this colour\'s alpha on the bar.');
    self:ColorSetting('Border Color', 'BorderColor',
        'The border of every MobDB window. Tabs, buttons, sliders and other controls are tinted from it.');

    if (imgui.Button('Reset Colors')) then
        local defaults = self.Parent.DefaultSettings;
        for _, key in ipairs({ 'BackgroundColor', 'BorderColor' }) do
            local color, default = self.Parent[key], defaults and defaults[key];
            if (type(color) == 'table' and type(default) == 'table') then
                color[1], color[2], color[3], color[4] = default[1], default[2], default[3], default[4];
            end
        end
        self.Parent:Save(self.Parent.CharacterSpecific);
    end
end

-- The settings windows keep their title bars and close buttons, and take the shared colours
function SettingsGui:Render()
    -- nothing is pushed on the frames (nearly all of them) when no settings window is open
    local anyOpen = self.IsOpen[1] or self.TokenEditor.IsOpen[1];
    if anyOpen then
        style.Push();
    end

    self:RenderWindows();

    if anyOpen then
        style.Pop();
    end
end

function SettingsGui:RenderWindows()
    if (self.TokenEditor.IsOpen[1]) then
        if (imgui.Begin('MobDB Token Editor', self.TokenEditor.IsOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
            for _,category in ipairs(self.TokenEditor.Categories) do
                imgui.TextColored(self.Theme.Header, string.format('%s Targeted', category));
                imgui.PushItemWidth(400);
                if imgui.InputText('##Token_' .. category, self.TokenEditor.Strings[category], 1080) then
                   self.Parent[category .. 'Format'] = self.TokenEditor.Strings[category][1];
                   gBar:ParseFormats(category .. 'Format'); 
                   self.Parent:Save(self.Parent.CharacterSpecific);
                end
                imgui.PopItemWidth();
            end
            if (imgui.Button('Help')) then
                self.TokenHelper.IsOpen[1] = true;
            end
        end
        imgui.End();

        if (self.TokenHelper.IsOpen[1]) then
            imgui.SetNextWindowSize({ 610, 597, });
            if (imgui.Begin('MobDB Token Help', self.TokenHelper.IsOpen, ImGuiWindowFlags_NoResize)) then
                for _,entry in pairs(TokenHelpData) do
                    imgui.TextColored(self.Theme.Header, entry.Token);
                    imgui.TextWrapped('  ' .. entry.Explanation);                    
                end
            end
            imgui.End(); 
        end
    else
        self.TokenHelper.IsOpen[1] = false;
        if (self.IsOpen[1]) then
            if (imgui.Begin(string.format('%s v%s', addon.name, addon.version), self.IsOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
                if imgui.BeginTabBar('##mobdb.config') then
                    if imgui.BeginTabItem('General') then
                        imgui.TextColored(self.Theme.Header, 'Save Mode');
                        if imgui.Checkbox('Character-Specific', { self.Parent.CharacterSpecific }) then
                            self.Parent:ToggleCharacterSpecific();
                            self.SubWindows = T{};
                        end
                        local details = { self.Parent.DetailView };
                        imgui.TextColored(self.Theme.Header, 'Detailed View')
                        if (imgui.Checkbox('Enabled##MobDB Detailed View', details)) then
                            self.Parent.DetailView = details[1];
                            self.Parent:Save(self.Parent.CharacterSpecific);
                        end
                        imgui.TextColored(self.Theme.Header, 'Draw Scale (Bar)');
                        local scale = { self.Parent.Scale };
                        if (imgui.SliderFloat('##BarScale', scale, 0.5, 3.0, '%.2f', ImGuiSliderFlags_AlwaysClamp)) then
                            if (scale[1] ~= self.Parent.Scale) then
                                self.Parent.Scale = scale[1];
                                self.Parent:Save(self.Parent.CharacterSpecific);
                            end
                        end
                        imgui.TextColored(self.Theme.Header, 'Draw Scale (Details)');
                        local scale = { self.Parent.DetailScale };
                        if (imgui.SliderFloat('##DetailScale', scale, 0.5, 3.0, '%.2f', ImGuiSliderFlags_AlwaysClamp)) then
                            if (scale[1] ~= self.Parent.DetailScale) then
                                self.Parent.DetailScale = scale[1];
                                self.Parent:Save(self.Parent.CharacterSpecific);
                            end
                        end
                        imgui.TextColored(self.Theme.Header, 'Opacity');
                        local alpha = { self.Parent.Alpha };
                        if (imgui.SliderFloat('##Alpha', alpha, 0.1, 1.0, '%.2f', ImGuiSliderFlags_AlwaysClamp)) then
                            if (alpha[1] ~= self.Parent.Alpha) then
                                self.Parent.Alpha = alpha[1];
                                self.Parent:Save(self.Parent.CharacterSpecific);
                            end
                        end
                        if (imgui.Button('Edit Tokens')) then
                            self.TokenEditor.IsOpen[1] = true;
                        end
                        imgui.EndTabItem();
                    end

                    if imgui.BeginTabItem('Appearance') then
                        self:RenderAppearance();
                        imgui.EndTabItem();
                    end

                    imgui.EndTabBar();
                end
            end
            imgui.End();
        end
    end
end

return SettingsGui;