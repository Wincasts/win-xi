-- The playing of twister's sounds, which are the wav files of its sounds folder.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.
-- So that one event's sound is not lost to another's, a sound asked for while one is playing waits
-- for it to finish.
local shared = require('shared')

local events = shared.events

local soundFolder = addon.path .. 'sounds\\'
local minimumGap = 1.0 -- seconds between two soundings of one event: packets come in bursts, and twice over
local lastPlayed = setmetatable({ }, { __mode = 'k' }) -- event key, or trigger -> when: a trigger's goes with the trigger

-- How long a sound lasts, in seconds, read from its file the first time it is wanted: the bytes it
-- plays a second are in its 'fmt ' part, and how many bytes there are of it in its 'data' part
local usualLength = 0.5 -- for a file that cannot be read
local lengths = { }     -- file -> seconds

local function Number(text, at)
    local a, b, c, d = text:byte(at, at + 3)
    if d == nil then
        return nil
    end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function Length(file)
    local length = lengths[file]
    if length == nil then
        length = usualLength
        local opened = io.open(soundFolder .. file, 'rb')
        if opened ~= nil then
            local head = opened:read(4096) or ''
            opened:close()
            local format = head:find('fmt ', 1, true)
            local data = head:find('data', 1, true)
            local rate = format and Number(head, format + 16)
            local size = data and Number(head, data + 4)
            if rate and size and rate > 0 then
                length = size / rate
            end
        end
        lengths[file] = length
    end
    return length
end

local playingUntil = 0 -- when the sound last started will have finished
local waiting = { }    -- sounds asked for while one was playing, the first asked for first
local waitAtMost = 3   -- seconds: a sound that has waited longer says nothing worth hearing any more

local function PlayFile(file)
    local path = soundFolder .. file
    if not ashita.fs.exists(path) then
        return false
    end
    ashita.misc.play_sound(path)
    playingUntil = os.clock() + Length(file)
    return true
end

-- Starts whatever has been waiting, once the sound before it is over: looked at every frame
local function PlayWaiting(now)
    while #waiting > 0 and now >= playingUntil do
        local nextUp = table.remove(waiting, 1)
        if now - nextUp.asked <= waitAtMost then
            PlayFile(nextUp.file)
        end
    end
end

-- A sound is wanted, for whatever key stands for: an event's name, or a trigger. At once if nothing
-- is playing, after what is if something is, and not at all if the same was wanted a moment ago.
local function Ask(file, key)
    local now = os.clock()
    if lastPlayed[key] ~= nil and now - lastPlayed[key] < minimumGap then
        return
    end
    lastPlayed[key] = now
    if now >= playingUntil and #waiting == 0 then
        PlayFile(file)
    else
        waiting[#waiting + 1] = { file = file, asked = now }
    end
end

-- A sound played to hear it, or word that its file is not there
local function Try(file)
    if not PlayFile(file) then
        shared.app:Say(('There is no %s in the sounds folder.'):format(file))
    end
end

-- An event has happened: its sound, if it is switched on
local function Sound(key)
    local chosen = shared.app.options.events[key]
    if chosen.enabled[1] then
        Ask(chosen.sound, key)
    end
end

-- A sound chosen under a name it no longer has: the spoken ones were voice- and are voicef-, and
-- the first tones had only the event's name, tell.wav, and are tone-tell1.wav
local firstTones = { ['trigger.wav'] = 'tone-trigger1.wav' }
for _, event in ipairs(events) do
    firstTones[event.key .. '.wav'] = ('tone-%s1.wav'):format(event.key)
end

local function Renamed(sound)
    return firstTones[sound] or (sound:gsub('^voice%-', 'voicef-'))
end

return {
    folder = soundFolder,
    PlayFile = PlayFile,
    PlayWaiting = PlayWaiting,
    Ask = Ask,
    Try = Try,
    Sound = Sound,
    Renamed = Renamed,
}
