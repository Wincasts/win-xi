-- The playing of trigger's sounds, which are the wav files of its sounds folder.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.
-- By default events wait for playback to finish. The optional overlap backend uses independent
-- Windows voices instead, with a bounded pool and the same per-event repeat protection.
local shared = require('shared')
local overlap = require('overlap')

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

-- Walk RIFF chunks instead of searching the first 4 KB: custom WAVs may have large metadata
-- chunks, and text or sample bytes containing 'fmt ' or 'data' are not chunk headers.
local function ReadLength(opened)
    local head = opened:read(12)
    if head == nil or #head ~= 12 or head:sub(1, 4) ~= 'RIFF' or head:sub(9, 12) ~= 'WAVE' then
        return usualLength
    end
    local fileSize = opened:seek('end')
    if fileSize == nil then return usualLength end
    local ending = math.min(fileSize, Number(head, 5) + 8)
    local at, rate, size = 12, nil, nil
    while at + 8 <= ending do
        if opened:seek('set', at) == nil then break end
        local chunk = opened:read(8)
        if chunk == nil or #chunk ~= 8 then break end
        local bytes = Number(chunk, 5)
        if at + 8 + bytes > ending then break end
        local kind = chunk:sub(1, 4)
        if kind == 'fmt ' and bytes >= 16 then
            local format = opened:read(16) or ''
            rate = Number(format, 9)
        elseif kind == 'data' then
            size = bytes
        end
        if rate ~= nil and rate > 0 and size ~= nil then
            return size / rate
        end
        at = at + 8 + bytes + bytes % 2 -- RIFF chunks are padded to an even size
    end
    return usualLength
end

local function Length(file)
    local length = lengths[file]
    if length == nil then
        length = usualLength
        local opened = io.open(soundFolder .. file, 'rb')
        if opened ~= nil then
            length = ReadLength(opened)
            opened:close()
        end
        lengths[file] = length
    end
    return length
end

local playingUntil = 0 -- when the sound last started will have finished
local waiting = { }    -- sounds asked for while one was playing, the first asked for first
local waitingFirst, waitingLast = 1, 0 -- queue bounds; avoids shifting the queue on every played sound
local waitAtMost = 3   -- seconds: a sound that has waited longer says nothing worth hearing any more

-- Resolve at playback time so even queued sounds use the current global volume. Keeping
-- variants in subfolders leaves the sound selectors and saved filenames unchanged.
local volumeFolders = { High = 'high\\', Low = 'low\\' }

local overlapMode = false
local warned = {}
local function Warn(reason)
    if not warned[reason] and shared.app then
        warned[reason] = true
        shared.app:Say('Overlap Sounds: ' .. reason)
    end
end

local function SyncMode()
    local options = shared.app and shared.app.options
    local wanted = options and options.overlapSounds and options.overlapSounds[1] == true
    if wanted then
        local available, reason = overlap.Available()
        if not available then
            Warn('unavailable; using the sound queue. ' .. reason)
            wanted = false
        end
    end
    wanted = wanted == true
    if wanted ~= overlapMode then
        overlap.Stop()
        waiting, waitingFirst, waitingLast = {}, 1, 0
        playingUntil = 0
        overlapMode = wanted
    end
    return overlapMode
end

local function PlayFile(file)
    local simultaneous = SyncMode()
    local options = shared.app and shared.app.options
    local folder = options and volumeFolders[options.volume]
    local selected, path = file, nil
    if folder ~= nil then
        local variant = folder .. file
        local variantPath = soundFolder .. variant
        if ashita.fs.exists(variantPath) then
            selected, path = variant, variantPath
        end
    end
    if path == nil then
        path = soundFolder .. file
        if not ashita.fs.exists(path) then
            return false
        end
    end
    if simultaneous then
        local ok, reason = overlap.Play(path)
        if not ok then Warn(reason) end
        -- Do not fall back to interrupting legacy playback on a full pool or bad WAV.
        return ok, reason
    end
    ashita.misc.play_sound(path)
    playingUntil = os.clock() + Length(selected)
    return true
end

-- Starts whatever has been waiting, once the sound before it is over: looked at every frame
local function PlayWaiting(now)
    if SyncMode() then
        overlap.Poll()
        return
    end
    while waitingFirst <= waitingLast and now >= playingUntil do
        local nextUp = waiting[waitingFirst]
        waiting[waitingFirst] = nil
        waitingFirst = waitingFirst + 1
        if waitingFirst > waitingLast then
            waitingFirst, waitingLast = 1, 0
        end
        if now - nextUp.asked <= waitAtMost then
            PlayFile(nextUp.file)
        end
    end
end

-- A sound is wanted, for whatever key stands for: an event's name, or a trigger. At once if nothing
-- is playing, after what is if something is, and not at all if the same was wanted a moment ago.
local function Ask(file, key)
    local simultaneous = SyncMode()
    local now = os.clock()
    if lastPlayed[key] ~= nil and now - lastPlayed[key] < minimumGap then
        return
    end
    lastPlayed[key] = now
    if simultaneous or (now >= playingUntil and waitingFirst > waitingLast) then
        PlayFile(file)
    else
        waitingLast = waitingLast + 1
        waiting[waitingLast] = { file = file, asked = now }
    end
end

-- A sound played to hear it, or word that its file is not there
local function Try(file)
    local ok, reason = PlayFile(file)
    if not ok and reason == nil then
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
    Stop = overlap.Stop,
    folder = soundFolder,
    PlayFile = PlayFile,
    PlayWaiting = PlayWaiting,
    Ask = Ask,
    Try = Try,
    Sound = Sound,
    Renamed = Renamed,
}
