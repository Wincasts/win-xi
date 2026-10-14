addon.name = 'menurect';
addon.author = 'win';
addon.version = '0.1';
addon.desc = 'Read-only native menu rectangle discovery (unverified candidates).';
require('common');
local imgui = require('imgui');
local probe = require('probe');
local enabled, memory, failure, signature = false, nil, nil, nil;
local menu, candidates, sources, rectangle = nil, {}, {}, nil;
local selected, scale, offset = { 1 }, { 1 }, { 0, 0 };
local preview = { false };
local expected = { 0, 0, 300, 200 };
local nextPoll = 0;
local lastDump = '';
local function say(message) print(('[menurect] %s'):format(message)); end
local function screen()
    local size = imgui.GetIO().DisplaySize;
    return size.x or size[1], size.y or size[2];
end
local function slot()
    local at = AshitaCore:GetPointerManager():Get('menu');
    if at and at ~= 0 then return at; end
    if signature == nil then
        signature = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0) or 0;
    end
    if signature == 0 then return 0; end
    -- The signature operand contains the address of the global slot, not the node itself.
    local bytes = memory.read(signature, 4);
    if not bytes then return 0; end
    local a,b,c,d = bytes:byte(1,4);
    return a+b*256+c*65536+d*16777216;
end
local function rescan(current)
    menu = current;
    rectangle, candidates, sources = nil, {}, {};
    selected[1], preview[1] = 1, false;
    if menu then
        local w,h = screen();
        candidates, sources = probe.scan(memory, menu, w, h);
    end
end
local function poll(force)
    if not memory then return; end
    if not force and os.clock() < nextPoll then return; end
    nextPoll = os.clock() + 0.1;
    local current, err = probe.resolve(memory, slot());
    failure = err;
    if force or (current and not menu) or (menu and not current)
        or (current and menu and (current.node ~= menu.node or current.header ~= menu.header
            or current.name ~= menu.name)) then
        rescan(current);
    end
    rectangle = nil;
    if menu and candidates[selected[1]] then
        local w,h = screen();
        rectangle = probe.live(memory, current, candidates[selected[1]], w, h);
    end
