local bit = require('bit')

local outboundStartSynth = {
    id = 0x096,
    name = 'Start Synth',
    parse = function(packet)
        local startSynth = {
            crystal = struct.unpack('H', packet, 0x06 + 1),
            crystalIdx = struct.unpack('B', packet, 0x08 + 1),
            ingredientCount = struct.unpack('B', packet, 0x09 + 1),
            ingredient = {},
            ingredientIdx = {},
        }

        for i=0, 7 do
            startSynth.ingredient[i] = struct.unpack('H', packet, 0x0A + (i * 2) + 1)
        end

        for i=0, 7 do
            startSynth.ingredientIdx[i] = struct.unpack('B', packet, 0x1A + (i * 2) + 1)
        end

        return startSynth
    end,
}

local outboundFishingAction = {
    id = 0x110,
    name = 'Fishing Action',
    parse = function(packet)
        local fishingAction = {
            player = struct.unpack('I', packet, 0x04 + 1),
            fishHp = struct.unpack('I', packet, 0x08 + 1),
            playerIdx = struct.unpack('H', packet, 0x0C + 1),
            action = struct.unpack('B', packet, 0x0E + 1),
            catchKey = struct.unpack('I', packet, 0x10 + 1),
        }

        return fishingAction
    end,
    actionMap = {
        ['Cast'] = 2,
        ['Catch'] = 3,
        ['Stop'] = 4,
    },
}

local inboundCaughtFish = {
    id = 0x027,
    name = 'Fish Catch',
    ---@param packet string
    parse = function(packet)
        local fish = {
            player = struct.unpack('I', packet, 0x04 + 1),
            playerIdx = struct.unpack('I', packet, 0x08 + 1),
            message = struct.unpack('H', packet, 0x0A + 1),
            fishId = struct.unpack('H', packet, 0x10 + 1),
            count = struct.unpack('B', packet, 0x14 + 1),
        }

        return fish
    end
}

local inboundAction = {
    id = 0x028,
    name = 'Action',
    ---@param packet userdata
    ---@return ActionPacket
    parse = function(packet)
        -- Collect top-level metadata. The category field will provide the context
        -- for the rest of the packet - that should be enough information to figure
        -- out what each target and action field are used for.
        ---@type ActionPacket
        local action = {
            actor_id     = ashita.bits.unpack_be(packet,  40, 32),
            target_count = ashita.bits.unpack_be(packet,  72,  6),
            result_count = ashita.bits.unpack_be(packet,  78,  4),
            category     = ashita.bits.unpack_be(packet,  82,  4),
            param        = ashita.bits.unpack_be(packet,  86, 32),
            recast       = ashita.bits.unpack_be(packet, 118, 32),
            targets      = {}
        }

        local bit_offset = 150

        -- Collect target information. The ID is the server ID, not the entity idx.
        for i = 1, action.target_count do
            action.targets[i] = {
                id           = ashita.bits.unpack_be(packet, bit_offset,      32),
                action_count = ashita.bits.unpack_be(packet, bit_offset + 32,  4),
                actions      = {}
            }

            -- Collect per-target action information. This is where more identifiers
            -- for what's being used lie - often the animation can be used for that
            -- purpose. Otherwise the message may be what you want.
            for j = 1, action.targets[i].action_count do
                action.targets[i].actions[j] = {
                    miss     = ashita.bits.unpack_be(packet, bit_offset + 36,  3),
                    kind     = ashita.bits.unpack_be(packet, bit_offset + 39,  2),
                    sub_kind = ashita.bits.unpack_be(packet, bit_offset + 41, 12),
                    info     = ashita.bits.unpack_be(packet, bit_offset + 53,  5),
                    scale    = ashita.bits.unpack_be(packet, bit_offset + 58,  5),
                    param    = ashita.bits.unpack_be(packet, bit_offset + 63, 17),
                    message  = ashita.bits.unpack_be(packet, bit_offset + 80, 10),
                    bit      = ashita.bits.unpack_be(packet, bit_offset + 90, 31),
                    has_proc           = false,
                    proc_animation     = nil,
                    proc_effect        = nil,
                    proc_param         = nil,
                    proc_message       = nil,
                    has_reaction       = false,
                    reaction_animation = nil,
                    reaction_effect    = nil,
                    reaction_param     = nil,
                    reaction_message   = nil,
                }

                -- Collect additional effect information for the action. This is
                -- where you'll find information about skillchains, enspell damage,
                -- et cetera.
                if ashita.bits.unpack_be(packet, bit_offset + 121, 1) == 1 then
                    action.targets[i].actions[j].has_proc       = true
                    action.targets[i].actions[j].proc_animation = ashita.bits.unpack_be(packet, bit_offset + 122, 6)
                    action.targets[i].actions[j].proc_effect    = ashita.bits.unpack_be(packet, bit_offset + 128, 4)
                    action.targets[i].actions[j].proc_param     = ashita.bits.unpack_be(packet, bit_offset + 132, 17)
                    action.targets[i].actions[j].proc_message   = ashita.bits.unpack_be(packet, bit_offset + 149, 10)

                    bit_offset = bit_offset + 37
                end

                -- Collect reaction effect information like spikes.
                if ashita.bits.unpack_be(packet, bit_offset + 122, 1) == 1 then
                    action.targets[i].actions[j].has_reaction       = true
                    action.targets[i].actions[j].reaction_animation = ashita.bits.unpack_be(packet, bit_offset + 123, 6)
                    action.targets[i].actions[j].reaction_effect    = ashita.bits.unpack_be(packet, bit_offset + 129, 4)
                    action.targets[i].actions[j].reaction_param     = ashita.bits.unpack_be(packet, bit_offset + 133, 14)
                    action.targets[i].actions[j].reaction_message   = ashita.bits.unpack_be(packet, bit_offset + 147, 10)

                    bit_offset = bit_offset + 34
                end

                bit_offset = bit_offset + 87
            end

            bit_offset = bit_offset + 36
        end

        return action
    end,
    actionTypes = {
        None = 0,
        Attack = 1,
        RangedFinish = 2,
        WeaponskillFinish = 3,
        SpellFinish = 4,
        ItemFinish = 5,
        AbilityFinish = 6,
        WeaponskillStart = 7,
        SpellStart = 8,
        ItemStart = 9,
        AbilityStart = 10,
        MobSkillFinish = 11,
        RangedStart = 12,
        PetAbilityFinish = 13,
        Dance = 14,
        RunWardEffusion = 15,
        Quarry = 16,
        Sprint = 17,
    }
}

