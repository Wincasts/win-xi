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

-- The action in the packet being handled, parsed the first time a tool asks for it and then handed to
-- every other tool that asks, rather than each parsing the same packet again. xiframes calls reset as
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
    inbound = {
        action = inboundAction,
        basic = inboundBasic,
    },
}

return packets
