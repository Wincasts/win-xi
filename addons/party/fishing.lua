-- fishing: whether a fish is on the line. The game draws the fish's stamina gauge as part of its own
-- target window, though away from where the window sits; uihook keeps all the window draws from showing
-- while party replaces it, wherever they are, so party lets the window go for the fight and the gauge shows.
--
--     fishing.HandlePacket(e), fishing.HandlePacketOut(e)     every packet in and out goes by these
--     fishing.Hooked()              whether a fight is on
--
-- The fight begins with the server's fish packet (0x115), which holds the fish's starting stamina and
-- the seconds it may be fought for (at 0x10), and ends when the client says it is over: its fishing
-- packet (0x110, or 0x066 as some clients still send) with mode 3, the mini-game ended, or 4, the
-- catch released (the mode at 0x0E). A change of area ends it too, and should neither come, so does the
-- time the fish may be fought for, and a little more.
local fishing = { }

local FISH, FISHING, FISHING_OLD = 0x115, 0x110, 0x066
local END_GAME, RELEASE = 3, 4
local GRACE = 30 -- seconds past the fight's time limit before it is taken to be over

local endsAt = nil -- os.clock() when the fight is taken to be over, or nil without one

function fishing.HandlePacket(e)
    if e.id == FISH and e.data ~= nil and #e.data >= 0x12 then
        local seconds = e.data:byte(0x10 + 1) + e.data:byte(0x11 + 1) * 256
        endsAt = os.clock() + math.min(600, seconds) + GRACE
    elseif e.id == 0x00A or e.id == 0x00B then
        endsAt = nil
    end
end

function fishing.HandlePacketOut(e)
    if endsAt == nil or (e.id ~= FISHING and e.id ~= FISHING_OLD) or e.data == nil or #e.data < 0x0F then return end
    local mode = e.data:byte(0x0E + 1)
    if mode == END_GAME or mode == RELEASE then endsAt = nil end
end

function fishing.Hooked()
    if endsAt ~= nil and os.clock() > endsAt then endsAt = nil end
    return endsAt ~= nil
end

return fishing
