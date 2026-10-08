local tokens = require('tokens');
local style = require('style');
local anchor = require('anchor');
local cache = require('cache');
local details = {
    IsOpen = { true },
    Header = { 1.0, 0.75, 0.55, 1.0 },
};
local entMgr = AshitaCore:GetMemoryManager():GetEntity();
local resMgr = AshitaCore:GetResourceManager();
local errorPrinted = T{};
local sideSpacing = { 8, 0 }; -- between the two columns of the detail view

local function GetDirection(index)
    local myIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    local myX = entMgr:GetLocalPositionX(myIndex);
    local myY = entMgr:GetLocalPositionY(myIndex);
    local targetX = entMgr:GetLocalPositionX(index);
    local targetY = entMgr:GetLocalPositionY(index);

    local rads = math.atan2(targetX - myX, targetY - myY);

    if (rads > 2.74) then
        return 'South';
    elseif (rads > 1.96) then
        return 'South-East';
    elseif (rads > 1.17) then
        return 'East';
    elseif (rads > 0.39) then
        return 'North-East';
    elseif (rads > -0.39) then
        return 'North';
    elseif (rads > -1.17) then
        return 'North-West';
    elseif (rads > -1.96) then
        return 'West';
    elseif (rads > -2.7) then
        return 'South-West';
    else
        return 'South';
    end
end

local function GetPosition(index)
    return string.format('(%.2f,%.2f) Z:%.2f',
        entMgr:GetLocalPositionX(index),
        entMgr:GetLocalPositionY(index),
        entMgr:GetLocalPositionZ(index));
end

local function GetSpeed(index)
    local entity = entMgr:GetRawEntity(index);
    if entity == nil then
        return 'Unknown';
    else
        local speed = entMgr:GetAnimationSpeed(index);
        local relative = speed / 4;
        if (index > 0x3FF) and (index < 0x700) then
            speed = entMgr:GetMovementSpeed(index);
            relative = speed / 5;
        end

        if (relative < 1) then
            relative = string.format('-%.2d', math.floor((1 - relative) * 100)) .. cache.PercentSign;
        elseif (relative > 1) then
            relative = string.format('+%.2d', math.floor((relative - 1) * 100)) .. cache.PercentSign;
        else
            relative = '+0%';
        end
        
        return string.format('%.2f Yalms/Second (%s)', speed, relative);
    end
end

local function DrawImage(file)
    if not gTextures:Draw(file, 13 * gSettings.DetailScale) then
        if errorPrinted[file] == nil then
            print(chat.header('MobDB') .. chat.error('Texture not found: ' .. file));
            errorPrinted[file] = true;
        end
        return;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(file);
    end
end

-- A sorted modifier list from the cache, on one line: each icon, and the figure after the last of
-- each strength
local function PrintMods(mods)
    local first = true;
    for _,mod in ipairs(mods) do
        if not first then
            imgui.SameLine();
        end

        if mod.HasIcon then
            DrawImage(mod.Type);
            first = false;
        end

        if mod.Text then
            imgui.SameLine();
            imgui.Text(mod.Text);
        end
    end
end

-- A mob's flag icons on one line: its aggro icon, then each flag it has
local function PrintFlags(resource)
    for index,icon in ipairs(cache.Flags(resource)) do
        if (index > 1) then
            imgui.SameLine();
        end
        DrawImage(icon);
    end
end

local function PrintImmunities(resource)
    for index,icon in ipairs(cache.Immunities(resource)) do
        if (index > 1) then
            imgui.SameLine();
        else
            imgui.TextColored(details.Header, 'Status Immunities');
        end
        DrawImage(icon);
    end
end

local function TimeToString(time)
    local days = math.floor(time / 86400);
    time = math.fmod(time, 86400);
    local hours = math.floor(time / 3600);
    time = math.fmod(time, 3600);
    local minutes = math.floor(time / 60);
    local seconds = math.fmod(time, 60);

    if (days > 0) then
        if (hours == 0) and (minutes == 0) and (seconds == 0) then
            return string.format('%u days', days);
        else
            return string.format('%u days + %02u:%02u:%02u', days, hours, minutes, seconds);
        end
    elseif (hours > 0) then
        return string.format('%u:%02u:%02u', hours, minutes, seconds);
    else
        return string.format('%u:%02u', minutes, seconds);
    end
end

