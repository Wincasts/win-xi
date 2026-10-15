-- Deterministic allocation budgets isolate addon work from the harness's allocating stubs.
local frames, debuffs = require('frames'), require('debuffs')
local imgui = require('imgui')
local tracker = require('winxi.debuffs')
local style = { trimLast = true, scale = 100 }
local count = 1000
local function allocated(fn)
    fn()
    collectgarbage('collect')
    collectgarbage('stop')
    local before = collectgarbage('count')
    for _ = 1, count do fn() end
    local bytes = (collectgarbage('count') - before) * 1024 / count
    collectgarbage('restart')
    return bytes
end
-- Interpreter mode makes these budgets independent of trace escape analysis.
jit.off()
jit.flush()
local geometry = allocated(function() frames.FullSize(6, 'party', style) end)
H.print(('FullSize allocation: %.1f bytes/call'):format(geometry))
local depth = 0
imgui.PushStyleVar = function() depth = depth + 1 end
imgui.PopStyleVar = function() depth = depth - 1 end
imgui.PushStyleColor = function() end
imgui.PopStyleColor = function() end
imgui.Text = function() end
imgui.SameLine = function() end
tracker.Get = function() return nil end
local letters = allocated(function() debuffs.Draw(1) end)
assert(depth == 0, 'debuff style stack unbalanced')
H.print(('Letter-debuff allocation: %.1f bytes/row'):format(letters))
assert(geometry < 8, 'automatic layout must reuse its geometry scratch table')
assert(letters < 8, 'debuff row must reuse spacing vectors and avoid per-row closures')
local reservation = require('geometry')
local cachedGeometry = allocated(function() reservation.Reserve(H.options(), 14, 14, 4, 6) end)
assert(cachedGeometry < 8, 'cached reservation must not allocate')
local statuses = require('statuses')
local ids, filter = { 40, 7, 41, 4, 1 }, { priorityStatuses = '4', hiddenStatuses = '', debuffsFirst = true }
local sorting = allocated(function() statuses.Select(ids, filter) end)
assert(sorting < 8, 'unchanged status filtering must reuse scratch lists')
H.print(('Cached reservation: %.1f bytes/call; status filtering: %.1f bytes/call'):format(cachedGeometry, sorting))
H.print('party geometry, status filtering and letter-debuff allocation budgets', true)
