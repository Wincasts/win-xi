-- Optional presentation policies. Never move plates or suppress the name itself.
local bit = require('bit');
local plates = require('winxi.nameplates');
local readability = {};
local active, pending, pendingAt, count = false, nil, nil, 0;
local rangeEnabled, epoch = false, 0;
local compact = setmetatable({}, { __mode = 'k' });
local specs = {
    { 'crowdDeclutter', false }, { 'crowdThreshold', 20, 4, 200 }, { 'crowdHold', 750, 250, 3000 },
    { 'distanceColours', false }, { 'distanceWarning', 20, 1, 100 },
    { 'distanceDanger', 25, 1, 100 }, { 'distanceHysteresis', 1, 0, 10 },
};
local colors = { distanceWarningColor = {1, .8, .2, 1}, distanceDangerColor = {1, .25, .2, 1} };
function readability.Defaults(options)
    for _, spec in ipairs(specs) do options[spec[1]] = T{spec[2]}; end
    for key, color in pairs(colors) do options[key] = T{unpack(color)}; end
end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge; end
function readability.Settle(options)
    for _, spec in ipairs(specs) do
        local value = options[spec[1]];
        if type(value)~='table' or type(value[1])~=type(spec[2]) or (spec[3] and not finite(value[1])) then
            value=T{spec[2]}; options[spec[1]]=value;
        end
        if spec[3] then value[1]=math.max(spec[3],math.min(spec[4],math.floor(value[1]))); end
    end
    options.distanceDanger[1]=math.max(options.distanceWarning[1],options.distanceDanger[1]);
    options.distanceHysteresis[1]=math.min(options.distanceHysteresis[1],options.distanceWarning[1]-1);
    for key, color in pairs(colors) do
        if type(options[key])~='table' then options[key]=T{unpack(color)}; end
        for i=1,3 do
            local n=options[key][i]; options[key][i]=finite(n) and math.max(0,math.min(1,n)) or color[i];
        end
        options[key][4]=1;
    end
end
function readability.Reset()
    active,pending,pendingAt,count=false,nil,nil,0;
    epoch=epoch+1;
    compact=setmetatable({}, {__mode='k'});
end
-- Count wanted, non-faded anchors inside the actual output, not merely in front
-- of the camera. No screen projection pass at all while the feature is off.
function readability.Begin(options, hook, now)
    if rangeEnabled~=options.distanceColours[1] then rangeEnabled=options.distanceColours[1];epoch=epoch+1; end
    if not options.crowdDeclutter[1] then active,pending,pendingAt,count=false,nil,nil,0; return; end
    local display=require('imgui').GetIO().DisplaySize;
    count=0;
    for i=0,hook.Count-1 do
        local name=hook.Names[i];
        if bit.band(name.Flags,plates.Flag.Wanted)~=0 and name.Scale>0 and bit.rshift(name.NameColor,24)>0 then
            local x,y=plates.Screen(name,hook);
            if x and y and x>=0 and x<=display.x and y>=0 and y<=display.y then count=count+1; end
        end
    end
    local wanted=count>=options.crowdThreshold[1];
    if active then wanted=count>math.max(0,options.crowdThreshold[1]-3); end
    if wanted==active then pending,pendingAt=nil,nil;
    elseif pending~=wanted then pending,pendingAt=wanted,now;
    elseif now-pendingAt>=options.crowdHold[1]/1000 then active,pending,pendingAt=wanted,nil,nil; end
end
local protected=bit.bor(plates.Category.Self,plates.Category.Party,plates.Category.Alliance,plates.Category.MyPet);
function readability.Simplify(name, subtarget, hunted)
    return active and not subtarget and not hunted and bit.band(name.Category,protected)==0
        and bit.band(name.Flags,bit.bor(plates.Flag.Target,plates.Flag.Whitelisted,plates.Flag.Charmed))==0;
