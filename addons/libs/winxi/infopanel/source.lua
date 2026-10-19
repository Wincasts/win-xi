-- Data for a chat-owned panel. Native HUD access is optional and READ-ONLY: it supplies
-- the native map grid when fresh, never gates time/zone/EXP or panel rendering. While the game
-- does not draw its clock (fishing, events, its HUD hidden) the grid is asked of the game's
-- own grid function (winxi.infopanel.grid), so it stays as the time does. Weather also falls back
-- to the game's current weather word, and keeps the last known value while the clock is hidden.
local fields = require('winxi.infopanel.fields')
local exp = require('winxi.infopanel.exp')
local M = {}
local function U16(data,offset)
    if type(data)~='string' or #data<offset+2 then return nil end
    local a,b=data:byte(offset+1,offset+2); return a+b*256
end
function M.New(deps)
    deps=deps or {}
    local time, hud, weather, lastWeather, problem
    local leaving=false
    local function WeatherId(value)
        value=tonumber(value)
        if value and value==value and value>=0 and value<=19 and value%1==0 then return value end
    end
    local source = {}
    function source.Reset()
        time,hud,weather,lastWeather,problem=nil,nil,nil,nil,nil
        leaving=false
        exp.Reset()
    end
    function source.Packet(id,data,format,enabled)
        -- Phoenix/XiPackets: weather at 0x68 in login (0x00A), 0x08 in weather (0x057).
        -- Clear on zone departure even if the panel is currently disabled.
        if id==0x00b then weather,lastWeather,leaving=nil,nil,true
        elseif id==0x00a or id==0x057 then
            if id==0x00a then weather,lastWeather,leaving=nil,nil,false end
            local value=WeatherId(U16(data,id==0x00a and 0x68 or 0x08))
            if value~=nil then weather,lastWeather=value,value end
        end
        if enabled and id==0x02D and fields.Uses(format,'exp') then exp.Packet(id,data) end
    end
    function source.Context(format,now)
        if not time then
            local ok,value=pcall(function() return deps.time or require('ffxi.time') end)
            if not ok then problem='Time unavailable: '..tostring(value); return nil end
            time=value
        end
        local grid, currentWeather
        -- A missing/hidden/disabled clock can omit grid, but never hides the panel.
        pcall(function()
            if not hud then
                local native=deps.native or require('winxi.nativehud')
                hud=native.new(native.Clock)
            end
            grid=hud.Grid()
            currentWeather=hud.Weather()
        end)
        if grid==nil and fields.Has(format,'grid') then
            pcall(function() grid=(deps.grid or require('winxi.infopanel.grid')).Read() end)
        end
        local id
        if not leaving then
            id=WeatherId(weather) or WeatherId(currentWeather)
            if id==nil then
                local ok,value=pcall(function() return (deps.weather or require('winxi.infopanel.weather')).Read() end)
                if ok then id=WeatherId(value) end
            end
            id=id or lastWeather
            lastWeather=id
        end
        local name
        if id and id>0 and fields.Has(format,'weather') then
            local ok,value=pcall(function() return AshitaCore:GetResourceManager():GetString('weather',id) end)
            name=ok and type(value)=='string' and value~='' and value or ('Weather '..id)
        end
        local ok,context=pcall(fields.Context,time,grid,name)
        if not ok then problem='Time unavailable: '..tostring(context); return nil end
        context.weekday=time.get_game_weekday(context.raw)
        context.weatherId=id
        context.exp=fields.Uses(format,'exp') and exp.Snapshot(now,3600) or nil
        problem=nil
        return context
    end
    function source.Status() return problem end
    return source
end
return M
