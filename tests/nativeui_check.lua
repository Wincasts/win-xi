-- nativeui: the skin and the offset of the menus over the chat log given to uihook, once, and again as they change.
local failures = 0
local function check(label, ok) H.print(label, ok and 'true' or 'FALSE'); if not ok then failures = failures + 1 end end
local queued = {}
AshitaCore.GetChatManager = function() return { QueueCommand = function(_, _, text) queued[#queued + 1] = text end } end
local function Sent(text) for _, q in ipairs(queued) do if q == text then return true end end return false end

H.load()
H.frames(1)
check('without uihook: nothing sent', #queued == 0)
H.loaded('uihook', true)
H.frames(1)
check('the skin given', Sent('/uihook skin winxi'))
check('the menus where the game puts them', Sent('/uihook native group off quiet'))
check('the sides where the game puts them', Sent('/uihook native inset 0 quiet'))
local count = #queued
H.frames(3)
check('nothing again while nothing changes', #queued == count)
local options = H.options()
options.offset[1], options.offset[2] = 40, -260
H.frames(1)
check('an offset given as it changes', Sent('/uihook native group 40 -260 quiet'))
options.inset[1] = 100
H.frames(1)
check('the sides brought in as it changes', Sent('/uihook native inset 100 quiet'))
options.skin = 'None'
H.frames(1)
check('no skin: the game\'s own', Sent('/uihook skin off'))
queued = {}
H.loaded('uihook', false); H.frames(1); H.loaded('uihook', true); H.frames(1)
check('uihook loaded again: given it all again', Sent('/uihook skin off') and Sent('/uihook native inset 100 quiet'))
check('the command opens the settings', H.command('/nativeui'))
H.frames(2)
check('the settings drawn', (H.calls['BeginCombo'] or 0) > 0 and (H.calls['DragInt'] or 0) > 0 and (H.calls['SliderInt'] or 0) > 0)
queued = {}
H.unload()
check('unloaded: the menus given back', Sent('/uihook native group off quiet') and Sent('/uihook native inset 0 quiet'))
check('nothing printed', #H.printed == 0)
H.print(failures == 0 and 'nativeui: 0 failures' or ('nativeui: %d failures'):format(failures))
if failures > 0 then os.exit(1) end
