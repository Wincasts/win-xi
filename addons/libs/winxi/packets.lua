-- winxi.packets: the packets addons send and read, set out once.
--
-- Each has the game's number for it as id. One an addon sends has make, which gives the id and the
-- bytes for AddOutgoingPacket; one it reads has parse, which takes the packet's data:
--
--     AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.inventorySort:make(bag));
--
--     if e.id == packets.inbound.inventoryFinish.id then
--         local finish = packets.inbound.inventoryFinish.parse(e.data);
--     end
--
-- Only what an addon has needed so far is here: the bags, the treasure pool, and actions and the
-- messages that follow them.
local packets = { outbound = {}, inbound = {} };

-- Throws an item away: so many of it, from a slot of a bag
packets.outbound.inventoryDrop = {
    id = 0x028,
    make = function(this, quantity, container, slot)
        return this.id, struct.pack('IIBB', 0, quantity, container, slot):totable();
    end,
};

-- Moves an item: so many of it, from a slot of one bag to another bag, where the server finds it a
-- slot. Within one bag it is put onto the slot given, which joins two stacks of the same item.
packets.outbound.inventoryMove = {
    id = 0x029,
    make = function(this, quantity, fromContainer, toContainer, fromSlot, toSlot)
        if fromContainer ~= toContainer then
            toSlot = 0x52;
        end
        return this.id, struct.pack('IIBBBB', 0, quantity, fromContainer, toContainer, fromSlot, toSlot):totable();
    end,
};

-- Asks the server to tidy a bag: it puts together the part stacks of the same item. The server takes
-- several of these for one bag inside a second for a cheating tool, and removes the player: an addon
-- must leave a few seconds between them.
packets.outbound.inventorySort = {
    id = 0x03A,
    make = function(this, container)
        return this.id, struct.pack('II', 0, container):totable();
    end,
};

-- Casts a lot on an item in the treasure pool, by its place there
packets.outbound.treasureLot = {
    id = 0x041,
    make = function(this, slot)
        return this.id, { 0x00, 0x00, 0x00, 0x00, slot };
    end,
};

-- Passes on an item in the treasure pool
packets.outbound.treasurePass = {
    id = 0x042,
    make = function(this, slot)
        return this.id, { 0x00, 0x00, 0x00, 0x00, slot };
    end,
};

-- The server has finished sending what is in the bags (flag 1), or one bag
packets.inbound.inventoryFinish = {
    id = 0x01D,
    parse = function(data)
        return {
            flag = struct.unpack('i1', data, 0x04 + 1),
            container = struct.unpack('i1', data, 0x05 + 1),
        };
    end,
};

-- How many of an item there are in a slot has changed
packets.inbound.inventoryModify = {
    id = 0x01E,
};

-- Something has been done: an attack, a spell, an ability, and what came of it for each target. parse
-- takes the packet's data_raw; category says which kind it is, and so what param and the rest mean.
packets.inbound.action = {
    id = 0x028,
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
    categories = {
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
};

-- A line for the battle log that is not an action: an effect wearing off, an enemy defeated. parse
-- takes the packet's data; message is which line, target who it is about, param what it names.
packets.inbound.message = {
    id = 0x029,
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
};

return packets;
