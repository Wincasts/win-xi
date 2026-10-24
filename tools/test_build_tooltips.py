import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

from build_tooltips import build, lua_quote, parse_catalogue, references, render
from package_release import winxi_modules


SAMPLE = '''# Test catalogue

## example.appearance.bold
Label: Bold
Location: Names → Appearance

A "quote", a backslash: \\ and 100%.

Second paragraph: [name], café.
'''


class TooltipBuildTests(unittest.TestCase):
    def test_text_and_metadata(self):
        entry = parse_catalogue(SAMPLE, 'example')['example.appearance.bold']
        self.assertEqual(entry.label, 'Bold')
        self.assertEqual(entry.location, 'Names → Appearance')
        self.assertEqual(entry.text, 'A "quote", a backslash: \\ and 100%.\n\nSecond paragraph: [name], café.')
        self.assertEqual(parse_catalogue(SAMPLE.replace('\n', '\r\n'), 'example')[entry.id], entry)

    def test_invalid_catalogues(self):
        for text in [SAMPLE + SAMPLE, SAMPLE.replace('example.appearance.bold', 'other.bold'),
                     SAMPLE.replace('Label: Bold', 'Label: '), SAMPLE.replace('Location: Names → Appearance', 'Wrong: X'),
                     SAMPLE[:SAMPLE.index('A "quote"')], SAMPLE.replace('example.appearance.bold', 'example..bold'),
                     SAMPLE.replace('100%', '100%\x00')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_catalogue(text, 'example')

    def test_literal_references_only(self):
        source = '''-- tips.Get('comment.not_used')
--[=[ tips.Get('long_comment.not_used') ]=]
local text = "tips.Get('text.not_used')"
local long = [==[ tips.Get('long_string.not_used') ]==]
function tips.Get(id, values) end
local a = tips.Get('example.appearance.bold')
local b = tips.Get("example.other", { seconds = 5 })
'''
        self.assertEqual(references(source), {'example.appearance.bold', 'example.other'})
        for source in ['tips.Get(id)', "tips.Get('example.' .. key)", "tips.Get('example.bad' .. suffix)"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                references(source)

    def test_lua_roundtrip_and_safe_escaping(self):
        text = 'Quotes: " and \\;\n\t100% café "); error("not code"); --'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'roundtrip.lua'
            path.write_text('io.write(' + lua_quote(text) + ')', encoding='utf-8')
            self.assertEqual(subprocess.check_output(['luajit', str(path)]).decode('utf-8'), text)

    def test_build_check_and_missing_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tooltips').mkdir()
            (root / 'tooltips/example.md').write_text(SAMPLE, encoding='utf-8')
            (root / 'addons/example').mkdir(parents=True)
            source = root / 'addons/example/example.lua'
            source.write_text("local tips = require('winxi.tips'); return tips.Get('example.appearance.bold')")
            target = root / 'addons/libs/winxi/data/tooltips/example.lua'
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(build(root, check=True), 1)
                self.assertFalse(target.exists())
                self.assertEqual(build(root), 0)
                self.assertEqual(build(root, check=True), 0)
                self.assertEqual(target.read_text(), render(parse_catalogue(SAMPLE, 'example'), 'tooltips/example.md'))
                previous = target.read_bytes()
                (root / 'tooltips/example.md').write_text(SAMPLE.replace('Second paragraph', 'Edited paragraph'), encoding='utf-8')
                self.assertEqual(build(root, check=True), 1)
                self.assertEqual(target.read_bytes(), previous)
                source.write_text("return tips.Get('example.missing')")
                with self.assertRaisesRegex(ValueError, 'missing tooltip IDs'):
                    build(root)
                self.assertEqual(target.read_bytes(), previous)

    def test_private_addon_packaging_includes_catalogues(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            addon = root / 'addons/example'
            library = root / 'addons/libs/winxi'
            addon.mkdir(parents=True)
            (library / 'data/tooltips').mkdir(parents=True)
            (addon / 'example.lua').write_text("local tips = require('winxi.tips'); return tips.Get('example.appearance.bold')")
            (library / 'version.lua').write_text('return {}')
            (library / 'tips.lua').write_text('return {}')
            (library / 'data/tooltips/example.lua').write_text('return {}')
            names, paths = winxi_modules(root, 'example')
            self.assertIn('data.tooltips.example', names)
            self.assertIn(Path('data/tooltips/example.lua'), paths)

    def test_unused_warning_and_second_addon(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tooltips').mkdir()
            (root / 'tooltips/example.md').write_text(SAMPLE, encoding='utf-8')
            (root / 'tooltips/party.md').write_text(SAMPLE.replace('example.', 'party.'), encoding='utf-8')
            errors = io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
                self.assertEqual(build(root), 0)
            self.assertIn('unused tooltip: party.appearance.bold', errors.getvalue())
            self.assertTrue((root / 'addons/libs/winxi/data/tooltips/party.lua').exists())


if __name__ == '__main__':
    unittest.main()
