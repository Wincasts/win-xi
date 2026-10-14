-- The settings' Triggers tab: the indicator's settings, the making of a trigger from what mobs.lua
-- says each kind of mob can do, and the triggers there are.
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shared = require('shared')
local playing = require('playing')
local mobdata = require('mobdata')
local triggers = require('triggers')
local indicator = require('indicator')
local controls = require('controls')

local Try = playing.Try
local MobData, Area, CurrentZone = mobdata.Read, mobdata.Area, mobdata.CurrentZone
local ActionName, ZoneName = mobdata.ActionName, mobdata.ZoneName
local IndexTriggers, triggerSound = triggers.Index, triggers.defaultSound
local Indicate = indicator.Indicate
local SoundCombo, Mark = controls.SoundCombo, controls.RightMark

-- The trigger being made: its sound is chosen once it is made, in the list of triggers
-- said is what the mark beside the kind says, put together for a kind (saidOf) in an area (saidIn)
local making = { mob = nil, action = nil, said = nil, saidOf = nil, saidIn = nil }

-- The button that makes it, its right side under that of the list over it
local createLabel = 'Create Trigger'
local typeSaid = 'Choose the mob type you wish to set a new trigger for. Mobs found in your area are displayed first when applicable.'
local createSize = nil -- how big the button is: found out once

-- What a kind of mob can do, each with its name, in the order of their names: found out once for a
-- kind, and kept with what is known of it. The game has some things under more than one number (a
-- weaponskill, and the same again for the mobs of Dynamis): what has one name is one thing to choose,
-- with every number it goes by.
--
-- What only the kind's notorious monsters do comes after what its other mobs do, in lists of its
-- own: what several of them do under one heading, then each monster's own under its name and level,
-- those of the area you are in first, then the rest,
-- the lowest in level first as mobs.lua has them. A monster that is in two areas is two where it is
-- not the same in both.
local kindLabels = triggers.kindLabels
local severalHeading = 'Notorious Monsters' -- over what several of a kind's notorious monsters do

-- The order of every list of things a mob does: its abilities, then its weaponskills, then its
-- spells, and each of those in the order of their names
local kindOrder = { ability = 1, skill = 2, spell = 3 }

local function ActionsInOrder(a, b)
    if a.kind ~= b.kind then
        return kindOrder[a.kind] < kindOrder[b.kind]
    end
    return a.label < b.label
end

