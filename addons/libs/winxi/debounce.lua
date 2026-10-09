-- winxi.debounce: runs a function once things have gone quiet.
--
--     debounce(Refresh)
--
-- Refresh is called a second after the last time it was asked for, however many times that was: for
-- work set off by packets that come in bursts, to be done once at the end of the burst.
local delay = ashita.time.qpf();
local asked = {};

local function debounce(fn)
    asked[fn] = ashita.time.qpc();
    ashita.tasks.once(1, function()
        local now = ashita.time.qpc();
        if asked[fn] and now.q >= (asked[fn].q + delay.q) then
            fn();
            asked[fn] = nil;
        end
    end);
end

return debounce;
