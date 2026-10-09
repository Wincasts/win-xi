-- winxi.debounce: runs a function once things have gone quiet.
--
--     debounce(Refresh)
--
-- Refresh is called a second after the last time it was asked for, however many times that was: for
-- work set off by packets that come in bursts, to be done once at the end of the burst.
local delay = ashita.time.qpf();
local asked = {};
local checks = {}; -- fn -> what looks, a second on, at whether it has gone quiet: made once

local function debounce(fn)
    asked[fn] = ashita.time.qpc();

    local check = checks[fn];
    if check == nil then
        check = function()
            local last = asked[fn];
            if last and ashita.time.qpc().q >= (last.q + delay.q) then
                fn();
                asked[fn] = nil;
            end
        end;
        checks[fn] = check;
    end
    ashita.tasks.once(1, check);
end

return debounce;
