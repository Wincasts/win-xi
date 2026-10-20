-- winxi.shell as the character logs out: Ashita's settings library gives every addon the defaults
-- then, in which the window is open, and the addon runs on for half a second as the game shuts down.
-- The shell draws nothing from the logout until a character's settings come, so that a window kept
-- closed does not show over the black screen. Run with atlas, a shell addon whose window is open to
-- begin with.
local settings = require('settings')
local o = H.options()
H.play(true); H.frames(2)
local begun = H.calls.Begin or 0
H.frames(1)
H.print('in the world, the window is drawn each frame', (H.calls.Begin or 0) > begun)
o.isVisible[1] = false; H.frames(1)
begun = H.calls.Begin or 0
H.frames(1)
H.print('closed by its switch: not drawn', (H.calls.Begin or 0) == begun)

-- the logout: the settings library loads the defaults (the window open) and says so
settings.logged_in = false
local defaults = H.options()
defaults.isVisible[1] = true
H.resettle()
H.play(false)
begun = H.calls.Begin or 0
H.frames(3)
H.print('logged out, the defaults open: nothing drawn', (H.calls.Begin or 0) == begun)
H.command('/atlas config'); H.frames(1)
H.print('the settings window neither', (H.calls.Begin or 0) == begun)

-- a character logs in: their settings come, and the window is drawn again
settings.logged_in = true
H.resettle()
H.play(true)
begun = H.calls.Begin or 0
H.frames(1)
H.print('logged in again: drawn', (H.calls.Begin or 0) > begun)
