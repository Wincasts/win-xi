local winxiPackets = require('winxi.packets')

local inboundAction = {
    id = winxiPackets.inbound.action.id,
    name = 'Action',
    parse = winxiPackets.inbound.action.parse,
    actionTypes = winxiPackets.inbound.action.categories,
}

local inboundBasic = {
    id = winxiPackets.inbound.message.id,
    name = 'Basic',
    parse = winxiPackets.inbound.message.parse,
}

-- The action in the packet being handled, parsed the first time a tool asks for it and then handed to
-- every other tool that asks, rather than each parsing the same packet again. party.lua calls reset as
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