-- A thing a mob does, by its kind and name, whoever does it and under whatever numbers: one trigger
-- is for them all. named is the things found so far for the one kind of mob.
local function NamedAction(named, kind, id)
    local name = ActionName(kind, id)
    local action = named[kind .. name]
    if action == nil then
        action = { kind = kind, ids = T{ }, has = { }, name = name,
            label = ('%s (%s)##%s%d'):format(name, kindLabels[kind], kind, id) }
        named[kind .. name] = action
    end
    if not action.has[id] then
        action.has[id] = true
        action.ids[#action.ids + 1] = id
    end
    return action
end

-- A thing into a list, unless it is there, or in either of the lists given as already said
local function AddAction(list, action, said, alsoSaid)
    if not list.listed[action] and not (said and said.listed[action]) and not (alsoSaid and alsoSaid.listed[action]) then
        list.listed[action] = true
        list[#list + 1] = action
    end
end

-- A list of things, in order, from the spells and the moves as mobs.lua writes them, under who does them
local function ActionList(named, spells, moves, who, said, alsoSaid)
    local list = { who = who, listed = { } }
    for id in (spells or ''):gmatch('%d+') do
        AddAction(list, NamedAction(named, 'spell', tonumber(id)), said, alsoSaid)
    end
    for ability, id in (moves or ''):gmatch('(a?)(%d+)') do
        AddAction(list, NamedAction(named, ability == 'a' and 'ability' or 'skill', tonumber(id)), said, alsoSaid)
    end
    table.sort(list, ActionsInOrder)
    return list
end

-- What the kind's mobs do, and in notorious the lists that come after it: first what several of
-- its notorious monsters do, said once for them all, then a list for each monster of what it does
-- that neither the kind's other mobs nor several monsters do
local function MobActions(data, known, zone)
    if known.actions ~= nil and known.actions.zone == zone then
        return known.actions
    end
    local named = { }
    local actions = ActionList(named, known.spells, known.moves)
    actions.zone, actions.notorious = zone, { }
    local several = known.several or { }
    several = ActionList(named, several.spells, several.moves, severalHeading, actions)
    if #several > 0 then
        actions.notorious[1] = several
    end
    local here = ('.%d.'):format(zone)
    for pass = 1, 2 do
        for name, where, level, spells, moves in (known.notorious or ''):gmatch('([^=;]+)=([%d.]+),([^,;]*),(%d*),(%d*);') do
            -- where is the areas it is in, with points between them
            if (('.' .. where .. '.'):find(here, 1, true) ~= nil) == (pass == 1) then
                local list = ActionList(named, data.lists[tonumber(spells)], data.lists[tonumber(moves)],
                    level ~= '' and ('%s (Lv %s)'):format(name, level) or name, actions, several)
                if #list > 0 then
                    actions.notorious[#actions.notorious + 1] = list
                end
            end
        end
    end
    known.actions = actions
    return actions
end

local hideRules = {
    { 'Hide While Map Open', 'UnderMap', 'Hide the indicator while the map is open.' },
    { 'Hide While Chat Open', 'UnderChat', 'Hide the indicator while the chat log is opened right out.' },
    { 'Hide While Loading', 'WhileLoading', 'Hide the indicator while changing area.' },
    { 'Hide During Events', 'DuringEvent', 'Hide the indicator during cutscenes and while talking to an NPC.' },
    { 'Hide With Game Interface', 'WithInterface', 'Hide the indicator while the game interface is hidden.' },
}
local hideValue = { false }

-- A trigger's sound, and its words in the indicator if that is switched on
local function TestButton(trigger)
    if imgui.Button('Test') then
        Indicate(trigger)
        Try(trigger.sound)
    end
end

local function HasTrigger(triggers, mob, action)
    for _, trigger in ipairs(triggers) do
        if trigger.mob == mob and trigger.kind == action.kind and trigger.name == action.name then
            return true
        end
    end
    return false
end

-- The kinds of mob to choose among, in two lists, each in the order of their names: those with mobs
-- in the area, and the rest. Put together once for an area, and kept with what is known of the mobs.
local function KindLists(data, zone)
    local lists = data.choices
    if lists == nil or lists.zone ~= zone then
        lists = { zone = zone, here = { }, elsewhere = { } }
        local among = Area(zone).among
        for kind in pairs(data.kinds) do
            local list = among[kind] ~= nil and lists.here or lists.elsewhere
            list[#list + 1] = kind
        end
        table.sort(lists.here)
        table.sort(lists.elsewhere)
        data.choices = lists
    end
    return lists
end

local function KindChoices(kinds)
    for _, kind in ipairs(kinds) do
        if imgui.Selectable(kind, kind == making.mob) and kind ~= making.mob then
            making.mob, making.action = kind, nil
        end
    end
end

local function ActionChoices(actions)
    for _, action in ipairs(actions) do
        if imgui.Selectable(action.label, making.action ~= nil and action.label == making.action.label) then
            making.action = action
        end
    end
end

local function DrawMaking(options)
    local data = MobData()
    if data == nil then
        imgui.TextDisabled('mobs.lua, which says what mobs can do, cannot be read.')
        Mark('Trigger creation needs mobs.lua in the addon folder. Restore or regenerate that file, then reopen settings.')
        return
    end
    local zone = CurrentZone()
    local lists = KindLists(data, zone)

    widgets.Label('Mob Type')
    widgets.PushControlWidth()
    if imgui.BeginCombo('##trigger.making.mob', making.mob or 'Choose One') then
        -- the area's own first, under its name, then the rest
        if #lists.here > 0 then
            imgui.TextDisabled(ZoneName(zone))
            KindChoices(lists.here)
            imgui.Separator()
            imgui.TextDisabled('Elsewhere')
        end
        KindChoices(lists.elsewhere)
        imgui.EndCombo()
    end
    widgets.PopControlWidth()
    -- what the mark says, and under it the mobs of the kind chosen that are in the area: put together
    -- when the kind or the area is another one
    if making.mob == nil then
        Mark(typeSaid, true)
    else
        if making.saidOf ~= making.mob or making.saidIn ~= zone then
            local here = Area(zone).among[making.mob]
            making.saidOf, making.saidIn = making.mob, zone
            making.said = ('%s\n\n%s'):format(typeSaid, here ~= nil and ('In %s: %s'):format(ZoneName(zone), (here:gsub('|', ', ')))
                or ('None in %s.'):format(ZoneName(zone)))
        end
        Mark(making.said, true)
    end

    widgets.Label('Action')
    widgets.PushControlWidth()
    if imgui.BeginCombo('##trigger.making.action', making.action and making.action.label or 'Choose One') then
        if making.mob ~= nil and data.kinds[making.mob] ~= nil then
            local actions = MobActions(data, data.kinds[making.mob], zone)
            ActionChoices(actions)
            -- what only a notorious monster of the kind does: under its name and level
            for index, list in ipairs(actions.notorious) do
                if index > 1 or #actions > 0 then
                    imgui.Separator()
                end
                imgui.TextDisabled(list.who)
                imgui.PushID(index)
                ActionChoices(list)
                imgui.PopID()
            end
        end
        imgui.EndCombo()
    end
    widgets.PopControlWidth()
    -- where the list ends, which is where the button under it ends too
    imgui.SameLine(0, 0)
    local listEnd = imgui.GetCursorPosX()
    Mark('Choose the action for which you wish to create a new trigger. Spells and weaponskills trigger as soon as they begin casting or are readied and an ability is triggered immediately upon use.', true)

    createSize = createSize or { imgui.CalcTextSize(createLabel) + 20, 0 }
    imgui.SetCursorPosX(math.max(listEnd - createSize[1], imgui.GetCursorPosX()))
    if imgui.Button(createLabel, createSize) then
        if making.mob == nil or making.action == nil then
            shared.app:Say('Choose a kind of mob and what it does first.')
        elseif HasTrigger(options.triggers, making.mob, making.action) then
            shared.app:Say(('There is a trigger for %s and %s already.'):format(making.mob, making.action.name))
        else
            options.triggers[#options.triggers + 1] = T{ mob = making.mob, kind = making.action.kind,
                ids = T{ unpack(making.action.ids) }, name = making.action.name, sound = triggerSound, enabled = T{ true } }
            making.action = nil
            IndexTriggers(options.triggers)
            shared.app:Save()
        end
    end
    Mark('Create a trigger for the selected mob type and action. Choose its sound in the list below. Duplicate triggers are not added.')
end

-- What a trigger is shown as: put together once for each
local triggerTexts = setmetatable({ }, { __mode = 'k' })

local function TriggerText(trigger)
    local text = triggerTexts[trigger]
    if text == nil then
        text = ('%s: %s'):format(trigger.mob, trigger.name)
        triggerTexts[trigger] = text
    end
    return text
end

local growIds = { } -- a side the indicator grows from -> its button's label
for _, grow in ipairs(indicator.Grows) do
    growIds[grow] = grow .. '##trigger.indicator.grow'
end

local function DrawIndicatorSettings(options)
    widgets.Label('Show Indicator')
    if imgui.Checkbox('##trigger.indicator.enabled', options.showIndicator) then shared.app:Save() end
    Mark('A small window that says what a trigger was for, as the chat log does, for a few seconds. It is shown while this tab is open: drag it to where you want it.', true)

    -- how long only while it is switched on: off, there is nothing for it to set
    if options.showIndicator[1] then
        widgets.Label('Indicator Duration')
        widgets.PushControlWidth()
        imgui.SliderInt('##trigger.indicator.seconds', options.indicatorSeconds, 1, 15, '%d s')
        widgets.PopControlWidth()
        if imgui.IsItemDeactivatedAfterEdit() then shared.app:Save() end
        Mark('How long each triggered message stays in the indicator, in seconds.')
    end
    widgets.Gap()
    for _, rule in ipairs(hideRules) do
        widgets.Label(rule[1])
        hideValue[1] = options.hide[rule[2]]
        if imgui.Checkbox('##trigger.hide.' .. rule[2], hideValue) then
            options.hide[rule[2]] = hideValue[1]
            shared.app:Save()
        end
        Mark(rule[3] .. ' Sounds are unaffected.')
    end
end

local function DrawAppearance(options)
    widgets.Label('Fade In And Out')
    if imgui.Checkbox('##trigger.indicator.fade', options.fadeInOut) then shared.app:Save() end
    Mark('The indicator fades in as it appears and out as it goes.', true)

    widgets.Gap()
    widgets.Label('Grow From')
    for index, grow in ipairs(indicator.Grows) do
        if index > 1 then
            imgui.SameLine()
        end
        if imgui.RadioButton(growIds[grow], options.indicatorGrow == grow) and options.indicatorGrow ~= grow then
            options.indicatorGrow = grow
            shared.app:Save()
        end
    end
    Mark('The side of the indicator that stays where it is as what it says gets longer or shorter. Its lines are set to that side too.', true)
end

local function DrawTriggers(options)
    -- the indicator is shown while the tab is, to be put where it is wanted
    indicator.sample = true

    -- [Experimental], as every addon here marks what is
    imgui.TextColored(widgets.ExperimentalColor, '[Experimental]')

    if widgets.Header('Indicator') then
        DrawIndicatorSettings(options)
        widgets.Gap()
        DrawAppearance(options)
    end

    if widgets.Header('New Trigger') then
        DrawMaking(options)
    end

    if not widgets.Header('Triggers') then return end
    local triggers = options.triggers
    if #triggers == 0 then
        imgui.TextDisabled('None yet.')
        Mark('Use Mob Type and Action above, then Create Trigger, to add a trigger.')
        return
    end
    local removed = nil
    for index, trigger in ipairs(triggers) do
        imgui.PushID(index)
        if imgui.Checkbox('##enabled', trigger.enabled) then shared.app:Save() end
        imgui.SameLine()
        SoundCombo('##sound', trigger, 'trigger')
        imgui.SameLine()
        TestButton(trigger)
        imgui.SameLine()
        if imgui.Button('Remove') then
            removed = index
        end
        imgui.SameLine()
        imgui.Text(TriggerText(trigger))
        Mark('Enable or disable this trigger, choose its sound, test its sound and indicator, or remove it.\n' .. TriggerText(trigger))
        imgui.PopID()
    end
    if removed ~= nil then
        table.remove(triggers, removed)
        IndexTriggers(triggers)
        shared.app:Save()
    end
end

return { Draw = DrawTriggers }
