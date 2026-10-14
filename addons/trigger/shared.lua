-- What the parts of trigger have between them: the app, the events there are, and the making good
-- of a setting.

-- app is winxi.shell's, which holds the settings (app.options): there once trigger.lua has made it
local shared = { app = nil }

-- The events, in the order the settings list them. file is the sound an event starts with: its spoken one.
shared.events = {
    { key = 'tell', group = 'Chat', label = 'Tell Received', file = 'voicef-tell.wav',
      tooltip = 'Someone sends you a tell.' },
    { key = 'mention', group = 'Chat', label = 'Name Mentioned', file = 'voicef-mention.wav',
      tooltip = 'Your name is said in party or linkshell chat.' },
    { key = 'invite', group = 'Chat', label = 'Party Invite', file = 'voicef-invite.wav',
      tooltip = 'You are invited to a party or alliance.' },
    { key = 'trade', group = 'Chat', label = 'Trade Request', file = 'voicef-trade.wav',
      tooltip = 'Someone asks to trade with you.' },
    { key = 'examine', group = 'Chat', label = 'Examined', file = 'voicef-examine.wav',
      tooltip = 'Someone examines you.' },
    { key = 'tp', group = 'Combat', label = 'TP Ready', file = 'voicef-tp.wav',
      tooltip = 'Your TP reaches 1000.' },
    { key = 'lowhp', group = 'Combat', label = 'Low HP', file = 'voicef-lowhp.wav', threshold = 'lowHpPercent', thresholdLabel = 'HP Threshold',
      tooltip = 'Your HP falls to the threshold. Sounds once until it recovers.' },
    { key = 'lowmp', group = 'Combat', label = 'Low MP', file = 'voicef-lowmp.wav', threshold = 'lowMpPercent', thresholdLabel = 'MP Threshold',
      tooltip = 'Your MP falls to the threshold. Sounds once until it recovers.' },
    { key = 'ko', group = 'Combat', label = 'Party Member KO', file = 'voicef-ko.wav',
      tooltip = 'A party member in your area is knocked out.' },
    { key = 'skillup', group = 'Other', label = 'Skill Up', file = 'voicef-skillup.wav',
      tooltip = 'One of your skills, or one of your pet\'s, rises.' },
    { key = 'drop', group = 'Other', label = 'Item Drop', file = 'voicef-drop.wav', items = 'dropItems',
      tooltip = 'An item named below lands in the treasure pool.' },
}

-- A setting kept in a table of one, for imgui to change: made good where it is not there, or holds
-- the wrong kind of thing
local function Boxed(options, key, kind, default)
    local box = options[key]
    if type(box) ~= 'table' or type(box[1]) ~= kind then
        options[key] = T{ default }
    end
end

shared.Boxed = Boxed

return shared
