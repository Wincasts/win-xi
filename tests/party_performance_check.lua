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
local nativePlacement=require('nativeposition')
local rect={0.5,0.5,0.99,0.99}
local nativeBytes=allocated(function() nativePlacement.Place('party1',rect,1920,1080,300,150,false) end)
assert(nativeBytes<8,'native anchoring must not allocate per window')
local windows,options=require('windows'),H.options()
local automatic=options.automaticPositioning[1]
options.automaticPositioning[1]=false
local ioBefore=H.calls.GetIO or 0
for _=1,100 do windows.UpdatePositions() end
assert((H.calls.GetIO or 0)==ioBefore,'manual layout must not read unused display geometry')
options.automaticPositioning[1]=automatic
H.print(('Native anchoring: %.1f bytes/window; unused manual-layout display reads: 0'):format(nativeBytes))
H.print('party geometry, status filtering and letter-debuff allocation budgets', true)

local target,perf=require('target'),require('perf')
local oldMemory,oldEntity=AshitaCore.GetMemoryManager,perf.Entity
local entityReads,targetReads,subActive=0,0,false
local targets={GetTargetIndex=function(_,slot) return slot==0 and 10 or 11 end,
    GetIsActive=function() return 1 end,GetIsSubTargetActive=function() return subActive and 1 or 0 end}
local memory={GetTarget=function() targetReads=targetReads+1; return targets end}
AshitaCore.GetMemoryManager=function() return memory end
perf.Entity=function(index) entityReads=entityReads+1; return {TargetedIndex=index+2} end
local selected={showMain={true},showSub={false},showTot={false}}
for _=1,1000 do local main,sub,tot=target.Indexes(selected); assert(main==10 and sub==0 and tot==0) end
assert(entityReads==0,'disabled ToT must not look up the main entity just to discard its targeted index')
selected.showTot[1],selected.showMain[1]=true,false
local main,sub,tot=target.Indexes(selected)
assert(main==0 and sub==0 and tot==12 and entityReads==1,'ToT still works with the main target window disabled')
selected.showMain[1],selected.showSub[1],subActive=true,true,true
main,sub,tot=target.Indexes(selected)
assert(main==11 and sub==10 and tot==13,'subtarget stack swaps and main-derived ToT remain intact')
selected.showMain[1],selected.showSub[1],selected.showTot[1]=false,false,false
local before=targetReads
for _=1,100 do main,sub,tot=target.Indexes(selected); assert(main==0 and sub==0 and tot==0) end
assert(targetReads==before,'all target windows disabled skips target-memory polling')
AshitaCore.GetMemoryManager,perf.Entity=oldMemory,oldEntity
H.print('Target polling: no discarded entity lookup with ToT off; no target reads with all windows off; subtarget/ToT semantics preserved',true)
