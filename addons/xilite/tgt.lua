require('common')
local bit = require('bit')
local imgui = require('imgui')
local ui = require('ui')
local packets = require('utils/packets')

-- The compact view is a line in the party list's XivParty Style, set as the party's is
local xivparty = require('xivparty')
local us = require('us')

local StatusType = {
    -- standard fare
    Dia = 'dia',
    Bio = 'bio',
    Paralyze = 'para',
    Slow = 'slow',
    Gravity = 'grav',
    Blind = 'blind',
    Flash = 'flash',
    -- utility
    Silence = 'silence',
    Sleep = 'sleep',
    Bind = 'bind',
    Stun = 'stun',
    -- misc
    Virus = 'virus',
    Curse = 'curse',
    -- dots
    Poison = 'poison',
    Shock = 'shock',
    Rasp = 'rasp',
    Choke = 'choke',
    Frost = 'frost',
    Burn = 'burn',
    Drown = 'drown',
    -- bard stuff
    Requiem = 'requiem',
    Elegy = 'elegy',
    Threnody = 'threnody',
    ThrenodyEle = 'threnodyEle',
}

local ActionMap = {
    [  4] = {
        [ 23] = {
            name = 'Dia',
            dur = 60,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = T{ 2, 264, 252 },
        },
        [ 24] = {
            name = 'Dia II',
            dur = 120,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = T{ 2, 264, 252 },
        },
        [ 25] = {
            name = 'Dia III',
            dur = 150,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = T{ 2, 264, 252 },
        },
        [ 33] = {
            name = 'Diaga',
            dur = 60,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = T{ 2, 264, 252 },
        },
        [ 34] = {
            name = 'Diaga II',
            dur = 120,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = T{ 2, 264, 252 },
        },
        [230] = {
            name = 'Bio',
            dur = 60,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = T{ 2, 264, 252 },
        },
        [231] = {
            name = 'Bio II',
            dur = 120,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = T{ 2, 264, 252 },
        },
        [232] = {
            name = 'Bio III',
            dur = 150,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = T{ 2, 264, 252 },
        },
        [ 58] = {
            name = 'Paralyze',
            dur = 120,
            type = StatusType.Paralyze,
            msg = T{ 236, 277, 268, 271 },
        },
        [ 80] = {
            name = 'Paralyze II',
            dur = 120,
            type = StatusType.Paralyze,
            msg = T{ 236, 277, 268, 271 },
        },
        [356] = {
            name = 'Paralyzega',
            dur = 120,
            type = StatusType.Paralyze,
            msg = T{ 236, 277, 268, 271 },
        },
        [341] = {
            name = 'Jubaku: Ichi',
            dur = 180,
            type = StatusType.Paralyze,
            msg = T{ 237, 267, 278 },
        },
        [342] = {
            name = 'Jubaku: Ni',
            dur = 300,
            type = StatusType.Paralyze,
            msg = T{ 237, 267, 278 },
        },
        [343] = {
            name = 'Jubaku: San',
            dur = 420,
            type = StatusType.Paralyze,
            msg = T{ 237, 267, 278 },
        },
        [ 56] = {
            name = 'Slow',
            dur = 180,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [ 79] = {
            name = 'Slow II',
            dur = 180,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [357] = {
            name = 'Slowga',
            dur = 180,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [344] = {
            name = 'Hojo: Ichi',
            dur = 180,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [345] = {
            name = 'Hojo: Ni',
            dur = 300,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [346] = {
            name = 'Hojo: San',
            dur = 420,
            type = StatusType.Slow,
            msg = T{ 236, 277, 268, 271 },
        },
        [254] = {
            name = 'Blind',
            dur = 180,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [276] = {
            name = 'Blind II',
            dur = 180,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [361] = {
            name = 'Blindga',
            dur = 180,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [347] = {
            name = 'Kurayami: Ichi',
            dur = 180,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [348] = {
            name = 'Kurayami: Ni',
            dur = 300,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [349] = {
            name = 'Kurayami: San',
            dur = 420,
            type = StatusType.Blind,
            msg = T{ 236, 277, 268, 271 },
        },
        [216] = {
            name = 'Gravity',
            dur = 120,
            type = StatusType.Gravity,
            msg = T{ 236, 277, 268, 271 },
        },
        [217] = {
            name = 'Gravity II',
            dur = 180,
            type = StatusType.Gravity,
            msg = T{ 236, 277, 268, 271 },
        },
        [112] = {
            name = 'Flash',
            dur = 12,
            type = StatusType.Flash,
            msg = T{ 236, 277, 268, 271 },
        },
        [ 59] = {
            name = 'Silence',
            dur = 120,
            type = StatusType.Silence,
            msg = T{ 236, 277, 268, 271 },
        },
        [359] = {
            name = 'Silencega',
            dur = 120,
            type = StatusType.Silence,
            msg = T{ 236, 277, 268, 271 },
        },
        [253] = {
            name = 'Sleep',
            dur = 60,
            type = StatusType.Sleep,
            msg = T{ 236, 277, 268, 271 },
        },
        [259] = {
            name = 'Sleep II',
            dur = 90,
            type = StatusType.Sleep,
            msg = T{ 236, 277, 268, 271 },
        },
        [273] = {
            name = 'Sleepga',
            dur = 60,
            type = StatusType.Sleep,
            msg = T{ 236, 277, 268, 271 },
        },
        [274] = {
            name = 'Sleepga II',
            dur = 90,
            type = StatusType.Sleep,
            msg = T{ 236, 277, 268, 271 },
        },
        [463] = {
            name = 'Foe Lullaby',
            dur = 60,
            type = StatusType.Sleep,
            msg = T{ 237, 267, 278 },
        },
        [376] = {
            name = 'Horde Lullaby',
            dur = 60,
            type = StatusType.Sleep,
            msg = T{ 237, 267, 278 },
        },
        [258] = {
            name = 'Bind',
            dur = 60,
            type = StatusType.Bind,
            msg = T{ 236, 277, 268, 271 },
        },
        [362] = {
            name = 'Bindga',
            dur = 60,
            type = StatusType.Bind,
            msg = T{ 236, 277, 268, 271 },
        },
        [252] = {
            name = 'Stun',
            dur = 5,
            type = StatusType.Stun,
            msg = T{ 236, 277, 268, 271 },
        },
        [220] = {
            name = 'Poison',
            dur = 30,
            type = StatusType.Poison,
            msg = T{ 236, 277, 268, 271 },
        },
        [221] = {
            name = 'Poison II',
            dur = 120,
            type = StatusType.Poison,
            msg = T{ 236, 277, 268, 271 },
        },
        [225] = {
            name = 'Poisonga',
            dur = 60,
            type = StatusType.Poison,
            msg = T{ 236, 277, 268, 271 },
        },
        [226] = {
            name = 'Poisonga II',
            dur = 120,
            type = StatusType.Poison,
            msg = T{ 236, 277, 268, 271 },
        },
        [350] = {
            name = 'Dokumori: Ichi',
            dur = 60,
            type = StatusType.Poison,
            msg = T{ 237, 267, 278 },
        },
        [351] = {
            name = 'Dokumori: Ni',
            dur = 120,
            type = StatusType.Poison,
            msg = T{ 237, 267, 278 },
        },
        [352] = {
            name = 'Dokumori: San',
            dur = 360,
            type = StatusType.Poison,
            msg = T{ 237, 267, 278 },
        },
        [239] = {
            name = 'Shock',
            dur = 120,
            type = StatusType.Shock,
            over = StatusType.Drown,
            msg = T{ 237, 267, 278 },
        },
        [238] = {
            name = 'Rasp',
            dur = 120,
            type = StatusType.Rasp,
            over = StatusType.Shock,
            msg = T{ 237, 267, 278 },
        },
        [237] = {
            name = 'Choke',
            dur = 120,
            type = StatusType.Choke,
            over = StatusType.Rasp,
            msg = T{ 237, 267, 278 },
        },
        [236] = {
            name = 'Frost',
            dur = 120,
            type = StatusType.Frost,
            over = StatusType.Choke,
            msg = T{ 237, 267, 278 },
        },
        [235] = {
            name = 'Burn',
            dur = 120,
            type = StatusType.Burn,
            over = StatusType.Frost,
            msg = T{ 237, 267, 278 },
        },
        [240] = {
            name = 'Drown',
            dur = 120,
            type = StatusType.Drown,
            over = StatusType.Burn,
            msg = T{ 237, 267, 278 },
        },
        [421] = {
            name = 'Battlefield Elegy',
            dur = 150,
            type = StatusType.Elegy,
            msg = T{ 237, 267, 278 },
        },
        [422] = {
            name = 'Carnage Elegy',
            dur = 250,
            type = StatusType.Elegy,
            msg = T{ 237, 267, 278 },
        },
        [423] = {
            name = 'Massacre Elegy',
            dur = 350, -- ???
            type = StatusType.Elegy,
            msg = T{ 237, 267, 278 },
        },
        [368] = {
            name = 'Foe Requiem',
            dur = 100,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [369] = {
            name = 'Foe Requiem II',
            dur = 150,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [370] = {
            name = 'Foe Requiem III',
            dur = 200,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [371] = {
            name = 'Foe Requiem IV',
            dur = 250,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [372] = {
            name = 'Foe Requiem V',
            dur = 300,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [373] = {
            name = 'Foe Requiem VI',
            dur = 350,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [374] = {
            name = 'Foe Requiem VII',
            dur = 400,
            type = StatusType.Requiem,
            msg = T{ 237, 267, 278 },
        },
        [454] = {
            name = 'Fire Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'fire',
        },
        [455] = {
            name = 'Ice Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'ice',
        },
        [456] = {
            name = 'Wind Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'wind',
        },
        [457] = {
            name = 'Earth Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'earth',
        },
        [458] = {
            name = 'Lightning Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'lightning',
        },
        [459] = {
            name = 'Water Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'water',
        },
        [460] = {
            name = 'Light Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'light',
        },
        [461] = {
            name = 'Dark Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = T{ 237, 267, 278 },
            ele = 'dark',
        },
    },
}

-- The state we're operating on is the expiry time of the statuses
local DefaultDebuffs = {
    -- standard fare
    dia = 0,
    bio = 0,
    para = 0,
    slow = 0,
    grav = 0,
    blind = 0,
    flash = 0,
    -- utility
    silence = 0,
    sleep = 0,
    bind = 0,
    stun = 0,
    -- misc
    virus = 0,
    curse = 0,
    -- dots
    poison = 0,
    shock = 0,
    rasp = 0,
    choke = 0,
    frost = 0,
    burn = 0,
    drown = 0,
    -- bard stuff
    requiem = 0,
    elegy = 0,
    threnody = 0,
    threnodyEle = nil,
}

local TrackedEnemies = { }

---@param object table
---@return table
local function DeepCopy(object)
    local lookup_table = {}
    local function _copy(obj)
        if type(obj) ~= "table" then
            return obj
        elseif lookup_table[obj] then
            return lookup_table[obj]
        end
        local new_table = {}
        lookup_table[obj] = new_table
        for index, value in pairs(obj) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(obj))
    end
    return _copy(object)
end

local function GetThrenodyColor(element)
    if element == 'light' then
        return ui.Colors.StatusWhite
    elseif element == 'dark' then
        return ui.Colors.StatusBlack
    elseif element == 'fire' then
        return ui.Colors.StatusRed
    elseif element == 'ice' then
        return ui.Colors.StatusCyan
    elseif element == 'wind' then
        return ui.Colors.StatusGreen
    elseif element == 'earth' then
        return ui.Colors.StatusBrown
    elseif element == 'lightning' then
        return ui.Colors.StatusYellow
    elseif element == 'water' then
        return ui.Colors.StatusBlue
    end
end

---@param debuffs table
---@param action any
local function HandleAction(debuffs, action)
    local now = os.time()

    for _, target in pairs(action.targets) do
        for _, ability in pairs(target.actions) do
            if ActionMap[action.category] then
                local actionId = action.param
                local message = ability.message
                local map = ActionMap[action.category][actionId]

                if map and map.msg:contains(message) then
                    debuffs[target.id] = debuffs[target.id] or DeepCopy(DefaultDebuffs)
                    debuffs[target.id][map.type] = now + map.dur

                    if map.ele then
                        debuffs[target.id][StatusType.ThrenodyEle] = map.ele
                    end

                    if map.over then
                        debuffs[target.id][map.over] = 0
                    end
                end
            end
        end
    end
end

-- The basic messages that report a death: being defeated, and falling to the ground
local DeathMessages = {
    [  6] = true,
    [ 20] = true,
    [113] = true,
    [406] = true,
    [605] = true,
    [646] = true,
}

---@param debuffs table
---@param basic string
local function HandleBasic(debuffs, basic)
    -- if we're tracking a mob that dies, reset its status
    if DeathMessages[basic.message] and debuffs[basic.target] then
        debuffs[basic.target] = nil
    elseif basic.message == 206 then
        if debuffs[basic.target] == nil then
            return
        end

        if basic.param == 2 or basic.param == 19 then
            debuffs[basic.target].sleep = 0
        elseif basic.param == 3 or basic.param == 540 then
            debuffs[basic.target].poison = 0
        elseif basic.param == 4 or basic.param == 566 then
            debuffs[basic.target].para = 0
        elseif basic.param == 5 then
            debuffs[basic.target].blind = 0
        elseif basic.param == 156 then
            debuffs[basic.target].flash = 0
        elseif basic.param == 6 then
            debuffs[basic.target].silence = 0
        elseif basic.param == 8 then
            debuffs[basic.target].virus = 0
        elseif basic.param == 9 or basic.param == 20 then
            debuffs[basic.target].curse = 0
        elseif basic.param == 10 then
            debuffs[basic.target].stun = 0
        elseif basic.param == 11 then
            debuffs[basic.target].bind = 0
        elseif basic.param == 12 or basic.param == 567 then
            debuffs[basic.target].grav = 0
        elseif basic.param == 13 or basic.param == 565 then
            debuffs[basic.target].slow = 0
        elseif basic.param == 128 then
            debuffs[basic.target].burn = 0
        elseif basic.param == 129 then
            debuffs[basic.target].frost = 0
        elseif basic.param == 130 then
            debuffs[basic.target].choke = 0
        elseif basic.param == 131 then
            debuffs[basic.target].rasp = 0
        elseif basic.param == 132 then
            debuffs[basic.target].shock = 0
        elseif basic.param == 133 then
            debuffs[basic.target].drown = 0
        elseif basic.param == 134 then
            debuffs[basic.target].dia = 0
        elseif basic.param == 135 then
            debuffs[basic.target].bio = 0
        elseif basic.param == 192 then
            debuffs[basic.target].requiem = 0
        elseif basic.param == 194 then
            debuffs[basic.target].elegy = 0
        elseif basic.param == 217 then
            debuffs[basic.target].threnody = 0
            debuffs[basic.target].threnodyEle = nil
        end
    end
end

---@param name     string
---@param distance number
---@param options  table
local function DrawHeader(name, distance, options)
    imgui.Text(name)

    local dist = string.format('%.1fm', distance)
    local width = imgui.CalcTextSize(dist) + ui.Styles.WindowPadding[1]

    imgui.SameLine()
    imgui.SetCursorPosX(ui.PaddedWidth(options.size[1]) - width)
    imgui.Text(dist)
end

-- The lowest bit of an entity's spawn flags is set for a player character, and for nothing else
local spawnFlagPlayer = 0x01

---@param entity Entity
---@return boolean
local function IsPlayer(entity)
    return entity.SpawnFlags ~= nil and bit.band(entity.SpawnFlags, spawnFlagPlayer) ~= 0
end

-- The HP text is coloured by how low the HP is for players only; for anything else it stays white.
---@param hpPercent integer
---@param colorByHp boolean
local function DrawHp(hpPercent, colorByHp)
    local title = string.format('HP %3i%%', hpPercent)
    local textColor = ui.Colors.White
    local barColor = ui.Colors.HpBar

    if not colorByHp or hpPercent > 75 then
        textColor = ui.Colors.White
    elseif hpPercent > 50 then
        textColor = ui.Colors.Yellow
    elseif hpPercent > 25 then
        textColor = ui.Colors.Orange
    elseif hpPercent >= 0 then
        textColor = ui.Colors.Red
    end

    imgui.PushStyleColor(ImGuiCol_Text, textColor)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, barColor)
    ui.DrawBar(title, hpPercent, 100, ui.Styles.BarSize, '')
    imgui.PopStyleColor(2)
end

local function DrawSeparator()
    imgui.PopStyleVar()
    imgui.Text('')
    imgui.SameLine()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
end

local function DrawStatusEntry(text, isActive, color)
    if isActive then
        imgui.PushStyleColor(ImGuiCol_Text, color)
    else
        imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.StatusGrey)
    end

    imgui.Text(text)
    imgui.SameLine()
    imgui.PopStyleColor()
end

---@param debuffs table
local function DrawStatus(debuffs)
    local now = os.time()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
    DrawStatusEntry('D',  now < debuffs.dia, ui.Colors.StatusWhite)
    DrawStatusEntry('B',  now < debuffs.bio, ui.Colors.StatusBlack)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('P',  now < debuffs.para, ui.Colors.StatusWhite)
    DrawStatusEntry('S',  now < debuffs.slow, ui.Colors.StatusWhite)
    DrawStatusEntry('E',  now < debuffs.elegy, ui.Colors.StatusBrown)
    DrawStatusEntry('G',  now < debuffs.grav, ui.Colors.StatusBlack)
    DrawStatusEntry('B',  now < debuffs.blind, ui.Colors.StatusBlack)
    DrawStatusEntry('F',  now < debuffs.flash, ui.Colors.StatusWhite)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('Si', now < debuffs.silence, ui.Colors.StatusWhite)
    DrawSeparator()
    DrawStatusEntry('Sl', now < debuffs.sleep, ui.Colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Bi', now < debuffs.bind, ui.Colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Po', now < debuffs.poison, ui.Colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Rq', now < debuffs.requiem, ui.Colors.StatusWhite)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('S',  now < debuffs.shock, ui.Colors.StatusYellow)
    DrawStatusEntry('R',  now < debuffs.rasp, ui.Colors.StatusBrown)
    DrawStatusEntry('C',  now < debuffs.choke, ui.Colors.StatusGreen)
    DrawStatusEntry('F',  now < debuffs.frost, ui.Colors.StatusCyan)
    DrawStatusEntry('B',  now < debuffs.burn, ui.Colors.StatusRed)
    DrawStatusEntry('D',  now < debuffs.drown, ui.Colors.StatusBlue)

    if debuffs.threnodyEle ~= nil and now < debuffs.threnody then
        imgui.NewLine()
        imgui.Text('Threnody: ')
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, GetThrenodyColor(debuffs.threnodyEle))
        imgui.Text(debuffs.threnodyEle)
        imgui.PopStyleColor()
    end

    imgui.PopStyleVar()
end

---@param entity Entity
---@param options table
local function DrawTgt(entity, options)
    DrawHeader(entity.Name, math.sqrt(entity.Distance), options)
    DrawHp(entity.HPPercent, IsPlayer(entity))
    if options.showStatus[1] then
        DrawStatus(TrackedEnemies[entity.ServerId] or DefaultDebuffs)
    end
end

-- The compact view: one line in the party list's XivParty Style, with the name, the HP bar with its
-- percentage, and the distance under the name where a party member's TP is. The debuffs go under it.
local compactNameChars = 13 -- as much of a name as fits before the HP figure
local compactLine = { isInZone = true, tp = 0 }
local compactLines = { compactLine }

---@param entity Entity
---@param options table
local function DrawCompactTgt(entity, options)
    local line = compactLine
    line.name = entity.Name
    line.serverId = -(entity.ServerId or 0) -- its own glow, apart from a party member's of the same id
    line.hpp = entity.HPPercent
    line.hpText = string.format('%d%%', entity.HPPercent)
    line.tpText = string.format('%.1fm', math.sqrt(entity.Distance))
    line.plainHp = not IsPlayer(entity)

    -- set as the party's lists are, but for what is this line's own: more of the name, and the
    -- distance always, whatever is set for TP
    local settings = us.StyleSettings() or { }
    settings.nameChars = compactNameChars
    settings.showTp = true
    xivparty.Draw(compactLines, 'pets', nil, settings)

    if options.showStatus[1] then
        DrawStatus(TrackedEnemies[entity.ServerId] or DefaultDebuffs)
    end
end

-- A target window's content, in whichever view is set
local compact = false

local function DrawTarget(entity, window)
    if compact then
        DrawCompactTgt(entity, window)
    else
        DrawTgt(entity, window)
    end
end

-- The entity each window last showed, by window name
local lastShown = { }

-- Draws one of the target windows for the entity at index, if there is one (the client can hold an
-- index for an entity it no longer knows about, so the entity is fetched and checked first). When there
-- is none, the window goes on showing the entity it last showed for as long as it is fading out.
local function DrawTargetWindow(window, gOptions, index)
    local entity = index ~= 0 and GetEntity(index) or nil
    local wanted = entity ~= nil

    if wanted then
        lastShown[window.name] = index
    elseif lastShown[window.name] and ui.Lingers(window, gOptions) then
        entity = GetEntity(lastShown[window.name])
    end

    if entity == nil then
        return
    end

    ui.DrawUiWindow(window, gOptions, function()
        DrawTarget(entity, window)
    end, wanted, nil, compact)
end

---@type xitool
local tgt = {
    Name = 'tgt',
    DefaultSettings = T{
        isEnabled = T{ true },
        isVisible = T{ true },
        compact = T{ false }, -- each window as one line in the party list's XivParty Style
        showMain = T{ true },
        showSub = T{ false },
        showTot = T{ false },
        mainWindow = T{
            isVisible = T{ true },
            showStatus = T{ false },
            name = 'xilite.tgt.main',
            size = T{ 276, -1 },
            pos = T{ 100, 100 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        subWindow = T{
            isVisible = T{ true },
            showStatus = T{ false },
            name = 'xilite.tgt.sub',
            size = T{ 276, -1 },
            pos = T{ 100, 200 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        totWindow = T{
            isVisible = T{ true },
            showStatus = T{ false },
            name = 'xilite.tgt.tot',
            size = T{ 276, -1 },
            pos = T{ 386, 100 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
    },
    HandlePacket = function(e, options)
        -- don't track anything if we're not displaying it
        local showStatus =
            options.mainWindow.showStatus[1] or
            options.subWindow.showStatus[1] or
            options.totWindow.showStatus[1]

        if not showStatus then return end

        -- clear state on zone changes
        -- TODO: clear mob state on death
        if e.id == 0x00A then
            TrackedEnemies = { }
        elseif e.id == 0x028 then
            HandleAction(TrackedEnemies, packets.inbound.action.shared(e))
        elseif e.id == 0x029 then
            HandleBasic(TrackedEnemies, packets.inbound.basic.parse(e.data))
        end
    end,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('tgt') then
            ui.BeginLabels('xilite.tgt')
            ui.Label('Enabled')
            imgui.Checkbox('##tgt.1', options.isEnabled)

            -- Settings saved before this option existed have no value for it
            if options.compact == nil then
                options.compact = T{ false }
            end
            ui.Label('Compact', true)
            imgui.Checkbox('##tgt.compact', options.compact)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Draws each target window as one line in the style of the party list\'s XivParty Style: the name, an HP bar with its percentage, and the distance.\nIts size, text sizes, outline and glow are the ones set for the party list on the us tab.')
            end

            ui.Gap()
            ui.Label('Show Target')
            imgui.Checkbox('##tgt.2', options.showMain)
            ui.Label('Target Debuffs')
            imgui.Checkbox('##tgt.3', options.mainWindow.showStatus)

            ui.Label('Show Sub-Target')
            imgui.Checkbox('##tgt.4', options.showSub)
            ui.Label('Sub-Target Debuffs')
            imgui.Checkbox('##tgt.5', options.subWindow.showStatus)

            ui.Label('Show Target Of Target')
            imgui.Checkbox('##tgt.6', options.showTot)
            ui.Label('Target Of Target Debuffs')
            imgui.Checkbox('##tgt.7', options.totWindow.showStatus)

            ui.Gap()
            ui.Label('Target Position')
            if imgui.InputInt2('##tgt.8', options.mainWindow.pos) then
                imgui.SetWindowPos(options.mainWindow.name, options.mainWindow.pos)
            end
            ui.Label('Sub-Target Position')
            if imgui.InputInt2('##tgt.9', options.subWindow.pos) then
                imgui.SetWindowPos(options.subWindow.name, options.subWindow.pos)
            end
            ui.Label('Target Of Target Position')
            if imgui.InputInt2('##tgt.10', options.totWindow.pos) then
                imgui.SetWindowPos(options.totWindow.name, options.totWindow.pos)
            end
            imgui.EndTabItem()
        end
    end,
    DrawMain = function(options, gOptions)
        compact = options.compact ~= nil and options.compact[1] == true
        local tgt = AshitaCore:GetMemoryManager():GetTarget()
        local targetId = tgt:GetTargetIndex(0)
        local targetActive = tgt:GetIsActive(0) == 1
        local subTargetId = tgt:GetTargetIndex(1)
        local subTargetActive = tgt:GetIsSubTargetActive() == 1
        local totId = 0

        -- the target struct appears to be a stack, so when we have two targets
        -- that means the subtarget is actually in [0] and main moves to [1]
        if subTargetActive then
            targetId, subTargetId = subTargetId, targetId
        end

        -- TODO: if no subtarget, check for stpt/stal

        -- the target of target comes from the main target itself, so that it still shows when the
        -- main target window is switched off
        local mainIndex = (targetActive and targetId ~= 0) and targetId or 0
        local mainEntity = mainIndex ~= 0 and GetEntity(mainIndex) or nil
        if mainEntity then
            totId = mainEntity.TargetedIndex or 0
        end

        -- TODO: compact tot display
        DrawTargetWindow(options.mainWindow, gOptions, options.showMain[1] and mainIndex or 0)
        DrawTargetWindow(options.subWindow, gOptions, (options.showSub[1] and subTargetActive) and subTargetId or 0)
        DrawTargetWindow(options.totWindow, gOptions, options.showTot[1] and totId or 0)
    end,
    DrawSample = function(options, gOptions)
        compact = options.compact ~= nil and options.compact[1] == true
        -- each window only if it is one that is switched on
        local samples = {
            { options.mainWindow, { Name = 'Sample Target', Distance = 8 * 8, HPPercent = 75, ServerId = 0 }, options.showMain[1] },
            { options.subWindow, { Name = 'Sample Sub-target', Distance = 12 * 12, HPPercent = 100, ServerId = 0 }, options.showSub[1] },
            { options.totWindow, { Name = 'Sample Target of Target', Distance = 3 * 3, HPPercent = 40, ServerId = 0 }, options.showTot[1] },
        }

        for _, sample in ipairs(samples) do
            if sample[3] then
                ui.DrawUiWindow(sample[1], gOptions, function()
                    DrawTarget(sample[2], sample[1])
                end, nil, nil, compact)
            end
        end
    end,
}

return tgt
