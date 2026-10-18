H.load()
local o, tracker = H.options(), require('winxi.debuffs')
require('game').StPartyIndex = function() return nil end
require('winxi.game').IsHidden = function() return true end
local function cast()
    tracker.Action({ actor_id = 1, category = 4, param = 23,
        targets = { { id = 900, actions = { { message = 2 } } } } })
    assert(tracker.Get(900, 'dia'))
end
o.target.enabled[1], o.target.showMain[1], o.target.mainDebuffs[1] = true, true, true
H.frames(1)
cast()
o.target.enabled[1] = false
H.frames(1)
assert(not tracker.Get(900, 'dia'), 'disabling tracking must clear history immediately')
for _, packet in ipairs({ 0x00A, 0x00B }) do
    cast()
    H.packet(packet)
    assert(not tracker.Get(900, 'dia'), 'zone clear must run even while target disabled')
end
o.target.enabled[1] = true
H.frames(1)
assert(not tracker.Get(900, 'dia'))
cast()
o.target.showMain[1] = false
H.frames(1)
assert(not tracker.Get(900, 'dia'), 'invisible target must not keep tracking enabled')
o.target.showSub[1], o.target.subDebuffs[1] = true, true
H.frames(1)
cast()
H.resettle()
assert(not tracker.Get(900, 'dia'), 'settings/character switch clears tracker')
H.print('debuff tracking: disable, hidden target, zone-in/out, re-enable and settings lifecycle', true)

local details, imgui = require('details'), require('imgui')
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Effect ' .. id end } end
cast()
local tooltip
local shared = require('winxi.theme').Shared()
shared.TooltipDelay, shared.TooltipsEnabled = 0, true
imgui.SetTooltip = function() error('party details must use Winxi tooltips') end
imgui.Text = function(text) tooltip = text end
details.Status(134, 900)
assert(tooltip:find('Estimated remaining:', 1, true) and tooltip:find('Observed effects only', 1, true))
details.Job({ name = 'Member', jobText = '[WAR30/RDM15]' })
assert(tooltip == '[WAR30/RDM15]', 'basic member hover shows job and level without extra details')
details.Member({ name = 'Pet', owner = 'Owner', jobText = '[WAR99/SAM49]', statusIds = { 4 } })
assert(tooltip:find('Owner: Owner', 1, true) and tooltip:find('Effect 4', 1, true))
tooltip = nil
shared.TooltipsEnabled = false
details.Status(4)
assert(tooltip == nil, 'status tooltips respect shared visibility')
shared.TooltipsEnabled = true
details.Status(4)
assert(tooltip == 'Effect 4 (4)', 'party buffs and debuffs show their name and ID')
o.style.hoverDetails[1], o.clickThrough[1] = true, true
assert(not require('options').Style(o).hoverDetails)
o.clickThrough[1] = false
assert(require('options').Style(o).hoverDetails)
H.print('hover: owner/jobs/status names, estimated durations and clickthrough opt-in', true)

local perf = require('perf')
local now, report = 0, nil
ashita.time.qpf = function() return { q = 1000 } end
ashita.time.qpc = function() return { q = now } end
perf.Start(function(text) report = text end, true)
perf.Packet(function(event) assert(event.id == 1); now = now + 2 end, { id = 1 })
for i = 1, 100 do
    now = now + 49
    perf.Run(function() now = now + 1; perf.Count('entity reads') end)
end
assert(report and report:find('median', 1, true) and report:find('p95', 1, true) and report:find('p99', 1, true))
assert(report:find('render: 100 calls', 1, true) and report:find('packets: 1 calls', 1, true))
assert(report:find('avg 2.000 ms', 1, true) and report:find('entity reads=100', 1, true))
assert(report:find('median 1.000, p95 1.000, p99 1.000', 1, true))
assert(report:find('not exact allocations', 1, true) and report:find('not GPU', 1, true))
local before = now
perf.Run(function() now = now + 1 end)
assert(now == before + 1)
H.print('profiling: CPU percentiles, packet timing, opt-in counters and honest memory estimates', true)
