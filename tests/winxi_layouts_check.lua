-- winxi.layouts against a stand-in install folder: a layout kept and put back, switched by resolution
-- at the start, held for the next start while logged in, and removed.
package.path='addons/libs/?.lua;'..package.path
local root=os.tmpname(); os.remove(root); os.execute('mkdir -p '..root)
local install=root..'/'
local function Real(path) return (path:gsub('\\','/')) end
local realOpen=io.open
io.open=function(path,mode) return realOpen(Real(path),mode) end
local realRemove=os.remove
os.remove=function(path) return realRemove(Real(path)) end
local realLoadfile=loadfile
loadfile=function(path) return realLoadfile(Real(path)) end
local function Exists(path) local ok=os.execute('test -e "'..Real(path)..'"'); return ok==0 or ok==true end
local function Read(path) local f=realOpen(Real(path),'rb'); if not f then return nil end local s=f:read('*a'); f:close(); return s end
local function Write(path,text) os.execute('mkdir -p "'..Real(path):match('^(.*)/')..'"'); local f=realOpen(Real(path),'wb'); f:write(text); f:close() end
ashita={fs={exists=Exists,
    create_directory=function(path) os.execute('mkdir -p "'..Real(path)..'"') end,
    remove_directory=function(path) os.execute('rmdir "'..Real(path)..'" 2>/dev/null') end,
    get_directory=function(path) local out={}; local p=io.popen('ls -1 "'..Real(path)..'" 2>/dev/null'); for line in p:lines() do out[#out+1]=line end p:close(); return out end},
    events={register=function(name,_,fn) if name=='packet_in' then PacketIn=fn end end}}
local loginStatus=0
AshitaCore={GetInstallPath=function() return install end,
    GetMemoryManager=function() return {GetPlayer=function() return {GetLoginStatus=function() return loginStatus end} end} end}
local display={x=2304,y=1296}
package.loaded.imgui={GetIO=function() return {DisplaySize=display} end}
local themeLoads,themeSaves=0,0
package.loaded['winxi.theme']={Load=function() themeLoads=themeLoads+1 end,Save=function() themeSaves=themeSaves+1 end}

local cfg=install..'config\\addons\\'
Write(cfg..'party\\Win_4458\\settings.lua','party at 2304')
Write(cfg..'party\\Task_4459\\settings.lua','task party at 2304')
Write(cfg..'party\\defaults\\settings.lua','defaults')
Write(cfg..'tCrossBar\\Win_4458\\settings.lua','crossbar at 2304')
Write(cfg..'tCrossBar\\Win_4458\\bindings\\WAR.lua','bindings')
Write(cfg..'winxi\\theme.lua','theme at 2304')

local function Fresh()
    package.loaded['winxi.layouts']=nil
    return require('winxi.layouts')
end

-- first start: nothing kept, the resolution remembered
local layouts=Fresh()
assert(layouts.Start()==nil and layouts.Last()=='2304x1296' and layouts.IsAutomatic(),'first start remembers the resolution')
assert(layouts.Start()==nil,'once')

-- kept by hand: settings.lua of every character and the theme, not defaults or other files
assert(layouts.Save('2304x1296')==4,'four files kept')
local kept=cfg..'winxi\\layouts\\2304x1296\\'
assert(Read(kept..'party\\Win_4458\\settings.lua')=='party at 2304' and Read(kept..'party\\Task_4459\\settings.lua')=='task party at 2304')
assert(Read(kept..'theme.lua')=='theme at 2304')
assert(not Exists(kept..'party\\defaults') and not Exists(kept..'tCrossBar\\Win_4458\\bindings'),'defaults and bindings left out')
assert(#layouts.List()==1 and layouts.List()[1]=='2304x1296')

-- the game starts at another resolution: the old one is kept as it was left, nothing for the new yet
Write(cfg..'party\\Win_4458\\settings.lua','party moved at 2304')
display={x=1920,y=1080}
layouts=Fresh()
local said=layouts.Start()
assert(said=='Kept the layout for 2304x1296.' and layouts.Last()=='1920x1080',tostring(said))
assert(Read(kept..'party\\Win_4458\\settings.lua')=='party moved at 2304','latest kept for the old resolution')
assert(Read(cfg..'party\\Win_4458\\settings.lua')=='party moved at 2304','settings left as they are with no layout for the new one')

-- moved for 1920, then back to 2304: 1920 kept, 2304 put in place, the theme loaded again
Write(cfg..'party\\Win_4458\\settings.lua','party at 1920')
Write(cfg..'winxi\\theme.lua','theme at 1920')
display={x=2304,y=1296}
layouts=Fresh()
said=layouts.Start()
assert(said=='Kept the layout for 1920x1080. Using the layout for 2304x1296.',tostring(said))
assert(Read(cfg..'party\\Win_4458\\settings.lua')=='party moved at 2304' and Read(cfg..'winxi\\theme.lua')=='theme at 2304')
assert(Read(cfg..'tCrossBar\\Win_4458\\bindings\\WAR.lua')=='bindings','bindings untouched')
assert(themeLoads==1 and themeSaves==1,'theme loaded and every addon told')
assert(Read(cfg..'winxi\\layouts\\1920x1080\\party\\Win_4458\\settings.lua')=='party at 1920')

-- logged in: Use waits for the next start, which puts it in place even at the same resolution
loginStatus=2
layouts=Fresh()
assert(layouts.IsLoggedIn())
assert(layouts.Use('1920x1080')=='next start' and layouts.Pending()=='1920x1080')
assert(Read(cfg..'party\\Win_4458\\settings.lua')=='party moved at 2304','nothing written while logged in')
loginStatus=0
layouts=Fresh()
assert(layouts.Pending()=='1920x1080','pending kept between starts')
said=layouts.Start()
assert(said=='Using the layout for 1920x1080.' and layouts.Pending()==nil and layouts.Last()=='2304x1296',tostring(said))
assert(Read(cfg..'party\\Win_4458\\settings.lua')=='party at 1920')

-- logging out by the packet allows it at once; entering a zone stops it
layouts=Fresh(); layouts.Start()
PacketIn({id=0x0A,data=string.rep('\0',8)})
assert(layouts.Use('2304x1296')=='next start'); layouts.CancelPending()
PacketIn({id=0x0B,data='\0\0\0\0\1'})
assert(layouts.Use('2304x1296')=='now' and Read(cfg..'party\\Win_4458\\settings.lua')=='party moved at 2304')

-- Automatic off: a new resolution changes nothing
layouts.SetAutomatic(false)
display={x=1920,y=1080}
layouts=Fresh()
assert(not layouts.IsAutomatic() and layouts.Start()==nil and Read(cfg..'party\\Win_4458\\settings.lua')=='party moved at 2304')

-- removed
layouts.Delete('1920x1080')
assert(not Exists(cfg..'winxi\\layouts\\1920x1080') and #layouts.List()==1,'removed')

os.execute('rm -rf '..root)
print('Winxi layouts: kept and put back by resolution, held while logged in, defaults and bindings untouched, removed')
