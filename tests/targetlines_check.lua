-- targetlines: the settings window as described rows (winxi 65). /targetlines opens it; every
-- setting is a row with a sentence, the experimental ones tagged, Anchor Height and Anchor Gap under
-- Anchor To Nameplate; a change is staged until Save Settings (or /targetlines save) writes it, and
-- the status line at the foot says so; the text commands save at once as before; no tooltips.
local widgets = require('winxi.widgets')
local imgui = require('imgui')
local config = H.targetlines
local print = H.print

-- every row drawn, with its sentence and spec, and every status line and section
local rows, headers, statuses = {}, {}, {}
local beginRow, header, status = widgets.BeginRow, widgets.Header, widgets.Status
widgets.BeginRow = function(name, sentence, spec)
    rows[#rows + 1] = { name = name, sentence = sentence, spec = spec }
    return beginRow(name, sentence, spec)
end
widgets.Header = function(text, first, dc) headers[#headers + 1] = text return header(text, first, dc) end
widgets.Status = function(text) statuses[#statuses + 1] = text return status(text) end
local function frame()
    rows, headers, statuses = {}, {}, {}
    H.frames(1)
end
local function row(name) for _, r in ipairs(rows) do if r.name == name then return r end end end
local function names() local t = {} for _, r in ipairs(rows) do t[#t + 1] = r.name end return table.concat(t, ', ') end

-- closed to start: nothing drawn
frame()
print('closed: no rows', #rows == 0, 'no window', (H.calls.Begin or 0) == 0)

-- /targetlines opens it
print('command taken', H.command('/targetlines') == true)
frame()
print('window drawn', (H.calls.Begin or 0) >= 1)
print('sections', table.concat(headers, ', '))
print('rows', names())
local expected = 'Filters, Quiet Mode, Persistent Enemy Targets, Show Pet Enmity, Enmity Mode, Enmity Alert Sound, Show Test Line, Opacity, Curve, Orb Size, Anchor To Nameplate, Anchor Height, Anchor Gap, Hide Behind Objects, Player, Enemy, Friendly, Pet, Other, Reset Colours, Save Settings'
print('rows in order', names() == expected)
local allSaid = true
for _, r in ipairs(rows) do if type(r.sentence) ~= 'string' or r.sentence == '' then allSaid = false print('no sentence:', r.name) end end
print('every row has a sentence', allSaid)
local function experimental(name) local r = row(name) return r and r.spec and r.spec.experimental == true end
print('experimental tags', experimental('Enmity Mode') and experimental('Anchor To Nameplate') and experimental('Hide Behind Objects') and not experimental('Quiet Mode'))
print('anchor rows under Anchor To Nameplate, greyed while it is off', row('Anchor Height').spec.parent == false and row('Anchor Gap').spec.parent == false)
print('no tooltips', (H.calls.SetTooltip or 0) == 0 and (H.calls.BeginTooltip or 0) == 0)
print('no radio buttons, no raw labels', (H.calls.RadioButton or 0) == 0)
print('status: saved', statuses[1] == 'Everything here is saved.')

-- a setting changed in the window is staged, not saved, until Save Settings
local saves = H.saves()
local checkbox = imgui.Checkbox
rawset(imgui, 'Checkbox', function(id, box)
    if id == '##quietmode' then box[1] = not box[1] return true end
    return checkbox(id, box)
end)
frame()
rawset(imgui, 'Checkbox', nil)
print('quiet mode staged, not saved', H.options().quietMode == false and H.saves() == saves)
frame()
print('status: unsaved', statuses[1] == 'Unsaved changes. Nothing changed here takes effect until it is saved.', statuses[1])
print('the window shows the staged value', row('Quiet Mode') ~= nil and rows[2].name == 'Quiet Mode')
H.command('/targetlines test on')
frame()
print('status: unsaved, test line on', statuses[1] == 'Unsaved changes. The lines are drawn with them while the test line is on.')
print('preview has the staged value', config.preview().quietMode == true and config.isTesting() == true)
H.command('/targetlines test off')

-- Save Settings applies it
local button = imgui.Button
rawset(imgui, 'Button', function(label) return label == 'Save##save' end)
frame()
rawset(imgui, 'Button', nil)
print('saved by the Save row', H.options().quietMode == true and H.saves() == saves + 1)
frame()
print('status: saved again', statuses[1] == 'Everything here is saved.')

-- Anchor Height and Anchor Gap are live under Anchor To Nameplate
H.command('/targetlines nameplate on')
frame()
print('anchor rows live with the anchor on', row('Anchor Height').spec.parent == true and row('Anchor Gap').spec.parent == true)
print('nameplate saved at once by the command', H.options().nameplateAnchor == true and H.saves() == saves + 2)

-- Reset Colours stages every default
rawset(imgui, 'Button', function(label) return label == 'Reset##resetcolours' end)
frame()
rawset(imgui, 'Button', nil)
frame()
print('reset colours staged', statuses[1]:find('^Unsaved') ~= nil)
H.command('/targetlines save')
print('and saved by the command', H.saves() == saves + 3 and H.options().colors.player[1] == 0)

-- the text commands as before
H.command('/targetlines opacity 50')
print('opacity command', H.options().transparency == 50 and H.saves() == saves + 4)
print('unknown option refused', H.command('/targetlines opacity 5') == true and H.options().transparency == 50)

-- /targetlines closes it
H.command('/targetlines')
local begins = H.calls.Begin
frame()
print('closed again', H.calls.Begin == begins and #rows == 0)
