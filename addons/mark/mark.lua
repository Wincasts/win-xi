addon.name    = 'mark';
addon.author  = 'win (and claude)';
addon.version = '1.0';
addon.desc    = 'Pick a notorious monster, make it your mark, and see how it appears, its placeholders, where it spawns and what it drops.';
addon.link    = 'https://github.com/Wincasts/ffxi-addons';

-- A notorious monster looked up, and one of them hunted. The window has two dropdowns, a zone's and a
-- monster's, and under them what the server's own data says of the monster chosen: how it comes to be
-- there, its placeholders, where it and they spawn, and each drop with its chance at each level of
-- Treasure Hunter. Set As Mark makes it the mark: the window then says whether it and its placeholders
-- are in range and which way, says so in the chat log as it appears, and keeps time from its death.
--
--   /mark              shows or hides the window
--   /mark config       opens or closes the settings
--   /mark compact      switches between the whole window and the mark's few lines
--   /mark set <name>   makes a monster the mark, by its name or a part of it
--   /mark clear        there is no mark any more
--
-- The data is in data/, written by tools/build_mark_data.py from the server's source. hunts.lua reads
-- it and puts it into words; this file draws it and watches the game for the mark.

require('common');
local bit = require('bit');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local sound = require('winxi.sound');
local hunts = require('hunts');

local TextBaseWidth = imgui.CalcTextSize('A');

local gold = { 1.0, 215 / 255, 0.0, 1.0 };
local green = { 0.55, 1.0, 0.55, 1.0 };

local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
    'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };

local app = nil; -- the shell's: made once the settings' defaults are set out, below

local function Say(text)
    print(('\30\81[mark]\30\01 %s'):format(text));
end

local function ItemName(id)
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    local name = item ~= nil and item.Name ~= nil and item.Name[1] or nil;
    if name == nil or name == '' then
        return ('Item %d'):format(id);
    end
    return name;
end

----------------------------------------------------------------------------------------------------
-- The game, looked at four times a second: the zone, where the player is, and whether each monster
-- being watched (the mark and its placeholders, and those of the monster on show) is in range
----------------------------------------------------------------------------------------------------
local live = {
    checked = 0,
    zone = 0,
    x = nil, z = nil,     -- the player: east-west and north-south, as the server's data has them
    sights = {},          -- entity index -> { text, up } for those in range
    markUp = false,       -- whether the mark was up when last looked for
    markDead = false,     -- whether its corpse has been counted
    nearest = nil,        -- how far the monster on show's nearest spawn point is, in words
    timer = nil,          -- what is known of the mark's return, in words
};

local SPAWNED = 0x200; -- the render flag of an entity the client is showing

-- An entity in range: how far and which way, and whether it lives
local function Look(entities, index)
    if bit.band(entities:GetRenderFlags0(index), SPAWNED) == 0 then
        return nil;
    end
    local distance = math.sqrt(entities:GetDistance(index));
    local up = entities:GetHPPercent(index) > 0;
    local way = '';
    if live.x ~= nil then
        -- the game's own names for the two level directions are X and Y; the server's are x and z
        way = ' ' .. hunts.Compass(entities:GetLocalPositionX(index) - live.x, entities:GetLocalPositionY(index) - live.z);
    end
    return { up = up, text = ('%s, %d yalms%s'):format(up and 'Up' or 'Dead', math.floor(distance + 0.5), way) };
end

local function Watch(entities, record)
    local up, dead = false, false;
    for _, index in ipairs(record.indices) do
        local sight = Look(entities, index);
        live.sights[index] = sight;
        if sight ~= nil then
            up = up or sight.up;
            dead = dead or not sight.up;
        end
    end
    for _, placeholder in ipairs(record.placeholders or {}) do
        live.sights[placeholder.index] = Look(entities, placeholder.index);
    end
    return up, dead;
end

