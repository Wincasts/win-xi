require('common')
local bit = require('bit')
local imgui = require('imgui')
local ui = require('ui')

-- The same bars and window width as the party windows (us), so the two line up
local barSize = ui.Styles.ShortBarSize
local windowWidth = 276

local jobPup = 18
local partySize = 6

-- The automaton's HP and MP as last reported by the server, which sends them to its master only.
-- Nothing is known until the first report arrives (on zoning, job change, or when the automaton's state changes).
local automaton = { hp = nil, maxHp = 0, mp = nil, maxMp = 0 }

-- An exact value for a bar: the reported one while it still agrees with the percentage on screen,
-- otherwise worked out from the maximum, in case the server has not sent a fresh report.
local function ExactValue(reported, max, percent)
    if reported == nil or max <= 0 then
        return nil
    end

    if math.abs(reported / max * 100 - percent) <= 1 then
        return reported
    end
    return math.floor(max * percent / 100 + 0.5)
end

local function IsPuppetmaster()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    return player:GetMainJob() == jobPup or player:GetSubJob() == jobPup
end

---@class PetInfo
---@field name     string
---@field owner    string?  the party member it belongs to; nil for the player's own pet
---@field distance number
---@field hpp      integer
---@field mpp      integer? only known for the player's own pet
---@field tp       integer? only known for the player's own pet
---@field hp       integer? exact HP, shown in place of the percentage when known
---@field mp       integer? exact MP, shown in place of the percentage when known

---@param pet     PetInfo
---@param options table
local function DrawName(pet, options)
    if pet.owner then
        imgui.Text(('%s (%s)'):format(pet.name, pet.owner))
    else
        imgui.Text(pet.name)
    end

    -- right-aligned by hand, the same way the party windows do it
    local dist = ('%.1fm'):format(pet.distance)
    local width = imgui.CalcTextSize(dist) + ui.Styles.WindowPadding[1]

    imgui.SameLine()
    imgui.SetCursorPosX(ui.PaddedWidth(options.size[1]) - width)
    imgui.Text(dist)
end

---@param pet PetInfo
local function DrawHp(pet)
    local overlay = pet.hp and ('%i'):format(pet.hp) or ('%i%%'):format(pet.hpp)

    imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.White)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, ui.Colors.HpBar)
    ui.DrawBar3(pet.hpp, 100, barSize, overlay)
    imgui.PopStyleColor(2)
end

---@param pet PetInfo
local function DrawMp(pet)
    local overlay = pet.mp and ('%i'):format(pet.mp) or ('%i%%'):format(pet.mpp)

    imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.White)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, ui.Colors.MpBar)
    imgui.SameLine()
    ui.DrawBar2(pet.mpp, 100, barSize, overlay)
    imgui.PopStyleColor(2)
end

---@param pet PetInfo
local function DrawTp(pet)
    local barColor = ui.TpBarColor(pet.tp, false)

    imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.White)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, barColor)
    imgui.SameLine()
    ui.DrawBar2(pet.tp, 3000, barSize, ('%i'):format(pet.tp))
    imgui.PopStyleColor(2)
end

-- A pet's name and distance over its bars. Only a pet's owner is told its MP and TP, so another
-- player's pet has the HP bar alone.
---@param pet     PetInfo
---@param options table
local function DrawPet(pet, options)
    DrawName(pet, options)
    DrawHp(pet)
    if pet.mpp ~= nil and pet.tp ~= nil then
        DrawMp(pet)
        DrawTp(pet)
    end
end

-- The entity of the pet belonging to the entity at ownerIndex, if it has one the client knows about
local function GetPetEntity(ownerIndex)
    if ownerIndex == nil or ownerIndex == 0 then
        return nil
    end

    local owner = GetEntity(ownerIndex)
    if owner == nil or owner.PetTargetIndex == nil or owner.PetTargetIndex == 0 then
        return nil
    end

    local pet = GetEntity(owner.PetTargetIndex)
    if pet == nil or pet.Name == nil then
        return nil
    end
    return pet
end

---@return PetInfo?
local function GetOwnPet(options)
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entity = GetPetEntity(party:GetMemberTargetIndex(0))
    if entity == nil then
        return nil
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local pet = {
        name = entity.Name,
        distance = math.sqrt(entity.Distance),
        hpp = entity.HPPercent,
        mpp = player:GetPetMPPercent(),
        tp = player:GetPetTP(),
    }

    -- Exact HP and MP are only known for a puppetmaster's automaton. On unless switched off.
    if (options.exactAutomaton == nil or options.exactAutomaton[1]) and IsPuppetmaster() then
        pet.hp = ExactValue(automaton.hp, automaton.maxHp, pet.hpp)
        pet.mp = ExactValue(automaton.mp, automaton.maxMp, pet.mpp)
    end

    return pet
