-- The perf addon: loads, reads after the sample window, marks and resets.
-- luajit tests/harness.lua perf addons/perf/perf.lua tests/perf_check.lua
H.play(true)
-- the harness's performance counter stands still; the addon reads the game's clock through it
ashita.time.qpc = function() return { q = os.clock() } end
H.frames(5)
H.print('window begun:', tostring((H.calls.Begin or 0) > 0))
H.print('nothing to mark before a reading:', tostring((function() H.command('/perf mark'); return H.printed[#H.printed]:find('Nothing to mark') ~= nil end)()))
H.frames(100)    -- 0.03 s a frame in the harness: past the 2 s window
H.print('table drawn:', tostring((H.calls.BeginTable or 0) > 0 and (H.calls.TableHeadersRow or 0) > 0))
H.command('/perf mark before')
H.print('marked with its name:', tostring(H.printed[#H.printed]:find('Marked as before', 1, true) ~= nil))
H.frames(100)
H.print('was and change columns:', tostring((H.calls.TableSetupColumn or 0) >= 9))
H.command('/perf mark clear')
H.print('mark forgotten:', tostring(H.printed[#H.printed]:find('forgotten', 1, true) ~= nil))
H.command('/perf reset')
H.print('longest reset:', tostring(H.printed[#H.printed]:find('start over', 1, true) ~= nil))
H.command('/perf config')
H.frames(2)
H.print('settings drawn:', tostring((H.calls.SliderInt or 0) > 0 and (H.calls.Checkbox or 0) >= 2))
