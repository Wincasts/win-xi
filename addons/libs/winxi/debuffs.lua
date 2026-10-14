-- winxi.debuffs: which debuffs are on each enemy, and for how long yet.
--
-- The server never says what is on an enemy. It does say what everyone nearby casts and whether it
-- took hold, and when an effect wears off or its owner is defeated; this keeps count from those.
--
--     ashita.events.register('packet_in', 'example_packet_in', function(e)
--         debuffs.HandlePacket(e);                     -- every packet in goes by this
--     end);
--
--     debuffs.Remaining(serverId, debuffs.Kinds.Dia)   -- seconds left of it, or nil when it is not on
--     debuffs.Get(serverId, 'slow')                    -- { kind, name, expires, by, element }, or nil
--     debuffs.Active(serverId)                         -- a list of those, the first to run out first
--     debuffs.On(serverId)                             -- kind -> entry as kept, or nil: see below
--     debuffs.Clear()                                  -- forget everything
--
--     debuffs.StatusIds[kind]                          -- the game's number for the status of that kind
--
-- Those are the kinds above, from the spells of a table of this file's own. Apart from them, any status
-- the server says took hold on anyone is kept by its number, whatever put it there:
--
--     debuffs.Statuses(serverId)                       -- status -> { id, expires, by, category, param },
--                                                      -- as kept: one that has run out may be in it
--     debuffs.StatusRemaining(serverId, status)        -- seconds left of it, or nil when it is not on
--
-- category and param are the action's that put it there (4 and the spell's number for a spell). How long
-- it lasts is the server's base duration for that spell or monster's move, or failing that the usual
-- one for the status (winxi.debuff_durations, made from the server's scripts), or failing that
-- DEFAULT_SECONDS; the server saying it wore off, or was taken off, ends it before that.
--
-- name is the spell that put it there, by the server id of who cast it, element the element of a
-- threnody. An addon that has parsed the packet already hands the result over in place of the packet:
-- debuffs.Action(action) and debuffs.Message(message), as winxi.packets parses them.
--
-- Each addon is its own Lua state, so each that wants this keeps its own count from the packets it is
-- handed: nothing is shared between addons but the code.
--
-- What it cannot know: a status that landed out of range or before the area was entered, and how
-- long one really lasts when it was partly resisted or lengthened by gear. Each lasts its usual time
-- unless the server says it wore off first. All is forgotten on a change of area. The kinds come
-- from spells alone.
local packets = require('winxi.packets');
local found, durations = pcall(require, 'winxi.debuff_durations');
if not found or type(durations) ~= 'table' then
    durations = {};
end
durations.spells = durations.spells or {};
durations.mobskills = durations.mobskills or {};
durations.statuses = durations.statuses or {};

local debuffs = {};

-- The kinds of debuff kept count of
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
};

