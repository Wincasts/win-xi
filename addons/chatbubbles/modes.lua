-- The channels a bubble can come by: the game's chat packet modes (player chat, in and out) and the
-- text channels an NPC's words come by. Player packet channels and NPC text-log channels use separate
-- settings keys ('0'..'35', 'npc:150'..). Each entry is a row of the settings' Chat Modes tab: its name,
-- its sentence, and the group (a sub-section) it is read under.
local M = { All = {}, Outgoing = {
    [0] = true, [1] = true, [4] = true, [5] = true, [8] = true,
    [26] = true, [27] = true, [33] = true, [34] = true, [35] = true,
} };
-- The player chat groups, in the order they are read; a mode named in none is Unknown
M.Groups = { 'Chat', 'Without A Speaker', 'System', 'Unknown' };
local named = {
    [0] = { 'Say', 'What is said nearby, by you and others. On to begin with.', 'Chat' },
    [1] = { 'Shout', 'Shouts, heard across the area.', 'Chat' },
    [3] = { 'Tell', 'Private messages sent to you, and yours back.', 'Chat' },
    [4] = { 'Party / Alliance', 'What your party and alliance say.', 'Chat' },
    [5] = { 'Linkshell 1', 'Your first linkshell\'s chat.', 'Chat' },
    [8] = { 'Emote', 'Emotes, done nearby.', 'Chat' },
    [26] = { 'Yell', 'Yells, heard across the whole region.', 'Chat' },
    [27] = { 'Linkshell 2', 'Your second linkshell\'s chat.', 'Chat' },
    [30] = { 'Linkshell 3', 'A third linkshell, kept by the game for later.', 'Chat' },
    [33] = { 'Unity', 'Unity chat.', 'Chat' },
    [34] = { 'Japanese Assist', 'The assist channel, in Japanese.', 'Chat' },
    [35] = { 'English Assist', 'The assist channel, in English.', 'Chat' },
    [13] = { 'Say', 'Say with no one named as speaking.', 'Without A Speaker' },
    [14] = { 'Shout', 'Shout with no one named as speaking.', 'Without A Speaker' },
    [15] = { 'Party', 'Party chat with no one named as speaking.', 'Without A Speaker' },
    [16] = { 'Linkshell 1', 'Linkshell 1 with no one named as speaking.', 'Without A Speaker' },
    [28] = { 'Linkshell 2', 'Linkshell 2 with no one named as speaking.', 'Without A Speaker' },
    [31] = { 'Linkshell 3', 'Linkshell 3 with no one named as speaking.', 'Without A Speaker' },
    [6] = { 'System 1', 'The game\'s first channel of system messages.', 'System' },
    [7] = { 'System 2', 'Its second channel of system messages.', 'System' },
    [29] = { 'System 3', 'Its third channel of system messages.', 'System' },
    [12] = { 'GM Prompt', 'What a game master sends you.', 'System' },
};
for id = 0, 35 do
    local entry = named[id];
    M.All[#M.All + 1] = { id = id, key = tostring(id), default = id == 0,
        label = entry and entry[1] or ('Unknown ' .. id),
        sentence = entry and entry[2] or 'A channel the game is not known to use.',
        group = entry and entry[3] or 'Unknown' };
end
M.Npc = { [142] = true, [144] = true, [150] = true, [151] = true, [152] = true, [210] = true };
local npcNamed = {
    [150] = { 'Dialogue 150', 'What an NPC says to you. On to begin with.' },
    [151] = { 'Dialogue 151', 'More of what an NPC says, by its second channel. On to begin with.' },
    [152] = { 'Prompts And Menus 152', 'NPC lines that carry a prompt or a menu as well.' },
    [142] = { 'System Text 142', 'System lines said by an NPC.' },
    [144] = { 'System Text 144', 'System lines said by an NPC, by its second channel.' },
    [210] = { 'Party And Trust 210', 'What a trust or a party\'s NPC says.' },
};
for _, id in ipairs({ 150, 151, 152, 142, 144, 210 }) do
    local entry = npcNamed[id];
    M.All[#M.All + 1] = { id = id, key = 'npc:' .. id, label = entry[1], sentence = entry[2],
        source = 'text', default = id == 150 or id == 151 };
end
return M;