-- Everything the detail view shows. Kept apart from the window itself because, for a corner other
-- than the top left, it is laid out twice: once off screen to be measured (see anchor).
function details:RenderContent(index, resource)
    imgui.PushFont(nil, 12 * gSettings.Scale);
    imgui.BeginGroup();
    imgui.TextColored(self.Header, 'Name:');
    imgui.SameLine();
    if resource and resource.Name then
        imgui.Text(resource.Name);
    else
        local name = entMgr:GetName(index);
        if (name ~= nil) then
            imgui.Text(name);
        else
            imgui.Text('Unknown');
        end
    end

    imgui.TextColored(self.Header, 'Index:');
    imgui.SameLine();
    imgui.Text(string.format('%u[0x%X]', index, index));
    
    imgui.TextColored(self.Header, 'Id:');
    imgui.SameLine();
    local id = entMgr:GetServerId(index);
    imgui.Text(string.format('%u[0x%08X]', id, id));

    imgui.TextColored(self.Header, 'Position:');
    imgui.SameLine();
    imgui.Text(GetPosition(index));
        
    imgui.TextColored(self.Header, 'Direction:');
    imgui.SameLine();
    imgui.Text(GetDirection(index));
                    
    imgui.TextColored(self.Header, 'Speed:');
    imgui.SameLine();
    imgui.Text(GetSpeed(index));

    if (index > 0) and (index < 0x900) and (bit.band(entMgr:GetSpawnFlags(index), 0x10) ~= 0) then
        imgui.TextColored(self.Header, 'Is Custom Mob:');
        imgui.SameLine();
        if ((index >= 0x700) and (index <= 0x900)) then
            imgui.Text('Yes');
        else
            imgui.Text('No');
        end
    end

    if resource then
        if resource.Job > 0 then
            imgui.TextColored(self.Header, 'Job:');
            imgui.SameLine();
            imgui.Text(cache.Job(resource));
        end

        imgui.TextColored(self.Header, 'Level:');
        imgui.SameLine();
        if (resource.Level) then
            imgui.Text(resource.Level);                    
        else
            imgui.Text(string.format('%d-%d', resource.MinLevel, resource.MaxLevel));
        end

        if (resource.Respawn ~= nil) and (resource.Respawn > 0) then
            imgui.TextColored(self.Header, 'Respawn Time:');
            imgui.SameLine();
            imgui.Text(TimeToString(resource.Respawn));
        end
        
        imgui.TextColored(self.Header, 'Flags');
        PrintFlags(resource);
        
        local mods = cache.Mods(resource, 'physical');
        if (#mods > 0) then
            imgui.TextColored(self.Header, 'Physical Modifiers');
            PrintMods(mods);
        end

        mods = cache.Mods(resource, 'magical');
        if (#mods > 0) then
            imgui.TextColored(self.Header, 'Magical Modifiers');
            PrintMods(mods);
        end

        PrintImmunities(resource);
    end
    imgui.EndGroup();

    if (resource) then
        local beganGroup = false;
        local drops = (resource.Drops) and (resource.Drops[1]);
        local spells = (resource.Spells) and (resource.Spells[1]);

        if drops or spells then
            imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, sideSpacing);
            imgui.SameLine();
            imgui.BeginGroup();
        end
        
        if drops then
            imgui.TextColored(self.Header, 'Drops');
            for _,dropName in ipairs(cache.DropNames(resource)) do
                imgui.Text(dropName);
            end
            if spells then
                imgui.NewLine();
            end
        end

        if spells then
            imgui.TextColored(self.Header, 'Spells');
            for _,spellName in ipairs(cache.SpellNames(resource)) do
                imgui.Text(spellName);
            end
        end

        if drops or spells then
            imgui.EndGroup();
            imgui.PopStyleVar();
        end
    end
    imgui.PopFont();
end

-- Fixed for as long as the addon is loaded, so made once rather than on every frame
local windowTitle = string.format('%s v%s##MobDB Detail View', addon.name, addon.version);
local windowOpen = { true };
local noSpacing = { 0, 0 };
local resetPosition = { 10, 10 };

-- What the measuring pass draws: the content for the target being rendered this frame
local renderIndex, renderResource = 0, nil;
local function drawContent()
    details:RenderContent(renderIndex, renderResource);
end

function details:Render()
    local targetMgr = AshitaCore:GetMemoryManager():GetTarget();
    local index = targetMgr:GetTargetIndex(targetMgr:GetIsSubTargetActive());
    local resource = nil;
    if (index == 0) then
        return;
    end

    if (bit.band(entMgr:GetSpawnFlags(index), 0x10) ~= 0) then
        resource = cache.FindResource(index);
    end
    renderIndex, renderResource = index, resource;

    style.PushPlain();
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, noSpacing);
    anchor.Measure('details', drawContent);
    if self.ResetPosition then
        imgui.SetNextWindowPos(resetPosition);
        self.ResetPosition = nil;
        anchor.Reset('details');
    else
        anchor.Place('details');
    end
    windowOpen[1] = true;
    if (imgui.Begin(windowTitle, windowOpen, style.WindowFlags())) then
        anchor.Track('details');
        self:RenderContent(index, resource);
    end
    imgui.End();
    imgui.PopStyleVar();
    style.PopPlain();
end

return details;