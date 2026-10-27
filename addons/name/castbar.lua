-- Packet-observed casts, keyed by server ID (never by a reusable entity index).
-- Start packets identify the action but do NOT transmit its effective duration.
-- Known base durations are explicitly estimated (~); finishes/interrupts win.
local bit = require('bit');
local castbar = {};
local actors, metadata = {}, { spell = {}, skill = {} };
local count, enabled, skills, skillTimes = 0, false, false, nil;
require('winxi.gamedata').OnChange(function() skillTimes=nil; end); -- another server's data chosen
local MAX_ACTORS, USED_SECONDS = 256, 1.2;
-- Session-only, never part of saved settings or observed actor state.
castbar.Preview = { false };
local previewUntil, previewStart, sampleAt = 0, nil, nil;
local sample = { preview = true };
function castbar.PreviewVisible(now)
    if castbar.Preview[1] then
        previewStart = previewStart or now;
        previewUntil = now + 0.25; -- renew only while this control is being drawn
    else previewUntil, previewStart, sampleAt = 0, nil, nil; end
end
local function preview(now)
    if not castbar.Preview[1] or now > previewUntil or not previewStart then return nil; end
    if sampleAt ~= now then
        sampleAt = now;
        local elapsed = math.max(0, now - previewStart);
        local skill = skills and math.floor(elapsed / 4) % 2 == 1;
        sample.kind = skill and 'skill' or 'spell';
        sample.name = skill and 'Preview: TP move' or 'Preview: Fire IV';
        sample.progress = (elapsed % 4) / 4;
        sample.timer = ('~%.1fs'):format(4 - elapsed % 4);
    end
    return sample;
end

local function remove(id)
    if actors[id] then actors[id]=nil;count=count-1; end
end
local function clearSkills()
    for id,entry in pairs(actors) do if entry.kind=='skill' then remove(id); end end
    metadata.skill={}; skillTimes=nil; 
end
function castbar.Reset()
    castbar.Preview[1] = false;
    previewUntil, previewStart, sampleAt = 0, nil, nil;
    if count>0 then actors={};count=0; end
    if enabled then metadata={spell={},skill={}};skillTimes=nil; end
    enabled,skills=false,false;
end
function castbar.Configure(options)
    local wanted=options.showCastBar and options.showCastBar[1] and (not options.drawNames or options.drawNames[1]);
    if not wanted then castbar.Reset();return false; end
    local withSkills=options.castBarWeaponskills and options.castBarWeaponskills[1] or false;
    if skills and not withSkills then clearSkills(); end
    enabled,skills=true,withSkills;
    return true;
end
function castbar.Begin(options, now)
    if not castbar.Configure(options) then return; end
    for id,entry in pairs(actors) do if now>=entry.expires then remove(id); end end
end
-- A length-bounded string reader: do not dereference packet pointers beyond the
-- received bytes, and do not unpack arbitrary target/result arrays for this UI.
local function read(data, at, width)
    if at+width>#data*8 then return nil; end
    local index,shift=math.floor(at/8)+1,at%8;
    local value,factor=0,1;
    while width>0 do
        local take=math.min(8-shift,width);
        value=value+math.floor(data:byte(index)/2^shift)%2^take*factor;
        factor=factor*2^take; width=width-take; index,shift=index+1,0;
    end
    return value;
end
local function text(value)
    if type(value)~='string' then return nil; end
    value=value:gsub('[%z\1-\31].*',''):gsub('[^\32-\126]','');
    if value=='' then return nil; end
    return #value>64 and value:sub(1,61)..'...' or value;
end
local function action(kind, id)
    local cache=metadata[kind];
    if cache[id] then return cache[id]; end
    local resources=AshitaCore:GetResourceManager();
    local name,duration;
    if kind=='spell' then
        local ok,record=pcall(function() return resources:GetSpellById(id); end);
        if ok and record then
            name=text(record.Name and record.Name[1]);
            local cast=tonumber(record.CastTime);
            if cast then duration=cast/4; end -- Ashita resource units: quarter-seconds
        end
        local ok,record=pcall(function() return require('winxi.spells').Get(id); end);
        if ok and record then
            name=name or text(record.Name);
            duration=record.Data and tonumber(record.Data.castTime) and record.Data.castTime/1000 or duration;
        end
    else
        local ok,value=pcall(function()
            if id>256 then return resources:GetString('monsters.abilities',id-256,2); end
            return resources:GetAbilityById(id).Name[1];
        end);
        if ok then name=text(value); end
        if id>256 then
            skillTimes=skillTimes or require('winxi.gamedata').Read('casttimes','index') or {}; -- the chosen server's casttimes set
            duration=skillTimes[id];
        end
    end
    if type(duration)~='number' or duration~=duration or duration<=0 or duration>120 then duration=nil; end
    local entry={name=name or ((kind=='spell' and 'Spell ' or 'Weaponskill ')..id),duration=duration};
    cache[id]=entry;
    return entry;