end
local function dump()
    if not menu then say('No readable menu to capture.'); return; end
    local path = addon.path .. 'menu-rect-probe.txt';
    local file, err = io.open(path, 'w');
    if not file then say('Capture failed: ' .. tostring(err)); return; end
    local w,h = screen();
    file:write(('UNVERIFIED native menu rectangle hypotheses\nMenu: %s\nSlot %08X holder %08X node %08X header %08X\nDisplay %.0fx%.0f\n'):format(
        menu.name, menu.slot, menu.holder, menu.node, menu.header, w, h));
    file:write(('Preview index %d scale %.3f offset %d,%d (not a verified UI transform)\n'):format(selected[1], scale[1], offset[1], offset[2]));
    if rectangle then file:write(('Selected live L/T/R/B: %.3f %.3f %.3f %.3f\n'):format(unpack(rectangle))); end
    for i,c in ipairs(candidates) do
        file:write(('%d %s : %.3f %.3f %.3f %.3f\n'):format(i,c.label,unpack(c.rect)));
    end
    for _,s in ipairs(sources) do
        file:write(('\n%s %08X (scan snapshot)\n'):format(s.label,s.address));
        for i=0,#s.bytes-1,16 do
            local hex = {};
            for j=i+1,math.min(i+16,#s.bytes) do hex[#hex+1]=('%02X'):format(s.bytes:byte(j)); end
            file:write(('%02X: %s\n'):format(i,table.concat(hex,' ')));
        end
    end
    file:close(); lastDump = path; say('Capture saved to ' .. path .. ' (overwrites previous capture).');
end
local function draw()
    imgui.SetNextWindowSize({ 590, 390 }, ImGuiCond_FirstUseEver);
    local open = { enabled };
    if imgui.Begin('Native menu rectangle probe', open, ImGuiWindowFlags_NoSavedSettings) then
        imgui.TextWrapped('Read-only discovery: rectangles below are guesses, not verified menu bounds. No clipping, controller capture or game memory writes.');
        if failure then imgui.TextWrapped(failure); end
        if menu then
            imgui.Text(('Focused: %s'):format(menu.name));
            imgui.Text(('node %08X / header %08X'):format(menu.node,menu.header));
            imgui.Text(('%d candidates from %d readable blocks (one hop, 256 bytes each)'):format(#candidates,#sources));
        end
        if imgui.Button('Rescan') then poll(true); end
        imgui.SameLine(); if imgui.Button('Capture snapshot') then dump(); end
        if #candidates > 0 then
            if imgui.InputInt('Candidate', selected) then
                selected[1] = math.max(1,math.min(#candidates,selected[1])); nextPoll=0; rectangle=nil;
            end
            if imgui.Button('Previous') then selected[1] = math.max(1,selected[1]-1); nextPoll=0; rectangle=nil; end
            imgui.SameLine(); if imgui.Button('Next') then selected[1] = math.min(#candidates,selected[1]+1); nextPoll=0; rectangle=nil; end
            imgui.Checkbox('Overlay selected candidate (unverified)', preview);
            imgui.SliderFloat('Preview scale', scale, 0.25, 4);
            imgui.InputInt2('Preview offset', offset);
            imgui.InputInt4('Approximate screen L/T/R/B', expected);
            if imgui.Button('Find closest snapshot candidate') then
                local best, distance = 1, math.huge;
                for i,item in ipairs(candidates) do
                    local score = 0;
                    for edge=1,4 do
                        local shift = offset[edge % 2 == 1 and 1 or 2];
                        score = score + math.abs(item.rect[edge]*scale[1]+shift-expected[edge]);
                    end
                    if score < distance then best, distance = i, score; end
                end
                selected[1], nextPoll, rectangle = best, 0, nil;
            end
            local c = candidates[selected[1]];
            imgui.Text(c.label);
            if rectangle then
                imgui.Text(('Live L/T/R/B: %.1f / %.1f / %.1f / %.1f'):format(unpack(rectangle)));
            else imgui.Text('Candidate invalid or child replaced; rescan required.'); end
            for i=math.max(1,selected[1]-2),math.min(#candidates,selected[1]+2) do
                local item=candidates[i];
                imgui.Text(('%d: %s [%.0f, %.0f, %.0f, %.0f]'):format(i,item.label,unpack(item.rect)));
            end
        end
        if lastDump ~= '' then imgui.TextWrapped('Last capture: ' .. lastDump); end
    end
    imgui.End(); enabled = open[1];
    if enabled and preview[1] and rectangle then
        local r=rectangle;
        local a={r[1]*scale[1]+offset[1],r[2]*scale[1]+offset[2]};
        local b={r[3]*scale[1]+offset[1],r[4]*scale[1]+offset[2]};
        local list=imgui.GetForegroundDrawList();
        local color=imgui.GetColorU32({1,0.7,0,1});
        list:AddRect(a,b,color,0,0,2);
        list:AddText({a[1],math.max(0,a[2]-18)},color,'UNVERIFIED native menu candidate');
    end
end
ashita.events.register('command', 'menurect_command', function(e)
    local args={}; for word in tostring(e.command):gmatch('%S+') do args[#args+1]=word:lower(); end
    if args[1] ~= '/menurect' then return; end
    e.blocked=true;
    if args[2] and args[2] ~= 'off' then say('Use /menurect to toggle the probe, or /menurect off.'); return; end
    enabled = args[2] ~= 'off' and not enabled;
    if enabled and not memory then
        local ok,result=pcall(require,'winxi.safe_memory');
        if not ok then enabled=false; say('Guarded memory reads unavailable: '..tostring(result)); return; end
        memory=result;
    end
    if enabled then nextPoll=0; poll(true); else preview[1]=false; rectangle=nil; end
end);
ashita.events.register('d3d_present', 'menurect_present', function()
    if not enabled then return; end
    poll(false); draw();
end);