-- Action category (4 is a spell finishing) -> spell -> the debuff it leaves, how long for in seconds,
-- the kind it takes the place of, and the messages that mean it took hold
local ActionMap = {
    [  4] = {
        [ 23] = {
            name = 'Dia',
            dur = 60,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = { 2, 264, 252 },
        },
        [ 24] = {
            name = 'Dia II',
            dur = 120,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = { 2, 264, 252 },
        },
        [ 25] = {
            name = 'Dia III',
            dur = 150,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = { 2, 264, 252 },
        },
        [ 33] = {
            name = 'Diaga',
            dur = 60,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = { 2, 264, 252 },
        },
        [ 34] = {
            name = 'Diaga II',
            dur = 120,
            type = StatusType.Dia,
            over = StatusType.Bio,
            msg = { 2, 264, 252 },
        },
        [230] = {
            name = 'Bio',
            dur = 60,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = { 2, 264, 252 },
        },
        [231] = {
            name = 'Bio II',
            dur = 120,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = { 2, 264, 252 },
        },
        [232] = {
            name = 'Bio III',
            dur = 150,
            type = StatusType.Bio,
            over = StatusType.Dia,
            msg = { 2, 264, 252 },
        },
        [ 58] = {
            name = 'Paralyze',
            dur = 120,
            type = StatusType.Paralyze,
            msg = { 236, 277, 268, 271 },
        },
        [ 80] = {
            name = 'Paralyze II',
            dur = 120,
            type = StatusType.Paralyze,
            msg = { 236, 277, 268, 271 },
        },
        [356] = {
            name = 'Paralyzega',
            dur = 120,
            type = StatusType.Paralyze,
            msg = { 236, 277, 268, 271 },
        },
        [341] = {
            name = 'Jubaku: Ichi',
            dur = 180,
            type = StatusType.Paralyze,
            msg = { 237, 267, 278 },
        },
        [342] = {
            name = 'Jubaku: Ni',
            dur = 300,
            type = StatusType.Paralyze,
            msg = { 237, 267, 278 },
        },
        [343] = {
            name = 'Jubaku: San',
            dur = 420,
            type = StatusType.Paralyze,
            msg = { 237, 267, 278 },
        },
        [ 56] = {
            name = 'Slow',
            dur = 180,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [ 79] = {
            name = 'Slow II',
            dur = 180,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [357] = {
            name = 'Slowga',
            dur = 180,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [344] = {
            name = 'Hojo: Ichi',
            dur = 180,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [345] = {
            name = 'Hojo: Ni',
            dur = 300,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [346] = {
            name = 'Hojo: San',
            dur = 420,
            type = StatusType.Slow,
            msg = { 236, 277, 268, 271 },
        },
        [254] = {
            name = 'Blind',
            dur = 180,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [276] = {
            name = 'Blind II',
            dur = 180,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [361] = {
            name = 'Blindga',
            dur = 180,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [347] = {
            name = 'Kurayami: Ichi',
            dur = 180,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [348] = {
            name = 'Kurayami: Ni',
            dur = 300,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [349] = {
            name = 'Kurayami: San',
            dur = 420,
            type = StatusType.Blind,
            msg = { 236, 277, 268, 271 },
        },
        [216] = {
            name = 'Gravity',
            dur = 120,
            type = StatusType.Gravity,
            msg = { 236, 277, 268, 271 },
        },
        [217] = {
            name = 'Gravity II',
            dur = 180,
            type = StatusType.Gravity,
            msg = { 236, 277, 268, 271 },
        },
        [112] = {
            name = 'Flash',
            dur = 12,
            type = StatusType.Flash,
            msg = { 236, 277, 268, 271 },
        },
        [ 59] = {
            name = 'Silence',
            dur = 120,
            type = StatusType.Silence,
            msg = { 236, 277, 268, 271 },
        },
        [359] = {
            name = 'Silencega',
            dur = 120,
            type = StatusType.Silence,
            msg = { 236, 277, 268, 271 },
        },
        [253] = {
            name = 'Sleep',
            dur = 60,
            type = StatusType.Sleep,
            msg = { 236, 277, 268, 271 },
        },
        [259] = {
            name = 'Sleep II',
            dur = 90,
            type = StatusType.Sleep,
            msg = { 236, 277, 268, 271 },
        },
        [273] = {
            name = 'Sleepga',
            dur = 60,
            type = StatusType.Sleep,
            msg = { 236, 277, 268, 271 },
        },
        [274] = {
            name = 'Sleepga II',
            dur = 90,
            type = StatusType.Sleep,
            msg = { 236, 277, 268, 271 },
        },
        [463] = {
            name = 'Foe Lullaby',
            dur = 60,
            type = StatusType.Sleep,
            msg = { 237, 267, 278 },
        },
        [376] = {
            name = 'Horde Lullaby',
            dur = 60,
            type = StatusType.Sleep,
            msg = { 237, 267, 278 },
        },
        [258] = {
            name = 'Bind',
            dur = 60,
            type = StatusType.Bind,
            msg = { 236, 277, 268, 271 },
        },
        [362] = {
            name = 'Bindga',
            dur = 60,
            type = StatusType.Bind,
            msg = { 236, 277, 268, 271 },
        },
        [252] = {
            name = 'Stun',
            dur = 5,
            type = StatusType.Stun,
            msg = { 236, 277, 268, 271 },
        },
        [220] = {
            name = 'Poison',
            dur = 30,
            type = StatusType.Poison,
            msg = { 236, 277, 268, 271 },
        },
        [221] = {
            name = 'Poison II',
            dur = 120,
            type = StatusType.Poison,
            msg = { 236, 277, 268, 271 },
        },
        [225] = {
            name = 'Poisonga',
            dur = 60,
            type = StatusType.Poison,
            msg = { 236, 277, 268, 271 },
        },
        [226] = {
            name = 'Poisonga II',
            dur = 120,
            type = StatusType.Poison,
            msg = { 236, 277, 268, 271 },
        },
        [350] = {
            name = 'Dokumori: Ichi',
            dur = 60,
            type = StatusType.Poison,
            msg = { 237, 267, 278 },
        },
        [351] = {
            name = 'Dokumori: Ni',
            dur = 120,
            type = StatusType.Poison,
            msg = { 237, 267, 278 },
        },
        [352] = {
            name = 'Dokumori: San',
            dur = 360,
            type = StatusType.Poison,
            msg = { 237, 267, 278 },
        },
        [239] = {
            name = 'Shock',
            dur = 120,
            type = StatusType.Shock,
            over = StatusType.Drown,
            msg = { 237, 267, 278 },
        },
        [238] = {
            name = 'Rasp',
            dur = 120,
            type = StatusType.Rasp,
            over = StatusType.Shock,
            msg = { 237, 267, 278 },
        },
        [237] = {
            name = 'Choke',
            dur = 120,
            type = StatusType.Choke,
            over = StatusType.Rasp,
            msg = { 237, 267, 278 },
        },
        [236] = {
            name = 'Frost',
            dur = 120,
            type = StatusType.Frost,
            over = StatusType.Choke,
            msg = { 237, 267, 278 },
        },
        [235] = {
            name = 'Burn',
            dur = 120,
            type = StatusType.Burn,
            over = StatusType.Frost,
            msg = { 237, 267, 278 },
        },
        [240] = {
            name = 'Drown',
            dur = 120,
            type = StatusType.Drown,
            over = StatusType.Burn,
            msg = { 237, 267, 278 },
        },
        [421] = {
            name = 'Battlefield Elegy',
            dur = 150,
            type = StatusType.Elegy,
            msg = { 237, 267, 278 },
        },
        [422] = {
            name = 'Carnage Elegy',
            dur = 250,
            type = StatusType.Elegy,
            msg = { 237, 267, 278 },
        },
        [423] = {
            name = 'Massacre Elegy',
            dur = 350, -- ???
            type = StatusType.Elegy,
            msg = { 237, 267, 278 },
        },
        [368] = {
            name = 'Foe Requiem',
            dur = 100,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [369] = {
            name = 'Foe Requiem II',
            dur = 150,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [370] = {
            name = 'Foe Requiem III',
            dur = 200,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [371] = {
            name = 'Foe Requiem IV',
            dur = 250,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [372] = {
            name = 'Foe Requiem V',
            dur = 300,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [373] = {
            name = 'Foe Requiem VI',
            dur = 350,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [374] = {
            name = 'Foe Requiem VII',
            dur = 400,
            type = StatusType.Requiem,
            msg = { 237, 267, 278 },
        },
        [454] = {
            name = 'Fire Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'fire',
        },
        [455] = {
            name = 'Ice Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'ice',
        },
        [456] = {
            name = 'Wind Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'wind',
        },
        [457] = {
            name = 'Earth Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'earth',
        },
        [458] = {
            name = 'Lightning Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'lightning',
        },
        [459] = {
            name = 'Water Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'water',
        },
        [460] = {
            name = 'Light Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'light',
        },
        [461] = {
            name = 'Dark Threnody',
            dur = 120,
            type = StatusType.Threnody,
            msg = { 237, 267, 278 },
            ele = 'dark',
        },
    },
};

debuffs.Kinds = StatusType;

-- The game's number for the status each kind is, for its icon
debuffs.StatusIds = {
    sleep = 2, poison = 3, para = 4, blind = 5, silence = 6, virus = 8, curse = 9, stun = 10, bind = 11,
    grav = 12, slow = 13, burn = 128, frost = 129, choke = 130, rasp = 131, shock = 132, drown = 133,
    dia = 134, bio = 135, flash = 156, requiem = 192, elegy = 194, threnody = 217,
};

-- Wearing off: the effect the server names in the message, to the kind kept here
local WearsOff = {
    [2] = 'sleep', [19] = 'sleep',
    [3] = 'poison', [540] = 'poison',
    [4] = 'para', [566] = 'para',
    [5] = 'blind',
    [156] = 'flash',
    [6] = 'silence',
    [8] = 'virus',
    [9] = 'curse', [20] = 'curse',
    [10] = 'stun',
    [11] = 'bind',
    [12] = 'grav', [567] = 'grav',
    [13] = 'slow', [565] = 'slow',
    [128] = 'burn',
    [129] = 'frost',
    [130] = 'choke',
    [131] = 'rasp',
    [132] = 'shock',
    [133] = 'drown',
    [134] = 'dia',
    [135] = 'bio',
    [192] = 'requiem',
    [194] = 'elegy',
    [217] = 'threnody',
};

-- The messages that report a death: being defeated, and falling to the ground
local DeathMessages = {
    [  6] = true,
    [ 20] = true,
    [113] = true,
    [406] = true,
    [605] = true,
    [646] = true,
};

local wearsOffMessage = 206;
local zonePacket = 0x00A;

-- enemy's server id -> kind -> { kind, name, expires, by, element }
local tracked = {};

-- anyone's server id -> status -> { id, expires, by, category, param }
local statuses = {};

local DEFAULT_SECONDS = 180; -- a status nothing says the length of
local SPELL, MOVE = 4, 11;   -- the action categories durations are known for: a spell, a monster's move

-- The messages of an action's result that say a status took hold, the status being param: "<target> is
-- <status>", "<target> receives the effect of <status>", "<target> gains the effect of <status>", as
-- each kind of action words it
local Lands = {
    [127] = true, [203] = true, [236] = true, [237] = true, [242] = true, [243] = true, [267] = true,
    [268] = true, [271] = true, [277] = true,
    [186] = true, [205] = true, [230] = true, [319] = true, [320] = true, [375] = true,
};
-- and the same said of an additional effect, the status being its param
local ProcLands = { [160] = true, [164] = true };
-- the messages that say a status is gone from its target, of an action's result or by themselves
local Removes = { [83] = true, [123] = true, [159] = true, [204] = true, [206] = true, [321] = true, [341] = true, [378] = true };
local ProcRemoves = { [168] = true };

local function Seconds(category, param, status)
    local by = (category == SPELL and durations.spells[param]) or (category == MOVE and durations.mobskills[param]) or nil;
    return (by and by[status]) or durations.statuses[status] or DEFAULT_SECONDS;
end

local function Put(target, status, seconds, actor, category, param)
    if status == nil or status <= 0 or status >= 0x400 then
        return;
    end
    local on = statuses[target];
    if on == nil then
        on = {};
        statuses[target] = on;
    end
    on[status] = { id = status, expires = os.time() + seconds, by = actor, category = category, param = param };
end

local function Take(target, status)
    local on = statuses[target];
    if on ~= nil then
        on[status] = nil;
    end
end

local function Landed(messages, message)
    for _, landed in ipairs(messages) do
        if landed == message then
            return true;
        end
    end
    return false;
end

-- A spell has gone off: whichever of its targets it took hold on has the debuff from now
local function Statuses(action)
    for _, target in pairs(action.targets) do
        for _, result in pairs(target.actions) do
            local message = result.message;
            if Lands[message] then
                Put(target.id, result.param, Seconds(action.category, action.param, result.param), action.actor_id, action.category, action.param);
            elseif Removes[message] then
                Take(target.id, result.param);
            end
            local proc = result.proc_message;
            if proc ~= nil then
                if ProcLands[proc] then
                    Put(target.id, result.proc_param, Seconds(nil, nil, result.proc_param), action.actor_id, action.category, action.param);
                elseif ProcRemoves[proc] then
                    Take(target.id, result.proc_param);
                end
            end
        end
    end
end

function debuffs.Action(action)
    Statuses(action);
    local spells = ActionMap[action.category];
    local spell = spells and spells[action.param];
    if spell == nil then
        return;
    end

    local expires = os.time() + spell.dur;
    for _, target in pairs(action.targets) do
        for _, result in pairs(target.actions) do
            if Landed(spell.msg, result.message) then
                local on = tracked[target.id];
                if on == nil then
                    on = {};
                    tracked[target.id] = on;
                end
                on[spell.type] = { kind = spell.type, name = spell.name, expires = expires, by = action.actor_id, element = spell.ele };
                -- by its number as well: Dia and Bio say only the damage they do as they land
                Put(target.id, debuffs.StatusIds[spell.type], spell.dur, action.actor_id, action.category, action.param);
                if spell.over then
                    on[spell.over] = nil;
                    Take(target.id, debuffs.StatusIds[spell.over]);
                end
            end
        end
    end
end

-- An effect has worn off an enemy, or the enemy is no more
function debuffs.Message(message)
    if DeathMessages[message.message] then
        statuses[message.target] = nil;
    elseif Removes[message.message] then
        Take(message.target, message.param);
    end

    local on = tracked[message.target];
    if on == nil then
        return;
    end

    if DeathMessages[message.message] then
        tracked[message.target] = nil;
    elseif message.message == wearsOffMessage then
        local kind = WearsOff[message.param];
        if kind then
            on[kind] = nil;
        end
    end
end

function debuffs.HandlePacket(e)
    if e.id == zonePacket then
        tracked, statuses = {}, {};
    elseif e.id == packets.inbound.action.id then
        debuffs.Action(packets.inbound.action.parse(e.data_raw));
    elseif e.id == packets.inbound.message.id then
        debuffs.Message(packets.inbound.message.parse(e.data));
    end
end

function debuffs.Get(serverId, kind)
    local on = tracked[serverId];
    local entry = on and on[kind];
    if entry and os.time() < entry.expires then
        return entry;
    end
    return nil;
end

function debuffs.Remaining(serverId, kind)
    local entry = debuffs.Get(serverId, kind);
    return entry and (entry.expires - os.time()) or nil;
end

function debuffs.Active(serverId)
    local active = {};
    local now = os.time();
    for _, entry in pairs(tracked[serverId] or {}) do
        if now < entry.expires then
            active[#active + 1] = entry;
        end
    end
    table.sort(active, function(a, b)
        if a.expires ~= b.expires then
            return a.expires < b.expires;
        end
        return a.kind < b.kind;
    end);
    return active;
end

-- What is kept for an enemy, as it is kept: nothing is made or put in order, for whoever asks about
-- many enemies every frame. One that has run out may still be in it: os.time() < entry.expires says.
function debuffs.On(serverId)
    return tracked[serverId];
end

function debuffs.Statuses(serverId)
    return statuses[serverId];
end

function debuffs.StatusRemaining(serverId, status)
    local on = statuses[serverId];
    local entry = on and on[status];
    local now = os.time();
    if entry and now < entry.expires then
        return entry.expires - now;
    end
    return nil;
end

function debuffs.Clear()
    tracked, statuses = {}, {};
end

return debuffs;