end
local function put(id, kind, number, now, mode, sequence)
    if not actors[id] and count>=MAX_ACTORS then
        local oldest,when;
        for key,entry in pairs(actors) do if not when or entry.started<when then oldest,when=key,entry.started; end end
        remove(oldest);
    end
    local info=action(kind,number);
    if not actors[id] then count=count+1; end
    actors[id]={kind=kind,id=number,started=now,name=info.name,duration=info.duration,
        mode=mode,sequence=sequence,expires=now+(mode=='used' and USED_SECONDS or math.min(120,math.max(30,(info.duration or 0)+10)))};
end
function castbar.HandlePacket(e, options)
    if e.id==0x00A then castbar.Reset();return; end
    if not castbar.Configure(options) or e.blocked then return; end
    if e.id==0x00E then
        if type(e.data)=='string' and #e.data>=11 and bit.band(e.data:byte(11),0x20)~=0 then remove(read(e.data,32,32)); end
        return;
    end
    if e.id~=0x028 then return; end
    local data=e.data;
    if type(data)~='string' or #data<19 then return; end
    local actor,category,param=read(data,40,32),read(data,82,4),read(data,86,32);
    if actor==0 then return; end
    local now,known=os.clock(),actors[actor];
    local kind=category==8 and 'spell' or (category==7 and 'skill' or nil);
    if kind then
        if kind=='skill' and not skills then return; end
        if bit.band(param,0xFFFF)==0x7073 then
            if known and known.kind==kind then remove(actor); end
            return;
        end
        if read(data,72,6)==0 or not read(data,182,4) or read(data,182,4)==0 then return; end
        local additional=read(data,271,1);
        if additional==nil then return; end
        local reactiveAt=272+(additional==1 and 37 or 0);
        local reactive=read(data,reactiveAt,1);
        if reactive==nil or (reactive==1 and read(data,reactiveAt+1,34)==nil) then return; end
        local number=read(data,213,17);
        if not number or number==0 or number>65535 then return; end
        local sequence=read(data,16,16);
        if known and known.kind==kind and known.id==number and known.sequence==sequence then return; end
        -- Message zero is still a real start: some moves suppress their chat line.
        put(actor,kind,number,now,'casting',sequence);
    elseif category==4 then
        if known and known.kind=='spell' and known.id==param then remove(actor); end
    elseif (category==3 or category==11) and skills and param>0 and param<=65535 then
        -- Instant player WS have no ready packet. Briefly show the observed name,
        -- never fabricate a charge-up or a pretend remaining-time countdown.
        if not known or (known.kind=='skill' and known.id==param) then
            if known and known.mode=='used' and known.sequence==read(data,16,16) then return; end
            put(actor,'skill',param,now,'used',read(data,16,16));
        end
    end
end
function castbar.Of(name, entities, now, dead)
    if not enabled then return nil; end
    local entry=actors[tonumber(name.ServerId)];
    if not entry then return not dead and preview(now) or nil; end
    if dead or now>=entry.expires or not entities or not entities.GetServerId
            or entities:GetServerId(name.EntityIndex)~=name.ServerId then
        remove(tonumber(name.ServerId));return nil;
    end
    local elapsed=math.max(0,now-entry.started);
    entry.progress=entry.mode=='used' and 1 or (entry.duration and math.min(1,elapsed/entry.duration) or 0);
    local remaining=entry.duration and math.max(0,entry.duration-elapsed) or elapsed;
    local tenth=math.floor(remaining*10+.5);
    local phase=entry.mode=='used' and 'used' or (entry.duration and elapsed>=entry.duration and 'waiting' or 'timed');
    if entry.tenth~=tenth or entry.phase~=phase then
        entry.tenth,entry.phase=tenth,phase;
        entry.timer=phase=='used' and 'Used' or (phase=='waiting' and 'Waiting' or
            (entry.duration and ('~%.1fs'):format(tenth/10) or ('+%.1fs'):format(tenth/10)));
    end
    return entry;
end
function castbar.Diagnostics()
    local now=os.clock();
    for id,entry in pairs(actors) do if now>=entry.expires then remove(id); end end
    return ('%d observed actions; %s%s'):format(count,enabled and 'enabled; base timing estimated' or 'disabled',
        preview(now) and '; preview active (not recorded)' or '');
end
return castbar;