-- How far the nearest of a monster's spawn points (or the middle of its regions) is, and which way
local function Nearest(record)
    if live.x == nil then
        return nil;
    end
    local best, east, north = nil, 0, 0;
    for _, list in ipairs({ record.points or {}, record.areas or {} }) do
        for _, point in ipairs(list) do
            local dx, dz = point[1] - live.x, point[3] - live.z;
            local distance = math.sqrt(dx * dx + dz * dz);
            if best == nil or distance < best then
                best, east, north = distance, dx, dz;
            end
        end
    end
    if best == nil then
        return nil;
    end
    return ('Nearest is %d yalms %s of you.'):format(math.floor(best + 0.5), hunts.Compass(east, north));
end

-- What is known of the mark's return from when it was last seen dead
local function Timer(options, record)
    if options.killedAt == 0 then
        return nil;
    end
    local age = os.time() - options.killedAt;
    local said = ('Seen dead %s ago.'):format(hunts.Duration(age));
    local lottery = record.lottery;
    if lottery ~= nil and lottery.cooldown ~= nil then
        local wait = (lottery.cooldownMost or lottery.cooldown) - age;
        if wait > 0 then
            return ('%s The lottery opens in %s%s.'):format(said, lottery.cooldownMost and 'at most ' or '', hunts.Duration(wait));
        end
        return said .. ' The lottery is open.';
    elseif record.respawn ~= nil then
        local least, most = record.respawn[1] - age, record.respawn[2] - age;
        if least > 0 then
            return ('%s Its window opens in %s.'):format(said, hunts.Duration(least));
        elseif most > 0 then
            return ('%s Its window is open, for %s more.'):format(said, hunts.Duration(most));
        end
        return said .. ' It is due.';
    end
    return said;
end

local function Mark(options)
    if options.markName == '' then
        return nil;
    end
    return hunts.Monster(options.markZone, options.markName);
end

local function Update(options)
    local now = os.clock();
    if now - live.checked < 0.25 then
        return;
    end
    live.checked = now;

    local memory = AshitaCore:GetMemoryManager();
    local party = memory:GetParty();
    local entities = memory:GetEntity();
    live.zone = party:GetMemberZone(0);
    local me = party:GetMemberTargetIndex(0);
    if me ~= 0 then
        live.x, live.z = entities:GetLocalPositionX(me), entities:GetLocalPositionY(me);
    else
        live.x, live.z = nil, nil;
    end
    for index in pairs(live.sights) do
        live.sights[index] = nil;
    end

    local shown = options.viewName ~= '' and hunts.Monster(options.viewZone, options.viewName) or nil;
    live.nearest = nil;
    if shown ~= nil and live.zone == options.viewZone then
        Watch(entities, shown);
        live.nearest = Nearest(shown);
    end

    local mark = Mark(options);
    if mark == nil or live.zone ~= options.markZone then
        live.markUp, live.markDead = false, false;
    else
        local up, dead = Watch(entities, mark);
        if up and not live.markUp then
            -- it is back: what was known of its last death is of no more use
            options.killedAt = 0;
            if options.announce[1] then
                local sight = nil;
                for _, index in ipairs(mark.indices) do
                    if live.sights[index] ~= nil and live.sights[index].up then
                        sight = live.sights[index];
                    end
                end
                Say(('%s: %s.'):format(options.markName, sight.text));
            end
            sound.SetEnabled(options.sound[1]);
            sound.Play('open');
        end
        if dead and not up and not live.markDead then
            options.killedAt = os.time();
            app:Save();
            if options.announce[1] then
                Say(('%s is dead. The time is kept from now.'):format(options.markName));
            end
        end
        live.markUp, live.markDead = up, dead and not up;
    end
    live.timer = mark ~= nil and Timer(options, mark) or nil;
end

----------------------------------------------------------------------------------------------------
-- The monster on show: its record put into words once, when it is chosen
----------------------------------------------------------------------------------------------------
local view = { zone = nil, name = nil, th = nil, record = nil };