end
-- Keep core identification/danger cues and their explicit colours/rules. Strip
-- surrounding punctuation with the removed details, rather than leaving '( y)'.
function readability.Compact(parts)
    if compact[parts]~=nil then return compact[parts] or parts; end
    local result,hasName={},false;
    for _,part in ipairs(parts) do
        if part.kind=='name' or part.kind=='letter' or part.kind=='aggro' then
            if #result>0 and not (result[#result].space and result[#result].space>0) then result[#result+1]={kind='text',text=' '}; end
            result[#result+1]=part;
            hasName=hasName or part.kind=='name';
            result[part.kind]=true;
            result.rules=result.rules or part.when~=nil or part.within~=nil;
            result.ruleDistance=result.ruleDistance or part.within~=nil;
        end
    end
    -- A deliberately name-less format must not acquire an invented name.
    if not hasName then compact[parts]=false; return parts; end
    compact[parts]=result;
    return result;
end
local function rgb(c) return 0xFF000000+math.floor(c[1]*255+.5)*65536+math.floor(c[2]*255+.5)*256+math.floor(c[3]*255+.5); end
-- Entry at the configured threshold; exit only below threshold minus hysteresis.
-- State lives with an existing bounded per-entity cache, and is identity/config keyed.
function readability.Distance(options, written, identity)
    local distance=written.distanceValue;
    if not options.distanceColours[1] or not finite(distance) or distance<0 then written.distanceBand=nil; return nil; end
    local warning,danger,h=options.distanceWarning[1],options.distanceDanger[1],options.distanceHysteresis[1];
    local band=written.distanceBand;
    if written.distanceEpoch~=epoch or written.distanceIdentity~=identity or written.distanceWarning~=warning or written.distanceDanger~=danger or written.distanceHysteresis~=h then band=nil; end
    if band==nil then band=distance>=danger and 2 or (distance>=warning and 1 or 0);
    elseif distance>=danger then band=2;
    elseif band==2 and distance>=math.max(0,danger-h) then band=2;
    elseif distance>=warning or (band>0 and distance>=math.max(0,warning-h)) then band=1;
    else band=0; end
    written.distanceBand,written.distanceIdentity,written.distanceEpoch=band,identity,epoch;
    written.distanceWarning,written.distanceDanger,written.distanceHysteresis=warning,danger,h;
    return band==2 and rgb(options.distanceDangerColor) or (band==1 and rgb(options.distanceWarningColor) or nil);
end
function readability.Diagnostics() return ('%d on-screen anchors; decluttering %s'):format(count,active and 'active' or 'inactive'); end
-- Crowd Decluttering, at the bottom of the Visibility tab
function readability.DrawCrowd(options)
    local controls, tips = require('controls'), require('winxi.tips');
    local imgui = require('imgui');
    if controls.Section('Crowd Decluttering', '##name.crowdOptions') then
        controls.Checkbox('Enabled', '##name.crowdDeclutter', options.crowdDeclutter, tips.Get('name.readability.crowd'));
        imgui.BeginDisabled(not options.crowdDeclutter[1]);
        controls.Input('Crowd Threshold (names)', '##name.crowdThreshold', options.crowdThreshold, 4, 200, tips.Get('name.readability.crowd_threshold'));
        controls.Slider('Hold Time (ms)', '##name.crowdHold', options.crowdHold, 250, 3000, '%d ms', tips.Get('name.readability.crowd_hold'));
        imgui.EndDisabled();
    end
    controls.EndSection();
end
-- Distance Thresholds, in the Names tab
function readability.DrawDistance(options)
    local controls, tips = require('controls'), require('winxi.tips');
    local imgui, widgets = require('imgui'), require('winxi.widgets');
    if controls.Section('Distance Thresholds', '##name.distanceOptions') then
        controls.Checkbox('Distance Colours', '##name.distanceColours', options.distanceColours, tips.Get('name.readability.distance'));
        imgui.BeginDisabled(not options.distanceColours[1]);
        if controls.Input('Warning Distance (y)', '##name.distanceWarning', options.distanceWarning, 1, 100, tips.Get('name.readability.distance_warning')) then
            options.distanceDanger[1]=math.max(options.distanceDanger[1],options.distanceWarning[1]);
        end
        controls.Input('Danger Distance (y)', '##name.distanceDanger', options.distanceDanger, options.distanceWarning[1], 100, tips.Get('name.readability.distance_danger'));
        controls.Input('Exit Margin (y)', '##name.distanceHysteresis', options.distanceHysteresis, 0, math.min(10,options.distanceWarning[1]-1), tips.Get('name.readability.distance_hysteresis'));
        for _,entry in ipairs({{'Warning Colour','distanceWarningColor'},{'Danger Colour','distanceDangerColor'}}) do
            widgets.Label(entry[1]);controls.Width();
            imgui.ColorEdit4('##name.'..entry[2],options[entry[2]],ImGuiColorEditFlags_NoAlpha or 0);
            controls.Mark(tips.Get('name.readability.distance_colors'));
        end
        imgui.EndDisabled();
    end
    controls.EndSection();
end
return readability;