end

-- The pets of the other members of the player's party who are in the same zone, in party order
---@return PetInfo[]
local function GetPartyPets()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local pets = { }

    for i = 1, partySize - 1 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberZone(i) == party:GetMemberZone(0) then
            local entity = GetPetEntity(party:GetMemberTargetIndex(i))
            if entity ~= nil then
                table.insert(pets, {
                    name = entity.Name,
                    owner = party:GetMemberName(i),
                    distance = math.sqrt(entity.Distance),
                    hpp = entity.HPPercent,
                })
            end
        end
    end

    return pets
end

local function ShowsPartyPets(options)
    return options.showParty == nil or options.showParty[1]
end

---@param pets    PetInfo[]
---@param options table
-- wanted is false when the pets are only being drawn for the window to fade out
local function DrawWindow(pets, options, gOptions, wanted)
    -- The width is fixed; one saved by an earlier version would not match the party windows
    options.size[1] = windowWidth

    ui.DrawUiWindow(options, gOptions, function()
        for _, pet in ipairs(pets) do
            DrawPet(pet, options)
        end
    end, wanted)
end

-- The pets last shown, which the window goes on showing while it fades out after the last one has gone
local lastPets = nil

---@type xitool
local pet = {
    Name = 'pet',
    DefaultSettings = T{
        isEnabled = T{ false },
        isVisible = T{ true },
        name = 'xitools.pet',
        size = T{ windowWidth, -1 },
        pos = T{ 100, 100 },
        flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        exactAutomaton = T{ true },
        showParty = T{ true },
    },
    HandlePacket = function(e, options, gOptions)
        -- Extended job info for puppetmaster: the automaton's current and maximum HP and MP
        if e.id == 0x044 and struct.unpack('B', e.data, 0x04 + 1) == jobPup then
            automaton.hp = struct.unpack('H', e.data, 0x68 + 1)
            automaton.maxHp = struct.unpack('H', e.data, 0x6A + 1)
            automaton.mp = struct.unpack('H', e.data, 0x6C + 1)
            automaton.maxMp = struct.unpack('H', e.data, 0x6E + 1)
        end
    end,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('pet') then
            ui.BeginLabels('xitools.pet')
            -- Settings saved before these options existed have no value for them
            if options.exactAutomaton == nil then
                options.exactAutomaton = T{ true }
            end
            if options.showParty == nil then
                options.showParty = T{ true }
            end

            ui.Label('Enabled')
            imgui.Checkbox('##pet.1', options.isEnabled)

            ui.Gap()
            ui.Label('Show Party Members\' Pets')
            imgui.Checkbox('##pet.2', options.showParty)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Lists the pets of the other members of your party under your own, with their owner\'s name.\nOnly their HP is shown: a pet\'s MP and TP are sent to its owner alone.')
            end
            ui.Label('Exact HP And MP (Puppetmaster)')
            imgui.Checkbox('##pet.3', options.exactAutomaton)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Shows your automaton\'s HP and MP as numbers rather than percentages.\nOnly applies while you are a puppetmaster; other pets always show percentages.')
            end

            ui.Gap()
            ui.Label('Position')
            if imgui.InputInt2('##pet.4', options.pos) then
                imgui.SetWindowPos(options.name, options.pos)
            end
            imgui.EndTabItem()
        end
    end,
    DrawMain = function(options, gOptions)
        if GetPlayerEntity() == nil then return end

        local pets = { }
        local own = GetOwnPet(options)
        if own ~= nil then
            table.insert(pets, own)
        end
        if ShowsPartyPets(options) then
            for _, partyPet in ipairs(GetPartyPets()) do
                table.insert(pets, partyPet)
            end
        end

        if #pets == 0 then
            if lastPets ~= nil and ui.Lingers(options, gOptions) then
                DrawWindow(lastPets, options, gOptions, false)
            end
            return
        end

        lastPets = pets
        DrawWindow(pets, options, gOptions)
    end,
    -- Real pets where there are any, with made-up ones filling the rest: the player's own, and one
    -- for each other party member when party pets are shown
    DrawSample = function(options, gOptions)
        local pets = { }
        table.insert(pets, GetPlayerEntity() and GetOwnPet(options) or { name = 'Sample Pet', distance = 4, hpp = 80, mpp = 60, tp = 1200 })

        if ShowsPartyPets(options) then
            local partyPets = GetPlayerEntity() and GetPartyPets() or { }
            for i = 1, partySize - 1 do
                table.insert(pets, partyPets[i] or {
                    name = ('Sample Pet %d'):format(i + 1),
                    owner = ('Sample %d'):format(i + 1),
                    distance = 4 + i * 2,
                    hpp = 100 - i * 15,
                })
            end
        end

        DrawWindow(pets, options, gOptions)
    end,
}

return pet