local function Summary(record)
    local parts = {};
    local low, high = record.level[1], record.level[2];
    if high > 0 then
        parts[#parts + 1] = low == high and ('Lv %d'):format(low) or ('Lv %d-%d'):format(low, high);
    end
    if record.family ~= nil then
        parts[#parts + 1] = record.family;
    end
    if record.job ~= nil and jobs[record.job] ~= nil then
        parts[#parts + 1] = jobs[record.job];
    end
    if record.aggro then
        parts[#parts + 1] = 'Aggressive';
    end
    if record.link then
        parts[#parts + 1] = 'Links';
    end
    if record.truesight then
        parts[#parts + 1] = 'True Sight';
    end
    if record.detects ~= nil then
        parts[#parts + 1] = 'Detects ' .. table.concat(record.detects, ', ');
    end
    return table.concat(parts, '  |  ');
end

local function Level(level)
    if level[1] == level[2] then
        return tostring(level[1]);
    end
    return ('%d-%d'):format(level[1], level[2]);
end

local function Names(ids)
    local names = {};
    for place, id in ipairs(ids) do
        names[place] = ItemName(id);
    end
    return table.concat(names, ', ');
end

local function BuildView(options)
    local th = math.max(0, math.min(hunts.MaxTreasureHunter, options.maxTh[1]));
    if view.zone == options.viewZone and view.name == options.viewName and view.th == th then
        return;
    end
    view.zone, view.name, view.th = options.viewZone, options.viewName, th;
    local record = options.viewName ~= '' and hunts.Monster(options.viewZone, options.viewName) or nil;
    view.record = record;
    if record == nil then
        return;
    end

    view.summary = Summary(record);
    view.appears = hunts.Appears(record, ItemName);
    view.places = hunts.Places(record.points, record.areas);
    for _, route in ipairs(record.routes or {}) do
        view.places[#view.places + 1] = ('%s %d points from %s to %s'):format(route.loop and 'Circles' or 'Walks out and back over',
            #route.points, hunts.Point(route.points[1]), hunts.Point(route.points[#route.points]));
    end

    view.placeholders = {};
    for place, placeholder in ipairs(record.placeholders or {}) do
        local where = hunts.Places(placeholder.points, placeholder.areas);
        if placeholder.route ~= nil then
            where[#where + 1] = ('%s %d points from %s'):format(placeholder.route.loop and 'Circles' or 'Walks',
                #placeholder.route.points, hunts.Point(placeholder.route.points[1]));
        end
        view.placeholders[place] = {
            index = placeholder.index,
            name = placeholder.name,
            id = ('%03X'):format(placeholder.index),
            level = Level(placeholder.level),
            respawn = placeholder.respawn and hunts.Duration(placeholder.respawn) or '',
            where = table.concat(where, '; '),
        };
    end

    -- each drop's chance at each level of Treasure Hunter shown, worked out here and not as it is drawn
    view.headings = {};
    for level = 0, th do
        view.headings[level + 1] = level == 0 and 'No TH' or ('TH%d'):format(level);
    end
    view.drops = hunts.Drops(record, ItemName);
    for _, row in ipairs(view.drops) do
        row.label = (row.indent and '   ' or '') .. row.name .. (row.count ~= nil and row.count > 1 and (' x%d'):format(row.count) or '');
        row.cells = {};
        for level = 0, th do
            row.cells[level + 1] = hunts.Percent(hunts.Chance(level, row.rate) * row.share / 10000);
        end
    end
    view.steal = record.steal and Names(record.steal) or nil;
    view.despoil = record.despoil and Names(record.despoil) or nil;
end

local function Show(options, zone, name)
    options.viewZone, options.viewName = zone, name or '';
    live.checked = 0; -- looked at again at once
end

local function SetMark(options, zone, name)
    options.markZone, options.markName, options.killedAt = zone, name, 0;
    live.markUp, live.markDead, live.checked = false, false, 0;
    app:Save();
end

----------------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------------
local find = { '' }; -- what is typed to look a monster up by name, in any zone

local function Sight(index)
    local sight = live.sights[index];
    if sight == nil then
        imgui.TextDisabled('Not In Range');
    elseif sight.up then
        imgui.TextColored(green, sight.text);
    else
        imgui.TextDisabled(sight.text);
    end
end

-- The mark, where it is and what is known of its return: what the compact window is made of, and
-- what heads the whole one
local function DrawMark(options, withPlaceholders)
    local mark = Mark(options);
    if mark == nil then
        return false;
    end
    imgui.TextColored(gold, 'Mark:');
    imgui.SameLine();
    imgui.Text(options.markName);
    imgui.SameLine();
    if live.zone ~= options.markZone then
        imgui.TextDisabled(hunts.ZoneName(options.markZone));
    else
        local seen = false;
        for _, index in ipairs(mark.indices) do
            if live.sights[index] ~= nil then
                Sight(index);
                seen = true;
                break;
            end
        end
        if not seen then
            imgui.TextDisabled('Not In Range');
        end
    end
    if live.timer ~= nil then
        imgui.Text(live.timer);
    end
    if withPlaceholders and live.zone == options.markZone then
        for _, placeholder in ipairs(mark.placeholders or {}) do
            imgui.Text(placeholder.name);
            imgui.SameLine();
            Sight(placeholder.index);
        end
    end
    return true;
end

local function DrawPicker(options)
    local zones = hunts.Zones(options.showScripted[1]);

    imgui.SetNextItemWidth(TextBaseWidth * 30);
    if imgui.BeginCombo('##mark.zone', options.viewZone ~= 0 and hunts.ZoneName(options.viewZone) or 'Zone') then
        for _, zone in ipairs(zones) do
            if imgui.Selectable(zone.label, zone.id == options.viewZone) and zone.id ~= options.viewZone then
                Show(options, zone.id, zone.monsters[1]);
            end
        end
        imgui.EndCombo();
    end

    imgui.SameLine();
    imgui.SetNextItemWidth(TextBaseWidth * 34);
    if imgui.BeginCombo('##mark.monster', options.viewName ~= '' and options.viewName or 'Notorious Monster') then
        if find[1] ~= '' then
            -- looked up by name: whichever zone they are in
            for _, found in ipairs(hunts.Find(find[1], options.showScripted[1])) do
                if imgui.Selectable(found.label, found.zone == options.viewZone and found.name == options.viewName) then
                    Show(options, found.zone, found.name);
                end
            end
        else
            for _, zone in ipairs(zones) do
                if zone.id == options.viewZone then
                    for _, name in ipairs(zone.monsters) do
                        if imgui.Selectable(name, name == options.viewName) and name ~= options.viewName then
                            Show(options, zone.id, name);
                        end
                    end
                end
            end
        end
        imgui.EndCombo();
    end

    imgui.SameLine();
    imgui.AlignTextToFramePadding();
    imgui.Text('Find:');
    imgui.SameLine();
    imgui.SetNextItemWidth(TextBaseWidth * 16);
    imgui.InputText('##mark.find', find, 64);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Type a part of a name: the monsters dropdown then lists every monster with it, in any zone.');
    end
end

local function Lines(lines)
    for _, line in ipairs(lines) do
        imgui.TextWrapped(line);
    end
end

local function DrawMonster(options)
    local record = view.record;
    local isMark = options.markName == options.viewName and options.markZone == options.viewZone;

    imgui.AlignTextToFramePadding();
    imgui.TextColored(isMark and gold or widgets.HeaderColor, options.viewName);
    imgui.SameLine();
    if isMark then
        if imgui.Button('Clear Mark##mark.clear') then
            SetMark(options, 0, '');
        end
    elseif imgui.Button('Set As Mark##mark.set') then
        SetMark(options, options.viewZone, options.viewName);
    end
    if view.summary ~= '' then
        imgui.Text(view.summary);
    end

    -- the sentences keep to the width of the tables under them
    imgui.PushTextWrapPos(imgui.GetCursorPosX() + TextBaseWidth * 96);

    widgets.Header('How It Appears');
    Lines(view.appears);

    if #view.placeholders > 0 then
        local here = live.zone == options.viewZone;
        widgets.Header('Placeholders');
        if imgui.BeginTable('mark.placeholders', here and 6 or 5, ImGuiTableFlags_SizingFixedFit) then
            imgui.TableSetupColumn('Placeholder', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 22);
            imgui.TableSetupColumn('ID', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 4);
            imgui.TableSetupColumn('Lv', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 6);
            imgui.TableSetupColumn('Respawn', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 9);
            imgui.TableSetupColumn('Where', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 44);
            if here then
                imgui.TableSetupColumn('Now', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 20);
            end
            imgui.TableHeadersRow();
            for _, placeholder in ipairs(view.placeholders) do
                imgui.TableNextRow();
                imgui.TableNextColumn();
                imgui.Text(placeholder.name);
                imgui.TableNextColumn();
                imgui.Text(placeholder.id);
                imgui.TableNextColumn();
                imgui.Text(placeholder.level);
                imgui.TableNextColumn();
                imgui.Text(placeholder.respawn);
                imgui.TableNextColumn();
                imgui.Text(placeholder.where);
                if here then
                    imgui.TableNextColumn();
                    Sight(placeholder.index);
                end
            end
            imgui.EndTable();
        end
    end

    widgets.Header('Spawn Locations');
    if #view.places == 0 then
        imgui.TextWrapped(#view.placeholders > 0 and 'The server\'s data gives it no place of its own: it stands where its placeholder would have.'
            or 'The server\'s data gives it no place of its own.');
    else
        Lines(view.places);
        if live.nearest ~= nil then
            imgui.Text(live.nearest);
        end
    end

    widgets.Header('Drops');
    if #view.drops == 0 then
        imgui.Text('Nothing, by the server\'s data.');
    elseif imgui.BeginTable('mark.drops', #view.headings + 1, ImGuiTableFlags_SizingFixedFit) then
        imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 30);
        for _, heading in ipairs(view.headings) do
            imgui.TableSetupColumn(heading, ImGuiTableColumnFlags_NoHide, TextBaseWidth * 7);
        end
        imgui.TableHeadersRow();
        for _, row in ipairs(view.drops) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            local Write = row.group and imgui.TextDisabled or imgui.Text;
            Write(row.label);
            for _, cell in ipairs(row.cells) do
                imgui.TableNextColumn();
                Write(cell);
            end
        end
        imgui.EndTable();
    end
    if view.steal ~= nil then
        imgui.TextWrapped('Steal: ' .. view.steal);
    end
    if view.despoil ~= nil then
        imgui.TextWrapped('Despoil: ' .. view.despoil);
    end

    imgui.PopTextWrapPos();
end

local function Draw(options)
    if options.compact[1] then
        if not DrawMark(options, true) then
            imgui.Text('No mark is set.');
            imgui.TextDisabled('/mark compact brings the whole window back.');
        end
        return;
    end

    if DrawMark(options, false) then
        if options.markName ~= options.viewName or options.markZone ~= options.viewZone then
            imgui.SameLine();
            if imgui.SmallButton('Show##mark.show') then
                Show(options, options.markZone, options.markName);
            end
        end
        imgui.Separator();
    end

    DrawPicker(options);
    BuildView(options);
    if view.record ~= nil then
        DrawMonster(options);
    elseif options.viewName ~= '' then
        imgui.Text('There is no data for ' .. options.viewName .. '.');
    else
        imgui.TextDisabled('Choose a zone and a notorious monster.');
    end
end

----------------------------------------------------------------------------------------------------
-- The settings, the settings window, the command and the main window's frame are the shell's
----------------------------------------------------------------------------------------------------
local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    markZone = 0,                -- the mark: its zone and its name, or none
    markName = '',
    killedAt = 0,                -- when the mark was last seen dead (os.time), or 0
    viewZone = 0,                -- the monster on show
    viewName = '',
    compact = T{ false },        -- only the mark's few lines
    announce = T{ true },        -- says in the chat log that the mark is up, or dead
    sound = T{ true },           -- and sounds as it comes up
    showScripted = T{ false },   -- lists the monsters the data knows only as brought by a script
    maxTh = T{ 4 },              -- the highest Treasure Hunter the drops are worked out for
};

local windowName = 'winxi.mark';

local function DrawSettings(options)
    widgets.Label('Visible');
    imgui.Checkbox('##mark.visible', options.isVisible);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows. /mark switches this.');
    end
    widgets.Label('Position');
    if imgui.InputInt2('##mark.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos);
    end
    widgets.Label('Compact Window');
    imgui.Checkbox('##mark.compact', options.compact);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Only the mark: whether it and its placeholders are in range, and what is known of its return. /mark compact switches this.');
    end

    widgets.Gap();
    widgets.Label('Show Scripted Spawns');
    imgui.Checkbox('##mark.scripted', options.showScripted);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Lists the notorious monsters a quest, a battlefield or an event brings as well: the server\'s data has their drops, and nothing of how they are brought.');
    end
    widgets.Label('Highest Treasure Hunter');
    imgui.SliderInt('##mark.maxTh', options.maxTh, 0, hunts.MaxTreasureHunter);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The drops are worked out for every level of Treasure Hunter up to this one.\nThe server takes up to 4 from a job that is not a thief\'s, up to 8 from a thief, and more only as a thief\'s blows raise it during the fight.');
    end

    widgets.Gap();
    widgets.Label('Announce Mark');
    imgui.Checkbox('##mark.announce', options.announce);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Says in the chat log that the mark has come into range, how far and which way, and that it has been seen dead.');
    end
    widgets.Label('Sound When Up');
    imgui.Checkbox('##mark.sound', options.sound);
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Plays a sound as the mark comes into range: open.wav in libs\\winxi\\sounds.');
    end
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Mark Settings',
    command = '/mark',
    help = '/mark shows or hides the window; /mark config opens or closes the settings; /mark compact switches to the mark\'s few lines and back; /mark set <name> makes a monster the mark; /mark clear leaves none.',
    drawSettings = DrawSettings,
    onSettings = function(options)
        -- anything a saved file has in another shape than it should
        for _, key in ipairs({ 'compact', 'announce', 'sound', 'showScripted', 'maxTh' }) do
            if type(options[key]) ~= 'table' then
                options[key] = defaults[key];
            end
        end
    end,
    commands = {
        compact = function(options)
            options.compact[1] = not options.compact[1];
        end,
        clear = function(options)
            if options.markName ~= '' then
                Say(('%s is no longer the mark.'):format(options.markName));
            end
            SetMark(options, 0, '');
        end,
        set = function(options, args)
            local words = table.concat(args, ' ', 3);
            if words == '' then
                Say('/mark set <name>: a notorious monster\'s name, or a part of it.');
                return;
            end
            -- one of the zone the player is in before any other, and a whole name before a part of one
            local found = hunts.Find(words, true, 200);
            local best = nil;
            for _, monster in ipairs(found) do
                local score = (monster.name:lower() == words:lower() and 2 or 0) + (monster.zone == live.zone and 1 or 0);
                if best == nil or score > best.score then
                    best = monster;
                    best.score = score;
                end
            end
            if best == nil then
                Say(('No notorious monster has "%s" in its name.'):format(words));
                return;
            end
            SetMark(options, best.zone, best.name);
            Show(options, best.zone, best.name);
            Say(('%s is the mark.'):format(best.label));
        end,
    },
});

ashita.events.register('d3d_present', 'mark_present', function()
    -- the mark is watched whether or not the window is there to be seen
    local shown = app:BeginFrame();
    local options = app.options;
    Update(options);
    if not shown then
        return;
    end

    -- nothing chosen yet: the zone the player is in, if it has any to list
    if options.viewZone == 0 and live.zone ~= 0 then
        for _, zone in ipairs(hunts.Zones(options.showScripted[1])) do
            if zone.id == live.zone then
                Show(options, zone.id, zone.monsters[1]);
            end
        end
    end
    app:Window(options.isVisible, Draw);
end);
