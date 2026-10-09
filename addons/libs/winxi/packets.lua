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
-- Only what an addon has needed so far is here: the bags.
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

return packets;
