"""phoenix.modules on a made-up server, and the rule that every build script reading the server
goes through modules.guard."""
import io
import re
import tempfile
import unittest
from pathlib import Path

from phoenix import modules

TOOLS = Path(__file__).resolve().parent

# Build scripts that read the server from before phoenix.modules. Each is to be taught its
# overrides and taken off this list; a new build script is never put on it.
NOT_YET_CHECKED = {
    'build_action_data.py': 'reads action overrides its own way',
    'build_item_data.py': 'reads item overrides and module SQL its own way',
    'build_mark_data.py': 'module SQL and YAML through mobdb\'s importer',
    'build_name_vendors.py': 'reads NPC overrides its own way',
    'build_name_placeholders.py': 'mobdb\'s importer',
    'build_name_cast_times.py': 'spell and mob skill cast times',
    'build_winxi_data.py': 'mobdb\'s importer',
    'build_puppet_attachments.py': 'automaton attachments',
    'build_transports.py': 'transport schedules',
    'build_zone_entrances.py': 'zone lines',
    'build_zone_kinds.py': 'zone types',
    'build_zone_weather.py': 'weather tables',
}


def server(files):
    root = Path(tempfile.mkdtemp())
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return root


class ModulesTest(unittest.TestCase):
    def test_gates(self):
        self.assertTrue(modules.gate(''))
        self.assertTrue(modules.gate('xi.pre(xi.expansion.SOA)'))
        self.assertFalse(modules.gate('xi.pre(xi.expansion.TOAU)'))
        self.assertFalse(modules.gate('not xi.pre(xi.expansion.WOTG)'))
        self.assertTrue(modules.gate('xi.pre(xi.expansion.COP) or\n    xi.pre(xi.expansion.ROV)'))
        self.assertIsNone(modules.gate('xi.settings.main.SOMETHING == true'))

    def test_overrides_loaded_gated_and_looped(self):
        root = server({
            'modules/init.txt': '# comment\nlive/\n',
            'modules/live/a.lua': (
                "local m = Module:new('a_module', xi.pre(xi.expansion.SOA))\n"
                "-- m:addOverride('xi.commented.out', function() end)\n"
                "m:addOverride('xi.spells.thing', function(x)\n    return 'a, b'\nend)\n"
                "local old = Module:new('old_module', xi.pre(xi.expansion.COP))\n"
                "old:addOverride('xi.spells.old', function() end)\n"
                "m:addOverrideByEra('xi.actions.mobskills.move.onMobWeaponSkill', {\n"
                "    [xi.expansion.SOA] = function() return 1 end,\n})\n"
                "local rows =\n{\n    { path = 'xi.actions.spells.black.one.onSpellCast', effect = xi.effect.ONE },\n"
                "    { path = 'xi.actions.spells.black.two.onSpellCast', effect = xi.effect.TWO },\n}\n"
                "for _, entry in ipairs(rows) do\n    m:addOverride(entry.path, function() end)\nend\n"
                "m:addOverride(somewhere.else, function() end)\n"),
            'modules/unloaded/b.lua': "local m = Module:new('b_module')\nm:addOverride('xi.spells.unloaded', function() end)\n",
        })
        found = {o.target: o for o in modules.overrides(root)}
        self.assertNotIn('xi.commented.out', found)
        self.assertNotIn('xi.spells.unloaded', found)
        self.assertTrue(found['xi.spells.thing'].applies)
        self.assertEqual(found['xi.spells.thing'].line, 3)
        self.assertFalse(found['xi.spells.old'].applies)
        move = found['xi.actions.mobskills.move.onMobWeaponSkill']
        self.assertTrue(move.applies)
        self.assertEqual([era for era, _ in move.cases()], ['SOA'])
        self.assertEqual(found['xi.actions.spells.black.two.onSpellCast'].row['effect'], 'xi.effect.TWO')
        self.assertIn('?', found)

    def test_guard_stops_on_what_is_not_accounted_for(self):
        root = server({
            'modules/init.txt': 'live\n',
            'modules/live/a.lua': ("local m = Module:new('a_module')\n"
                                   "m:addOverride('xi.spells.known', function() end)\n"
                                   "m:addOverride('xi.spells.new', function() end)\n"
                                   "m:addOverride('xi.zones.elsewhere', function() end)\n"),
        })
        out = io.StringIO()
        with self.assertRaises(SystemExit) as stop:
            modules.guard(root, ('xi.spells.',), lambda o: 'known' if o.target == 'xi.spells.known' else None, out)
        self.assertIn('xi.spells.new', str(stop.exception))
        self.assertNotIn('xi.zones.elsewhere', str(stop.exception))
        done = modules.guard(root, ('xi.spells.',), lambda o: 'seen', out)
        self.assertEqual(sorted(o.target for o, _ in done), ['xi.spells.known', 'xi.spells.new'])

    def test_seconds_and_arguments(self):
        self.assertEqual(modules.seconds('90'), (90, 90))
        self.assertEqual(modules.seconds('math.randomInt(80, 300)'), (80, 300))
        self.assertEqual(modules.seconds('xi.mobskills.calculateDuration(skill:getTP(), 180, 540)'), (180, 540))
        self.assertEqual(modules.seconds('duration', 'local duration = math.random(115, 180)\n'), (115, 180))
        self.assertIsNone(modules.seconds('duration * 2'))
        self.assertEqual(modules.arguments('f(a, g(b, c), { d = 1 }, "x,y")', 1), ['a', 'g(b, c)', '{ d = 1 }', '"x,y"'])
        body = modules.function_body('x = function(a)\n  for i = 1, 2 do\n    if a then end\n  end\n  return a\nend\ntail', 0)
        self.assertTrue(body.endswith('return a\nend'))


class EveryBuildScriptTest(unittest.TestCase):
    def test_build_scripts_that_read_the_server_go_through_the_guard(self):
        """A build script that reads Phoenix calls modules.guard, or is one of those from before it."""
        unguarded = []
        for path in sorted(TOOLS.glob('build_*.py')):
            text = path.read_text()
            if not re.search(r'^\s*from phoenix import|^\s*import phoenix', text, re.M):
                continue
            if 'modules.guard(' in text:
                self.assertNotIn(path.name, NOT_YET_CHECKED, f'{path.name} uses the guard now: take it off NOT_YET_CHECKED')
            elif path.name not in NOT_YET_CHECKED:
                unguarded.append(path.name)
        self.assertEqual(unguarded, [], 'these read the Phoenix server without phoenix.modules.guard: '
                         'have each hand the module overrides of what it reads to a handle function')


if __name__ == '__main__':
    unittest.main()
