package.path = 'addons/zone/?.lua;' .. package.path;
local module = require('boundary_editor');
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; end
local function definitions()
    return {
        [100] = { areas = { { id = 'square', polygon = { { 20, 20 }, { 40, 20 }, { 40, 40 }, { 20, 40 } } } } },
        [103] = { areas = { { id = 'triangle', polygon = { { 80, 80 }, { 100, 80 }, { 90, 100 } } } } },
    };
end
for _, def in pairs(require('data.poc_areas')) do
    for _, area in ipairs(def.areas) do check('default feature is a valid editable polygon: ' .. area.id, module.valid(area.polygon)); end
end
check('reject malformed coordinates', not module.valid({ 1, 2, 3 }));
check('reject bow tie', not module.valid({ { 0, 0 }, { 10, 10 }, { 0, 10 }, { 10, 0 } }));
check('reject collapsed edge', not module.valid({ { 0, 0 }, { 0, 0 }, { 10, 10 } }));
check('reject outside map', not module.valid({ { -1, 0 }, { 10, 0 }, { 10, 10 } }));
local path = os.tmpname(); os.remove(path);
local e = module.new(definitions(), path);
check('missing file retains defaults', e:load() and not e:dirty());
check('select known feature', e:select(100, 'square'));
check('missing vertex cannot drag', not e:begin(12));
check('begin drag', e:begin(1));
check('invalid crossing move rejected', not e:move(45, 30));
check('rejected move unchanged', e.selected.polygon[1][1] == 20);
check('nonfinite move rejected', not e:move(math.huge, 0));
check('drag clamps to map and accepts valid point', e:move(-10, 20) and e.selected.polygon[1][1] == 0);
check('preview does not commit revision', e.revision == 0 and e.preview_revision == 1);
check('saving during drag rejected', not e:save());
check('release commits once', e:finish() and e.revision == 1 and e:dirty());
check('no second commit on extra release', not e:finish());
check('undo is one entire drag', e:undo() and e.selected.polygon[1][1] == 20 and not e:dirty());
e:begin(1); e:move(10, 20); e:cancel();
check('cancel restores prior point', e.selected.polygon[1][1] == 20 and not e:dirty());
e:begin(1); e:move(10, 20); e:finish();
check('restore defaults is undoable', e:restore() and not e:dirty() and e:undo() and e:dirty());
check('explicit save creates override', e:save() and not e:dirty());
local loaded = module.new(definitions(), path);
check('reload persists adjusted vertex', loaded:load() and loaded.definitions[100].areas[1].polygon[1][1] == 10);
check('reload retains unmodified defaults', loaded.definitions[103].areas[1].polygon[1][1] == 80);
local old = e:encode();
e:select(103, 'triangle'); e:begin(1); e:move(75, 80); e:finish();
check('selecting another zone edits independently', e.definitions[100].areas[1].polygon[1][1] == 10);
check('second save succeeds', e:save());
local backup_file = io.open(path .. '.bak', 'r');
check('save creates previous backup', backup_file ~= nil);
if backup_file then backup_file:close(); end
local backup = module.new(definitions(), path .. '.bak');
check('backup has prior valid boundary set', backup:load() and backup.definitions[103].areas[1].polygon[1][1] == 80);
local both = module.new(definitions(), path);
check('reload preserves all zones', both:load() and both.definitions[100].areas[1].polygon[1][1] == 10
    and both.definitions[103].areas[1].polygon[1][1] == 75);
local text = both:encode();
check('invalid version rejected', not both:decode('return os.execute("oops")'));
check('duplicate saved feature rejected', not both:decode(text .. '100 square 10 20 40 20 40 40 20 40\n'));
check('invalid vertex count rejected', not both:decode('zoneinfo-boundaries-v1\n100 square 0 0\n'));
check('invalid saved shape rejected', not both:decode('zoneinfo-boundaries-v1\n100 square 0 0 10 10 0 10 10 0\n'));
check('unknown zone rejected', not both:decode('zoneinfo-boundaries-v1\n999 square 0 0 10 0 10 10 0 10\n'));
check('oversized file rejected', not both:decode(string.rep('x', 65537)));
check('bad file never partially applies', both:encode() == text);
e:select(100, 'square'); e:begin(1); e:move(5, 20); e:finish();
local rename = os.rename;
os.rename = function(from, to)
    if from == path .. '.tmp' then return nil, 'simulated install failure'; end
    return rename(from, to);
end;
local ok = e:save();
os.rename = rename;
check('failed replacement reported and remains dirty', not ok and e:dirty());
local recovered = module.new(definitions(), path);
check('failed replacement restores previous file', recovered:load() and recovered:encode() == text);
check('subsequent successful save works', e:save());
e:restore(); check('default restoration saved', e:save());
local restored = module.new(definitions(), path);
check('reload restores selected default only', restored:load() and restored.definitions[100].areas[1].polygon[1][1] == 20
    and restored.definitions[103].areas[1].polygon[1][1] == 75);
local bad = module.new(definitions(), path .. '/nonexistent/file');
bad:select(100, 'square'); bad:begin(1); bad:move(5, 20); bad:finish();
check('write failure retains unsaved edits', not bad:save() and bad:dirty());
os.remove(path); os.remove(path .. '.bak'); os.remove(path .. '.tmp');
print(('zoneinfo boundary editor: %d assertions passed'):format(checks));
