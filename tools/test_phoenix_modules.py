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
    'build_puppet_attachments.py': 'automaton attachments (another piece of work, not yet committed)',
}

# What a build script reads of the server, and what it must read it through to have it as live does
READS = (
    ('server Lua', r"scripts/|'scripts'|/ 'scripts", r'modules\.(guard|files_on_live)\('),
    ('data YAML', r"data/zones|data/[\w{}/]+\.yaml|'data' /|/ 'data'", r'modules\.load_yaml\(|importer\.generator\(|generator\.load_zone\('),
    ('server SQL', r"sql/|'sql'", r'enabled_files\(|zone_rows\(|zone_ids\(|importer\.generator\('),
)


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
    def test_build_scripts_read_the_server_as_live_does(self):
        """A build script that reads Phoenix's Lua goes through modules.guard, its YAML through
        modules.load_yaml (or the mobdb importer, which patches zones the same way), its SQL with the
        module SQL replayed over it; or it is one of those from before phoenix.modules."""
        missing = []
        for path in sorted(TOOLS.glob('build_*.py')):
            text = path.read_text()
            if not re.search(r'^\s*from phoenix import|^\s*import phoenix', text, re.M):
                continue
            gaps = [what for what, reads, through in READS if re.search(reads, text) and not re.search(through, text)]
            if path.name in NOT_YET_CHECKED:
                self.assertTrue(gaps, f'{path.name} reads the server as live does now: take it off NOT_YET_CHECKED')
            elif gaps:
                missing.append(f'{path.name}: {", ".join(gaps)}')
        self.assertEqual(missing, [], 'these read the Phoenix server without its modules')

    def test_mobdb_importer_patches_zones_from_the_same_folders(self):
        """The importer finds its zone overlays its own way; on live they are the data roots'."""
        from phoenix import importer
        cache = TOOLS.parent / '.cache/phoenix-live'
        if not (cache / 'modules/init.txt').is_file():
            self.skipTest('no fetched server')
        generator = importer.generator(cache, tempfile.mkdtemp())
        # it also counts module Lua folders named zones, which hold no YAML to patch with
        theirs = sorted(Path(p).resolve() for p in generator.zone_overlay_dirs if any(Path(p).rglob('*.yaml')))
        ours = sorted((root / 'zones').resolve() for root in modules.data_roots(cache) if (root / 'zones').is_dir())
        self.assertEqual(theirs, ours)


if __name__ == '__main__':
    unittest.main()
