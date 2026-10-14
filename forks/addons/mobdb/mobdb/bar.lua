local tokens = require('tokens');
local style = require('winxi.style');
local anchor = require('winxi.anchor');
local shadow = require('winxi.shadow');
local cache = require('cache');

local MobFormat = '$name[$joblevel] $aggro$LB$physmagic';
local PlayerFormat = 'PLAYER:';
local NPCFormat = 'NPC:';
local NothingFormat = 'NOTHING';
local PetFormat = 'PET';

local bar = {};

bar.Layout = {
    ItemSpacing = 0
}

bar.State = {
    IsOpen = { true }
};

local function ResolveToken(input, outTable)
    local longestMatch = 0;
    local bestFunc = nil;
    for token,func in pairs(tokens) do
        local start,finish = string.find(input, token);
        if (start == 1) and (finish > longestMatch) then
            longestMatch = finish;
            bestFunc = func;
        end
    end
    if bestFunc then
        outTable:append(bestFunc);
        return longestMatch;
    else
        local nextString = string.sub(input, 2);
        local nextTokenIndex = string.find(nextString, '%$');
        if (nextTokenIndex ~= nil) then
            outTable:append(string.sub(input, 1, nextTokenIndex));
            return nextTokenIndex;
        else
            return -1;
        end
    end
end

local function SplitTokens(input)
    local outTable = T{};
    local nextToken = string.find(input, '%$');
    while (nextToken ~= nil) do
        if (nextToken == 1) then
            if string.sub(input, 1, 3) == '$LB' then
                outTable:append('$LB');
                input = string.sub(input, 4);
            else
                local length = ResolveToken(input, outTable);
                if (length == -1) then
                    break;
                end
                input = string.sub(input, length + 1);
            end
            nextToken = string.find(input, '%$');
        else
            outTable:append(string.sub(input, 1, nextToken - 1));
            input = string.sub(input, nextToken);
            nextToken = 1;
        end
    end
    if (string.len(input) > 0) then
        outTable:append(input);
    end

    return outTable;
end

bar.ParseFormats = function(self, format)
    if type(format) == 'string' then
        self.Layout[format] = SplitTokens(gSettings[format]);
    else
        self.Layout.MobFormat = SplitTokens(gSettings.MobFormat);
        self.Layout.PlayerFormat = SplitTokens(gSettings.PlayerFormat);
        self.Layout.NPCFormat = SplitTokens(gSettings.NPCFormat);
        self.Layout.NothingFormat = SplitTokens(gSettings.NothingFormat);
        self.Layout.PetFormat = SplitTokens(gSettings.PetFormat);
    end
end

-- Which format the target at an entity index takes, and its database entry if it is a mob. Kept until
-- the target, or the entity at that index, changes: working it out takes several reads.
local kindIndex, kindId, kindFormat = nil, nil, nil;

local function GetFormat(entMgr, targetIndex)
    if (targetIndex == 0) then
        return 'NothingFormat';
    end

    local id = entMgr:GetServerId(targetIndex);
    if (targetIndex ~= kindIndex) or (id ~= kindId) then
        local format;
        if (targetIndex >= 0x400) and (targetIndex < 0x700) then
            format = 'PlayerFormat';
        elseif (targetIndex >= 0x700) and (entMgr:GetTrustOwnerTargetIndex(targetIndex) ~= 0) then
            format = 'PetFormat';
        elseif (bit.band(entMgr:GetSpawnFlags(targetIndex), 0x10) ~= 0) then
            format = 'MobFormat';
        else
            format = 'NPCFormat';
        end
        kindIndex, kindId, kindFormat = targetIndex, id, format;
    end
    return kindFormat;
end

-- Everything the bar shows this frame. Module-level rather than made each frame: for a corner other
-- than the top left it is laid out twice, once off screen to be measured (see anchor).
local renderTable, renderIndex, renderResource = nil, 0, nil;

local function drawContent()
    imgui.PushFont(nil, 12 * gSettings.Scale);
    gTokenState.FirstElement = true;
    gTokenState.LineBreak = false;
    for index,currentObject in ipairs(renderTable) do
        if (type(currentObject) == 'function') then
            currentObject(renderIndex, renderResource);
        elseif (type(currentObject) == 'string') then
            if (currentObject == '$LB') then
                gTokenState.LineBreak = true;
            else
                gTokenState:ProcessSameLines();
                imgui.Text(currentObject);
            end
        end
    end
    imgui.PopFont();
end

local itemSpacing = { bar.Layout.ItemSpacing, bar.Layout.ItemSpacing };
local resetPosition = { 10, 10 };
local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize);

bar.Render = function(self)
    local memMgr = AshitaCore:GetMemoryManager();
    local entMgr = memMgr:GetEntity();
    local targetMgr = memMgr:GetTarget();
    local targetIndex = targetMgr:GetTargetIndex(targetMgr:GetIsSubTargetActive());

    local format = GetFormat(entMgr, targetIndex);
    local targetResource = nil;
    if (format == 'MobFormat') then
        targetResource = cache.FindResource(targetIndex);
    end
    renderTable, renderIndex, renderResource = self.Layout[format], targetIndex, targetResource;

    if (self.State.IsOpen[1]) and (#renderTable > 0) then
        -- The theme first, so that a colour set in this addon's settings file still applies over it
        local growFrom = gSettings.GrowFrom;
        style.PushPlain();
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing);
        anchor.Measure('bar', growFrom, drawContent);
        if self.ResetPosition then
            imgui.SetNextWindowPos(resetPosition);
            self.ResetPosition = nil;
            anchor.Reset('bar');
        else
            anchor.Place('bar', growFrom);
        end
        local pushColor = gSettings.Color;
        if pushColor then
            imgui.PushStyleColor(ImGuiCol_WindowBg, gSettings.Color);
        end
        if imgui.Begin('mobdb_infobar', self.State.IsOpen, windowFlags) then
            anchor.Track('bar', growFrom);
            shadow.Draw();
            drawContent();
        end
        imgui.End();
        if pushColor then
            imgui.PopStyleColor();
        end
        imgui.PopStyleVar();
        style.Pop();
    end
end

bar:ParseFormats();
return bar;