local inboundBasic = {
    id = 0x029,
    name = 'Basic',
    ---@param packet string
    parse = function(packet)
        local basic = {
            sender     = struct.unpack('i4', packet, 0x04 + 1),
            target     = struct.unpack('i4', packet, 0x08 + 1),
            param      = struct.unpack('i4', packet, 0x0C + 1),
            value      = struct.unpack('i4', packet, 0x10 + 1),
            sender_tgt = struct.unpack('i2', packet, 0x14 + 1),
            target_tgt = struct.unpack('i2', packet, 0x16 + 1),
            message    = struct.unpack('i2', packet, 0x18 + 1),
        }

        return basic
    end
}

local inboundSpecial = {
    id = 0x02A,
    name = 'Special',
    ---@param packet string
    parse = function(packet)
        local special = {
            sender = struct.unpack('i4', packet, 0x04 + 1),
            param1 = struct.unpack('i4', packet, 0x08 + 1),
            param2 = struct.unpack('i4', packet, 0x0C + 1),
            param3 = struct.unpack('i4', packet, 0x10 + 1),
            param4 = struct.unpack('i4', packet, 0x14 + 1),
            senderIdx = struct.unpack('i2', packet, 0x18 + 1),
            message = struct.unpack('i2', packet, 0x1A + 1),
            -- name = struct.unpack('s', packet, 0x1E + 1),
        }

        return special
    end
}

local inboundSynthAnimation = {
    id = 0x030,
    name = 'Synth Animation',
    ---@param packet string
    parse = function(packet)
        local synthAnimation = {
            player = struct.unpack('I4', packet, 0x04 + 1),
            playerIdx = struct.unpack('H', packet, 0x08 + 1),
            effect = struct.unpack('H', packet, 0x0A + 1),
            param = struct.unpack('B', packet, 0x0C + 1),
            animation = struct.unpack('B', packet, 0x0D + 1),
        }

        return synthAnimation
    end
}

local inboundNpcMessage = {
    id = 0x036,
    name = 'NPC Message',
    ---@param packet string
    parse = function(packet)
        local message = {
            sender     = struct.unpack('I', packet, 0x04 + 1),
            sender_idx = struct.unpack('H', packet, 0x08 + 1),
            message    = struct.unpack('H', packet, 0x0A + 1),
            mode       = struct.unpack('B', packet, 0x0C + 1),
        }

        return message
    end
}

