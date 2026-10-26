local ffi=require('ffi')
local diag,plates,custom=require('diag'),require('winxi.nameplates'),require('custom')
local options=H.options()
local hook=ffi.new('namehook_t')
hook.Hooked,hook.Count,hook.TargetWidth,hook.TargetHeight=1,1,1920,1080
ffi.copy(hook.Names[0].Name,'SecretCharacter')
plates.Hook=function() return hook end
local caps=dofile('tests/fixtures/namehook_capabilities.lua')
ashita.memory.find=function() return tonumber(ffi.cast('uintptr_t',ffi.cast('void*',caps))) end
local playerdat=require('playerdat')
playerdat.Load=function() return nil,'C:\\Users\\SecretUser\\SecretCharacter\\bad.dat' end
require('icons').Begin(function() return 0x1234 end,'game')
options.nameFormat[1]='[name] SecretCharacter'
options.font='C:\\Users\\SecretUser\\font.ttf'
options.trackedNm[1]='SecretMonster'
diag.Options,diag.Runtime=options,custom.Diagnostics
local initial=diag.ReportText()
assert(not diag.Enabled() and initial:find('recording: off',1,true),'reports do not require recording')
diag.Enable(true)
diag.Note('SecretChat in history')
diag.Error('SecretCharacter raw error','C:\\Users\\SecretUser traceback SecretChat')
diag.Error('SecretCharacter raw error','SecretChat')
diag.Frame('texture');diag.Frame('texture');diag.Frame(nil)
local text=diag.ReportText()
for _,secret in ipairs({'SecretCharacter','SecretUser','SecretChat','SecretMonster','C:\\Users','traceback','[name]'}) do
    assert(not text:find(secret,1,true),'privacy leak: '..secret)
end
for _,expected in ipairs({'Name '..addon.version,'WinXI','55','1.35','API 1; mask 0x7','Filtered font','Letter badge atlas',
    'bundled fallback','source failure (details omitted)','Lua errors recorded: 2','texture: 1 brief'}) do
    assert(text:find(expected,1,true),'missing fact: '..expected)
end
local originalOpen=io.open
local files={}
io.open=function(path,mode)
    assert(mode=='w' and path:find('\\logs\\name-report-',1,true),'only explicitly requested reports may be written')
    local f={path=path,body=''};files[#files+1]=f
    f.write=function(self,value) self.body=self.body..value;return self end
    f.close=function() return true end
    return f
end
local path=assert(diag.Report())
assert(path==diag.LastReportPath() and files[1].body==text)
local second=assert(diag.Report());assert(second~=path,'repeat clicks must not overwrite a same-second report')
options.drawNames[1]=false
H.command('/name report')
assert(#files==3 and files[3].body:find('disabled',1,true),'report command works with Name off')
io.open=function() return nil,'denied' end
local failed,why=diag.Report()
assert(not failed and why:find('denied',1,true) and diag.LastReportPath()==files[3].path)
io.open=function(path,mode)
    return {write=function() return nil,'disk full' end,close=function() return true end}
end
failed,why=diag.Report();assert(not failed and why:find('disk full',1,true))
local closed=false
io.open=function() return {write=function() error('write exception') end,close=function() closed=true;return true end} end
failed,why=diag.Report();assert(not failed and closed and why:find('write exception',1,true),'exceptions still close the file')
-- Reader/provider failures must not leak exception contents into shareable text.
diag.Runtime=function() error('SecretUser runtime traceback') end
plates.Hook=function() error('SecretCharacter hook failure') end
text=diag.ReportText()
assert(text:find('unavailable',1,true) and not text:find('Secret',1,true))
io.open=originalOpen
H.print('Support report: versions/capabilities, resource/fallback facts, counts, recording off, privacy, unavailable readers, unique files and write failures passed',true)
