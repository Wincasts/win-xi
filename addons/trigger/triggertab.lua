-- The settings' Triggers tab (the making of a trigger from what the triggermobs set says each kind of
-- mob can do, and the triggers there are) and its Toast tab (the indicator's settings), as described
-- rows (winxi.widgets).
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
local SoundCombo = controls.SoundCombo

-- The trigger being made: its sound is chosen once it is made, in the list of triggers
-- said is the status line's account of the kind's mobs in the area, put together for a kind (saidOf)
-- in an area (saidIn)
local making = { mob = nil, action = nil, said = nil, saidOf = nil, saidIn = nil }

-- The rows of New Trigger: their sentences, and the spec of the Create row, which is what is experimental
local mobSentence = 'The kind of mob to listen for. Those in your area come first.'
local actionSentence = 'What the mob does. A spell or weaponskill sounds as it begins, an ability as it is used.'
local createSentence = 'Makes a trigger for the kind and action chosen. Its sound is chosen in the list below.'
local createSpec = { experimental = true }
local noData = 'The list of what mobs can do cannot be read. Put winxi\'s data back, then open the settings again.'
local noTriggers = 'None yet. Choose a mob type and an action above, then Create.'

-- What a kind of mob can do, each with its name, in the order of their names: found out once for a
-- kind, and kept with what is known of it. The game has some things under more than one number (a
-- weaponskill, and the same again for the mobs of Dynamis): what has one name is one thing to choose,
-- with every number it goes by.
--
-- What only the kind's notorious monsters do comes after what its other mobs do, in lists of its
-- own: what several of them do under one heading, then each monster's own under its name and level,
-- those of the area you are in first, then the rest,
-- the lowest in level first as the triggermobs set has them. A monster that is in two areas is two where it is
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

-- The rules for hiding the toast: each a row, under Enable Toast. The sounds play whatever they say.
local hideRules = {
    { 'Hide While Map Open', 'UnderMap', 'Hides the toast while the map is open. Sounds still play.', '##trigger.hide.UnderMap' },
    { 'Hide While Chat Open', 'UnderChat', 'Hides the toast while the chat log is fully open. Sounds still play.', '##trigger.hide.UnderChat' },
    { 'Hide While Loading', 'WhileLoading', 'Hides the toast while you change area. Sounds still play.', '##trigger.hide.WhileLoading' },
    { 'Hide During Events', 'DuringEvent', 'Hides the toast during cutscenes and while you talk to someone. Sounds still play.', '##trigger.hide.DuringEvent' },
    { 'Hide With Game Interface', 'WithInterface', 'Hides the toast when you hide the game interface. Sounds still play.', '##trigger.hide.WithInterface' },
}
local hideValue = { false }

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

-- The New Trigger rows: the kind of mob, what it does, and the Create button
local function DrawMaking(options)
    local data = MobData()
    if data == nil then
        widgets.Note(noData)
        return
    end
    local zone = CurrentZone()
    local lists = KindLists(data, zone)

    widgets.BeginRow('Mob Type', mobSentence)
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
    widgets.EndRow()

    widgets.BeginRow('Action', actionSentence)
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
    widgets.EndRow()

    if widgets.Action('Create Trigger', createSentence, 'Create##trigger.making.create', createSpec) then
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

-- The triggers there are, in a table: each with its switch, its name, its sound, and Test and Remove
local tableFlags = nil

local function DrawList(options)
    local triggers = options.triggers
    if #triggers == 0 then
        widgets.Note(noTriggers)
        return
    end
    tableFlags = tableFlags or ImGuiTableFlags_SizingFixedFit
    if not imgui.BeginTable('##trigger.triggers', 4, tableFlags) then return end
    imgui.TableSetupColumn('##trigger.triggers.on', ImGuiTableColumnFlags_WidthFixed)
    imgui.TableSetupColumn('##trigger.triggers.name', ImGuiTableColumnFlags_WidthFixed)
    imgui.TableSetupColumn('##trigger.triggers.sound', ImGuiTableColumnFlags_WidthFixed)
    imgui.TableSetupColumn('##trigger.triggers.buttons', ImGuiTableColumnFlags_WidthFixed)
    -- the list of sounds as wide as a row's control column
    local _, textHeight = imgui.CalcTextSize('A')
    local soundWidth = (textHeight or 14) * widgets.RowControlWidth
    local removed = nil
    for index, trigger in ipairs(triggers) do
        imgui.TableNextRow()
        imgui.PushID(index)
        imgui.TableNextColumn()
        if imgui.Checkbox('##enabled', trigger.enabled) then shared.app:Save() end
        imgui.TableNextColumn()
        imgui.AlignTextToFramePadding()
        imgui.Text(TriggerText(trigger))
        imgui.TableNextColumn()
        SoundCombo('##sound', trigger, 'trigger', soundWidth)
        imgui.TableNextColumn()
        -- the trigger's sound, and its words in the toast if that is switched on
        if imgui.SmallButton('Test') then
            Indicate(trigger)
            Try(trigger.sound)
        end
        imgui.SameLine()
        if imgui.SmallButton('Remove') then
            removed = index
        end
        imgui.PopID()
    end
    imgui.EndTable()
    if removed ~= nil then
        table.remove(triggers, removed)
        IndexTriggers(triggers)
        shared.app:Save()
    end
end

-- The foot of the Triggers tab: the mobs of the kind chosen that are in the area, put together when
-- the kind or the area is another one; with no kind chosen, how many triggers are listened for
local function TriggersStatus(options)
    if making.mob == nil then
        local on = 0
        for _, trigger in ipairs(options.triggers) do
            if trigger.enabled[1] then on = on + 1 end
        end
        return ('Listening for %d of %d triggers.'):format(on, #options.triggers)
    end
    local zone = CurrentZone()
    if making.saidOf ~= making.mob or making.saidIn ~= zone then
        local here = Area(zone).among[making.mob]
        making.saidOf, making.saidIn = making.mob, zone
        making.said = here ~= nil and ('%s mobs in %s: %s.'):format(making.mob, ZoneName(zone), (here:gsub('|', ', ')))
            or ('No %s mobs in %s.'):format(making.mob, ZoneName(zone))
    end
    return making.said
end

local function DrawTriggers(options)
    if widgets.Header('New Trigger', true) then
        DrawMaking(options)
    end
    if widgets.Header('Triggers') then
        DrawList(options)
    end
    widgets.Status(TriggersStatus(options))
end

-- The Toast tab: the switch, and under it the rows that mean something while it is on, then the
-- rules for hiding. Each row's spec takes the switch as its parent each draw: the settings table is
-- another after a change of character.
local toastSpec = { }
local durationSpec = { format = '%d s' }

local function DrawToast(options)
    indicator.sample = options.showIndicator[1]
    if not widgets.Header('Toast', true) then return end
    if widgets.Check('Enable Toast', 'Shows a small window saying what a trigger heard, as the chat log does. A sample shows while this tab is open.',
        options.showIndicator, '##trigger.indicator.enabled') then
        shared.app:Save()
    end
    toastSpec.parent, durationSpec.parent = options.showIndicator, options.showIndicator
    local _, done = widgets.Slider('Duration', 'How long each line stays.', options.indicatorSeconds, 1, 15, '##trigger.indicator.seconds', durationSpec)
    if done then shared.app:Save() end
    if widgets.Check('Fade In And Out', 'The toast fades in and out instead of popping.', options.fadeInOut, '##trigger.indicator.fade', toastSpec) then
        shared.app:Save()
    end
    local grow = widgets.Dropdown('Grow From', 'The side that stays where it is as the words get longer or shorter.',
        indicator.Grows, options.indicatorGrow, '##trigger.indicator.grow', toastSpec)
    if grow ~= nil then
        options.indicatorGrow = grow
        shared.app:Save()
    end

    widgets.Gap()
    for _, rule in ipairs(hideRules) do
        hideValue[1] = options.hide[rule[2]]
        if widgets.Check(rule[1], rule[3], hideValue, rule[4], toastSpec) then
            options.hide[rule[2]] = hideValue[1]
            shared.app:Save()
        end
    end
end

return { Draw = DrawTriggers, DrawToast = DrawToast }
