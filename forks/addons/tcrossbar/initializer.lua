--Initialize Globals..
require('helpers');
gTextureCache    = require('texturecache');
gBindings        = require('bindings');
gBindingGUI      = require('bindinggui');
gConfigGUI       = require('configgui');
gController      = require('controller');
gSingleDisplay   = require('singledisplay');
gDoubleDisplay   = require('doubledisplay');
settings         = require('settings');

local d3d8       = require('d3d8');
local ffi        = require('ffi');
local scaling    = require('scaling');
gToggleHide = false;

--Create directories..
local controllerConfigFolder = string.format('%sconfig/addons/%s/resources/controllers', AshitaCore:GetInstallPath(), addon.name);
if not ashita.fs.exists(controllerConfigFolder) then
    ashita.fs.create_directory(controllerConfigFolder);
end
local layoutConfigFolder = string.format('%sconfig/addons/%s/resources/layouts', AshitaCore:GetInstallPath(), addon.name);
if not ashita.fs.exists(layoutConfigFolder) then
    ashita.fs.create_directory(layoutConfigFolder);
end

--Initialize settings..
local defaultSettings = T{
    --Layouts tab..
    SingleLayout = 'classic',
    SingleScale = 1.0,
    DoubleLayout = 'classic',
    DoubleScale = 1.0,
    TriggerDuration = 0.25,
    ShowEmpty = true,
    ShowFrame = true,
    ShowFrameShadow = true, -- winxi: the theme's drop shadow under each frame
    ShadowMatchTheme = true, -- winxi: the shadow as the theme's Shadow settings, or with false as these
    ShadowOpacity = 30, -- winxi: percent
    ShadowOffset = 2, -- winxi: pixels down and to the right
    ShadowBlur = 3, -- winxi: pixels of soft edge
    ShowSwipe = true, -- winxi: the cooldown swipe over each icon (cooldown.lua)
    SwipeOpacity = 60, -- winxi: how dark the swipe is, 0 to 100
    ShowLowMP = true, -- winxi: Low MP Color over a spell or ability whose MP cost is not met
    LowMPColor = { 0.20, 0.40, 1.00, 0.45 },
    ShowLowTP = true, -- winxi: Low TP Color over a weapon skill or ability whose TP cost is not met
    LowTPColor = { 1.00, 0.45, 0.10, 0.40 },
    ShowGloss = false, -- winxi: a glossy light over each icon (gloss.lua)
    GlossOpacity = 100, -- winxi: how strong the gloss is, 0 to 100
    RecastSize = 16, -- winxi: the recast timer's size in pixels, centred on the icon in the theme's text (recasttext.lua)
    ShowBackdrop = true, -- winxi: a soft black backdrop behind the crossbar (backdrop.lua)
    BackdropOpacity = 50, -- winxi: how dark its middle is, 0 to 100
    BackdropSize = 130, -- winxi: how far it reaches, percent of the panel
    FrameBorder = 'none', -- winxi: the theme's border art round each frame (frameborder.lua)
    ShowCost = true,
    ShowCross = true,
    ShowFade = true,
    ShowName = true,
    ShowRecast = true,
    ShowHotkey = false,
    ShowSkillchainIcon = true,
    ShowSkillchainAnimation = true,
    ShowTrigger = true,
    ShowReadyPulse = true,
    ReadyPulseHz = 1.0,
    ReadyPulseMinAlpha = 0.45,
    ShowPalette = true,
    ShowSinglePalette = false,

    --Behavior tab..
    AutoDetectSubjob = true,
    BindingSubjob = 0,
    ClickToActivate = true,
    HideWhileZoning = true,
    HideWhileCutscene = true,
    HideWhileMap = true,
    HideWhileChat = true,
    DefaultSelectTarget = false,
    ShowUnavailableActions = false,
    EnableDoubleTap = true,
    EnablePriority = true,
    ShowDoubleDisplay = true,
    LTRTMode = 'FullDouble',
    SwapToSingleDisplay = false,
    AllowInventoryPassthrough = true,

    --Controller Tab..
    Controller = 'dualsense',
    BindMenuTimer = 1,
    TapTimer = 0.4,
};
gSettings = settings.load(defaultSettings);

local function UpdateSettings()
    local version = tonumber(addon.version);
    if (gSettings.Version ~= version) then
        if (gSettings.SwapToSingleDisplay ~= nil) then
            if (gSettings.SwapToSingleDisplay == true) then
                gSettings.LTRTMode = 'Single';
            else
                gSettings.LTRTMode = 'FullDouble';
            end
            gSettings.SwapToSingleDisplay = nil;
        end

        if (type(gSettings.Version) ~= 'number') or (gSettings.Version < 2.0) then
            for key,val in pairs(gSettings) do
                local newVal = defaultSettings[key];
                if newVal then
                    gSettings[key] = newVal;
                else
                    gSettings[key] = nil;
                end
            end
            Message('Settings from a prior incompatible version detected.  Updating settings.')
        end
        gSettings.Version = version;
        settings.save();
    end
