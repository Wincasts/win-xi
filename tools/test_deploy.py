"""Deploy regression checks. Every live write is confined to a temporary sandbox."""
import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('rsync'), 'deploy.sh needs rsync')
class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'
        self.live = self.root / 'live'
        self.project.mkdir()
        (self.live / 'addons').mkdir(parents=True)
        shutil.copy2(ROOT / 'deploy.sh', self.project / 'deploy.sh')
        self.env = dict(os.environ, ASHITA_LIVE=str(self.live),
                        DEPLOY_BACKUPS=str(self.root / 'backups'))
        self.put(self.project / 'addons/name/name.lua', 'new name')
        self.put(self.project / 'addons/libs/winxi/version.lua', 'new library')
        self.put(self.live / 'addons/libs/winxi/version.lua', 'new library')
        self.put(self.project / 'plugins/namehook/build/namehook.dll', b'\x00new plugin')
        self.put(self.project / 'plugins/namehook/build/not-for-live.obj', 'object')

    @staticmethod
    def put(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode() if isinstance(content, str) else content)

    def run_deploy(self, *args, terminal=True, answer=None):
        # Never point the real deployment script at a real Ashita installation.
        assert self.live.is_relative_to(self.root)
        command = ['bash', str(self.project / 'deploy.sh'), *args]
        master, slave = pty.openpty() if terminal else (None, subprocess.DEVNULL)
        try:
            proc = subprocess.Popen(command, stdin=slave, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, env=self.env)
            if terminal:
                os.close(slave)
            if answer is not None:
                os.write(master, (answer + '\n').encode())
            output = proc.communicate(timeout=15)[0].decode()
            return proc.returncode, output
        finally:
            if master is not None:
                os.close(master)

    def test_named_push_includes_plugin_and_keeps_separate_backups(self):
        self.put(self.live / 'addons/name/name.lua', 'old name')
        self.put(self.live / 'plugins/namehook.dll', b'\x00old plugin')
        self.put(self.live / 'plugins/other.dll', b'unrelated')
        self.put(self.live / 'addons/libs/winxi/version.lua', 'old library')
        code, output = self.run_deploy('-y', 'push', 'name')
        self.assertEqual(code, 0, output)
        self.assertLess(output.index('Pushed plugins/namehook'), output.index('Pushed name.'))
        self.assertEqual((self.live / 'plugins/namehook.dll').read_bytes(), b'\x00new plugin')
        self.assertEqual((self.live / 'addons/name/name.lua').read_text(), 'new name')
        self.assertEqual((self.live / 'plugins/other.dll').read_bytes(), b'unrelated')
        self.assertLess(output.index('Pushed libs/winxi'), output.index('Pushed plugins/namehook'))
        self.assertEqual((self.live / 'addons/libs/winxi/version.lua').read_text(), 'new library')
        library_backups = list((self.root / 'backups/libs/winxi').glob('*/version.lua'))
        self.assertEqual(len(library_backups), 1)
        self.assertEqual(library_backups[0].read_text(), 'old library')
        self.assertFalse((self.live / 'plugins/not-for-live.obj').exists())
        backups = list((self.root / 'backups/plugins/namehook').glob('*/namehook.dll'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), b'\x00old plugin')
        self.assertIn('/unload namehook then /load namehook', output)
        code, output = self.run_deploy('-y', 'rollback', 'plugins/namehook')
        self.assertEqual(code, 0, output)
        self.assertEqual((self.live / 'plugins/namehook.dll').read_bytes(), b'\x00old plugin')

    def test_plugin_updates_even_when_lua_matches(self):
        self.put(self.live / 'addons/name/name.lua', 'new name')
        self.put(self.live / 'plugins/namehook.dll', b'old plugin')
        code, output = self.run_deploy('-y', 'push', 'name')
        self.assertEqual(code, 0, output)
        self.assertIn('Pushed plugins/namehook', output)
        self.assertNotIn('Pushed name.', output)
        self.assertEqual((self.live / 'plugins/namehook.dll').read_bytes(), b'\x00new plugin')

    def test_all_push_includes_new_namehook_but_not_other_new_plugins(self):
        self.put(self.project / 'addons/libs/winxi/example.lua', 'library')
        self.put(self.project / 'plugins/unused/build/unused.dll', b'unused')
        code, output = self.run_deploy('-a', 'push')
        self.assertEqual(code, 0, output)
        self.assertLess(output.index('Pushed libs/winxi'), output.index('Pushed plugins/namehook'))
        self.assertLess(output.index('Pushed plugins/namehook'), output.index('Pushed name.'))
        self.assertEqual((self.live / 'plugins/namehook.dll').read_bytes(), b'\x00new plugin')
        self.assertFalse((self.live / 'plugins/unused.dll').exists())

    def test_missing_plugin_build_aborts_before_any_copy(self):
        (self.project / 'plugins/namehook/build/namehook.dll').unlink()
        for args in [('-y', 'push', 'name'), ('-a', 'push')]:
            code, output = self.run_deploy(*args)
            self.assertNotEqual(code, 0, output)
            self.assertIn("no build of 'namehook'", output)
            self.assertFalse((self.live / 'addons/name').exists())
            self.assertFalse((self.root / 'backups').exists())

    def test_missing_library_aborts_before_any_copy(self):
        shutil.rmtree(self.project / 'addons/libs/winxi')
        for args in [('-y', 'push', 'name'), ('-a', 'push')]:
            code, output = self.run_deploy(*args)
            self.assertNotEqual(code, 0, output)
            self.assertFalse((self.live / 'addons/name').exists())
            self.assertFalse((self.live / 'plugins').exists())
            self.assertFalse((self.root / 'backups').exists())

    def test_terminal_guard_is_preserved(self):
        for args in [('-y', 'push', 'name'), ('-a', 'push')]:
            code, output = self.run_deploy(*args, terminal=False)
            self.assertNotEqual(code, 0, output)
            self.assertIn('needs a person at the terminal', output)
            self.assertFalse((self.live / 'plugins').exists())
            self.assertFalse((self.live / 'addons/name').exists())

    def test_declining_cancels_both_targets(self):
        code, output = self.run_deploy('push', 'name', answer='n')
        self.assertEqual(code, 0, output)
        self.assertIn('Nothing was changed.', output)
        self.assertFalse((self.live / 'plugins').exists())
        self.assertFalse((self.live / 'addons/name').exists())

    def test_matching_targets_are_not_copied(self):
        self.put(self.live / 'addons/name/name.lua', 'new name')
        self.put(self.live / 'plugins/namehook.dll', b'\x00new plugin')
        code, output = self.run_deploy('push', 'name', terminal=False)
        self.assertEqual(code, 0, output)
        self.assertIn('nothing to push', output)
        self.assertFalse((self.root / 'backups').exists())

    def test_unrelated_named_addon_does_not_push_namehook(self):
        self.put(self.project / 'addons/other/other.lua', 'other addon')
        code, output = self.run_deploy('-y', 'push', 'other')
        self.assertEqual(code, 0, output)
        self.assertIn('Pushed other.', output)
        self.assertFalse((self.live / 'plugins').exists())


if __name__ == '__main__':
    unittest.main()
