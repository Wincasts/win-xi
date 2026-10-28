from pathlib import Path
import unittest

from package_release import ROOT, RELEASES, data_sets, plugin_version, stage_notes, staged, winxi_data, winxi_modules


class PluginVersionTests(unittest.TestCase):
    def test_each_released_plugin_has_a_version(self):
        # GetVersion in src/<plugin>.cpp (uihook, lens) or src/Version.h's MAJOR.MINOR (namehook)
        for plugin in ('namehook', 'uihook', 'lens'):
            with self.subTest(plugin=plugin):
                self.assertRegex(plugin_version(plugin), r'^\d+\.\d+$')


class StageTests(unittest.TestCase):
    def test_staged_versions(self):
        self.assertEqual(staged('1.86', None), ('1.86', '1.86'))
        self.assertEqual(staged('1.86-pre1', None), ('1.86-pre1', '1.86'))      # the addon's own stage
        self.assertEqual(staged('0.94', 'rc2'), ('0.94-rc2', '0.94'))           # a plugin's number takes it
        self.assertEqual(staged('2026.10.24', 'pre1'), ('2026.10.24-pre1', '2026.10.24'))
        with self.assertRaises(ValueError):
            staged('1.86-pre1', 'pre2')

    def test_stage_notes(self):
        self.assertEqual(stage_notes('1.86', '1.86', 'name'), '')
        self.assertTrue(stage_notes('1.86-pre1', '1.86', 'name').startswith('**Pre-release pre1 of name 1.86**'))
        self.assertTrue(stage_notes('0.94-rc1', '0.94', 'lens').startswith('**Release candidate rc1 of lens 0.94**'))


class DataSetTests(unittest.TestCase):
    def test_reads_found(self):
        text = '''local kinds = gamedata.Lookup('zonekinds');
local found = require('winxi.gamedata').Read("transports", 'index')
local statuses = require('winxi.catalog').New('statuses');
local skills = catalog.New( 'skills' );
local fileText = file:read('*a');'''
        self.assertEqual(data_sets(text), {'zonekinds', 'transports', 'statuses', 'skills'})

    def test_own_winxi_carries_its_sets(self):
        # every release with its own winxi: each set it reads, from every server's folder, and the list of servers
        for addon, extras in RELEASES.items():
            if not extras.get('private_winxi'):
                continue
            with self.subTest(addon=addon):
                _, paths = winxi_modules(ROOT, addon)
                sets, data = winxi_data(ROOT, addon, paths)
                data = {str(path) for path in data}
                self.assertIn('data/datasets.lua', data)
                servers = [path.parent.name for path in (ROOT / 'addons/libs/winxi/data').glob('*/manifest.lua')]
                self.assertTrue(servers)
                for server in servers:
                    self.assertIn(f'data/{server}/manifest.lua', data)
                for name in sets:
                    self.assertTrue(any(Path(path).name == name for path in data), name)
        _, paths = winxi_modules(ROOT, 'vis')
        self.assertEqual(winxi_data(ROOT, 'vis', paths)[0], ['rules', 'zonekinds'])
        _, paths = winxi_modules(ROOT, 'zone')
        self.assertEqual(winxi_data(ROOT, 'zone', paths)[0], ['entrances', 'regions', 'zonekinds'])


if __name__ == '__main__':
    unittest.main()