end
UpdateSettings();

local function PrepareLayout(layout, scale)
    local tx = layout.Textures[layout.DragHandle.Texture]
    layout.DragHandle.Width = tx.Width;
    layout.DragHandle.Height = tx.Height;

    for _,singleTable in ipairs(T{layout, layout.FixedObjects, layout.Elements, layout.Textures}) do
        for _,tableEntry in pairs(singleTable) do
            if (type(tableEntry) == 'table') then
                if (tableEntry.OffsetX ~= nil) then
                    tableEntry.OffsetX = tableEntry.OffsetX * scale;
                    tableEntry.OffsetY = tableEntry.OffsetY * scale;
                end
                if (tableEntry.Width ~= nil) then
                    tableEntry.Width = tableEntry.Width * scale;
                    tableEntry.Height = tableEntry.Height * scale;
                end
                if (tableEntry.font_height ~= nil) then
                    tableEntry.font_height = math.max(5, math.floor(tableEntry.font_height * scale));
                end
                if (tableEntry.outline_width ~= nil) then
                    tableEntry.outline_width = math.min(3, math.max(1, math.floor(tableEntry.outline_width * scale)));
                end
            end
        end
    end
    
    --Prepare textures for efficient rendering..
    for _,singleTable in ipairs(T{layout.SkillchainFrames, layout.Textures}) do
        for key,entry in pairs(singleTable) do
            local tx,dimensions;
            if type(entry) == 'table' then
                tx = gTextureCache:GetTexture(entry.Path)
                dimensions = { Width=entry.Width, Height=entry.Height };
            else
                tx = gTextureCache:GetTexture(entry)
                dimensions = { Width=layout.Icon.Width, Height=layout.Icon.Height };
            end

            if tx and dimensions then
                local preparedTexture = {};
                preparedTexture.Texture = tx.Texture;
                preparedTexture.Rect = ffi.new('RECT', { 0, 0, tx.Width, tx.Height });
                preparedTexture.Scale = ffi.new('D3DXVECTOR2', { dimensions.Width / tx.Width, dimensions.Height / tx.Height });
                singleTable[key] = preparedTexture;
            else
                singleTable[key] = nil;
            end
        end
    end

    layout.FadeOpacity = d3d8.D3DCOLOR_ARGB(layout.FadeOpacity, 255, 255, 255);
    layout.TriggerOpacity = d3d8.D3DCOLOR_ARGB(layout.TriggerOpacity, 255, 255, 255);
end

local function GetDefaultPosition(layout)
    if ((scaling.window.w == -1) or (scaling.window.h == -1) or (scaling.menu.w == -1) or (scaling.menu.h == -1)) then
        return { 0, 0 };
    else
        --Centered horizontally, vertically just above chat log.
        return {
            (scaling.window.w - layout.Panel.Width) / 2,
            scaling.window.h - (scaling.scale_height(136) + layout.Panel.Height)
        };
    end
end

--Create exports..
local Initializer = {};

function Initializer:ApplyController()
    gController:SetLayout(gSettings.Controller);
end

function Initializer:ApplyLayout()
    gSingleDisplay:Destroy();
    gDoubleDisplay:Destroy();

    local singleLayout = LoadFile_s(GetResourcePath('layouts/' .. gSettings.SingleLayout));
    if singleLayout then
        PrepareLayout(singleLayout.Single, gSettings.SingleScale);
        local position = gSettings.SinglePosition;
        if position == nil then
            gSettings.SinglePosition = GetDefaultPosition(singleLayout.Single);
            settings.save();
        end
        gSingleDisplay:Initialize(singleLayout.Single);
    else
        Error('Failed to load single layout.  Please enter "/tc" to open the menu and select a valid layout.');
    end

    local doubleLayout = LoadFile_s(GetResourcePath('layouts/' .. gSettings.DoubleLayout));
    if doubleLayout then
        PrepareLayout(doubleLayout.Double, gSettings.DoubleScale);
        local position = gSettings.DoublePosition;
        if position == nil then
            gSettings.DoublePosition = GetDefaultPosition(doubleLayout.Double);
            settings.save();
        end
        gDoubleDisplay:Initialize(doubleLayout.Double);
    else
        Error('Failed to load double layout.  Please enter "/tc" to open the menu and select a valid layout.');
    end
    
    gTextureCache:Clear();
end

settings.register('settings', 'settings_update', function(newSettings)
    gSettings = newSettings;
    UpdateSettings();
    Initializer:ApplyController();
    Initializer:ApplyLayout();
    gBindings:Update();
end);

Initializer:ApplyController();
Initializer:ApplyLayout();
gBindings:Update();

return Initializer;