local inboundKeyItems = {
    id = 0x055,
    name = 'Key Items',
    ---@param packet userdata
    parse = function(packet)
        local keyItems = {
            heldList = {},
            seenList = {},
            type = ashita.bits.unpack_be(packet, 0x84 * 8, 8)
        }

        local idBase = keyItems.type * 512
        local heldBit = 0x04 * 8
        local seenBit = 0x44 * 8

        for i = 0, 511 do
            keyItems.heldList[idBase + i] = ashita.bits.unpack_be(packet, heldBit + i, 1) == 1
            keyItems.seenList[idBase + i] = ashita.bits.unpack_be(packet, seenBit + i, 1) == 1
        end

        return keyItems
    end
}

local inboundSynthResultPlayer = {
    id = 0x06F,
    name = 'Self Synth',
    ---@param packet string
    parse = function(packet)
        local selfSynth = {
            result = struct.unpack('B', packet, 0x04 + 1),
            quality = struct.unpack('b', packet, 0x05 + 1),
            count = struct.unpack('B', packet, 0x06 + 1),
            item = struct.unpack('H', packet, 0x08 + 1),
            lost = {
                [1] = struct.unpack('H', packet, 0x0A + 1),
                [2] = struct.unpack('H', packet, 0x0C + 1),
                [3] = struct.unpack('H', packet, 0x0E + 1),
                [4] = struct.unpack('H', packet, 0x10 + 1),
                [5] = struct.unpack('H', packet, 0x12 + 1),
                [6] = struct.unpack('H', packet, 0x14 + 1),
                [7] = struct.unpack('H', packet, 0x16 + 1),
                [8] = struct.unpack('H', packet, 0x18 + 1),
            },
            skill = {
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1A + 1), 63),
                    isSkillupAllowed = bit.band(struct.unpack('B', packet, 0x1A + 1), 40) == 40,
                    isDesynth = bit.band(struct.unpack('B', packet, 0x1A + 1), 80) == 80,
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1B + 1), 63),
                    isSkillupAllowed = bit.band(struct.unpack('B', packet, 0x1B + 1), 40) == 40,
                    isDesynth = bit.band(struct.unpack('B', packet, 0x1B + 1), 80) == 80,
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1C + 1), 63),
                    isSkillupAllowed = bit.band(struct.unpack('B', packet, 0x1C + 1), 40) == 40,
                    isDesynth = bit.band(struct.unpack('B', packet, 0x1C + 1), 80) == 80,
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1D + 1), 63),
                    isSkillupAllowed = bit.band(struct.unpack('B', packet, 0x1D + 1), 40) == 40,
                    isDesynth = bit.band(struct.unpack('B', packet, 0x1D + 1), 80) == 80,
                },
            },
            skillup = {
                [1] = struct.unpack('B', packet, 0x1E + 1),
                [2] = struct.unpack('B', packet, 0x1F + 1),
                [3] = struct.unpack('B', packet, 0x20 + 1),
                [4] = struct.unpack('B', packet, 0x21 + 1),
            },
            crystal = struct.unpack('H', packet, 0x22 + 1),
        }

        return selfSynth
    end
}

-- The action in the packet being handled, parsed the first time a tool asks for it and then handed to
-- every other tool that asks, rather than each parsing the same packet again. xitools calls reset as
-- each packet arrives. The result is shared, so tools must only read from it.
local sharedAction = nil

---@param e PacketInEventArgs
---@return ActionPacket
inboundAction.shared = function(e)
    if sharedAction == nil then
        sharedAction = inboundAction.parse(e.data_raw)
    end
    return sharedAction
end

inboundAction.reset = function()
    sharedAction = nil
end

local packets = {
    outbound = {
        startSynth = outboundStartSynth,
        fishingAction = outboundFishingAction,
    },
    inbound = {
        fishCatch = inboundCaughtFish,
        action = inboundAction,
        basic = inboundBasic,
        special = inboundSpecial,
        synthAnimation = inboundSynthAnimation,
        npcMessage = inboundNpcMessage,
        keyItems = inboundKeyItems,
        synthResultPlayer = inboundSynthResultPlayer,
    },
}

return packets
