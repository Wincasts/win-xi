import sqlite3
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from build_action_data import binary_sql, blob_insert, overlay, lua_without_comments
from build_client_data import HEADER, parse_dictionary, build
from build_item_data import replay


def dictionary(lang=2, category=1, entries=None):
    entries = entries or [(1, 'Hello!', 'ハロー')]
    body = bytearray()
    for number, text, reading in entries:
        body += bytes((2, lang, category, number))
        value = text.encode('cp932') + b'\0'
        body += bytes((len(value),)) + value
        if lang == 1:
            value = reading.encode('cp932') + b'\0'
            body += bytes((len(value),)) + value
    ident = int.from_bytes(bytes((2, lang, category, 0)), 'little')
    return HEADER.pack(ident, b'Greetings', b'Greetings', len(entries), len(body)) + body


class CatalogBuildTest(unittest.TestCase):
    def test_binary_jobs_and_mysql_byte_insert(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'jobs.sql'
            path.write_text('CREATE TABLE `weapon_skills` (\n `id` int,\n `name` text,\n `jobs` binary(22),\n PRIMARY KEY (`id`)\n) ENGINE=Aria;\nINSERT INTO weapon_skills VALUES (1,\'0xAB\',0x02020000000200000000000002000000000202000000);')
            db = sqlite3.connect(':memory:')
            db.create_function('BLOB_INSERT', 4, blob_insert)
            replay(db, path, {}, tables=('weapon_skills',), transform=binary_sql)
            value = db.execute('SELECT jobs FROM weapon_skills').fetchone()[0]
            self.assertEqual(len(value), 22)
            self.assertEqual(value[17], 2)
            path.write_text("UPDATE weapon_skills SET jobs = INSERT(jobs,18,1,0x00) WHERE id=1;")
            replay(db, path, {}, True, tables=('weapon_skills',), transform=binary_sql)
            new = db.execute('SELECT name,jobs FROM weapon_skills').fetchone()
            self.assertEqual(new[0], '0xAB')
            self.assertEqual(new[1], value[:17] + b'\0' + value[18:])
            path.write_text('ALTER TABLE weapon_skills ADD broken int;')
            with self.assertRaises(ValueError):
                replay(db, path, {}, True, tables=('weapon_skills',), transform=binary_sql)
        scalar = "UPDATE spell_list SET element=0x80, name='INSERT(0xFF)';"
        self.assertEqual(binary_sql(scalar, 'spell_list'), scalar)
        self.assertEqual(blob_insert(b'abc', 0, 1, b'z'), b'abc')
        self.assertEqual(blob_insert(b'abc', 4, 1, b'z'), b'abc')

    def test_lua_index_ignores_comments_preserves_strings(self):
        text = "-- addOverride('fake')\nlocal value='-- not a comment'; --[[ block fake ]]\naddOverride('real')"
        cleaned = lua_without_comments(text)
        self.assertNotIn('fake', cleaned)
        self.assertIn("'-- not a comment'", cleaned)
        self.assertIn("addOverride('real')", cleaned)

    def test_enum_overlay_preserves_sibling_ranks_and_caps(self):
        base = {'skills': {'ranks': {'sword': {'war': 'b', 'blu': 'a_plus'}}, 'caps': {1: {'a': 6}}}}
        overlay(base, {'skills': {'ranks': {'sword': {'blu': 'a'}}}})
        self.assertEqual(base['skills']['ranks']['sword'], {'war': 'b', 'blu': 'a'})
        self.assertEqual(base['skills']['caps'][1]['a'], 6)

    def test_english_and_japanese_dictionary(self):
        for lang in (1, 2):
            language, categories, entries = parse_dictionary(dictionary(lang))
            self.assertEqual(language, lang)
            self.assertEqual(categories[1]['Name'], 'Greetings')
            entry = entries[257]
            self.assertEqual(entry['Text'], 'Hello!')
            self.assertEqual(entry['RawId'].to_bytes(4, 'little'), bytes((2, lang, 1, 1)))
            self.assertEqual(entry.get('Reading'), 'ハロー' if lang == 1 else None)

    def test_corrupt_truncated_duplicate_and_wrong_language(self):
        original = dictionary()
        for length in range(len(original)):
            with self.assertRaises(ValueError):
                parse_dictionary(original[:length])
        broken = bytearray(original)
        struct.pack_into('<I', broken, 72, 9999)
        with self.assertRaises(ValueError):
            parse_dictionary(broken)
        with self.assertRaises(ValueError):
            parse_dictionary(dictionary(entries=[(1, 'A', ''), (1, 'B', '')]))
        with self.assertRaises(ValueError):
            parse_dictionary(original + dictionary(category=1))
        with self.assertRaises(ValueError):
            parse_dictionary(original + dictionary(lang=1, category=2))

    def test_client_cli_failure_keeps_previous_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            old = root / 'out'
            old.mkdir()
            (old / 'sentinel').write_text('previous dataset')
            broken = root / 'bad.DAT'
            broken.write_bytes(dictionary()[:-1])
            command = [sys.executable, str(Path(__file__).with_name('build_client_data.py')),
                       '--dat', 'en=' + str(broken), '--out', str(old)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((old / 'sentinel').read_text(), 'previous dataset')
            self.assertFalse((old / 'index.lua').exists())

    def test_portable_client_build_provenance_and_locale_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / '25.DAT'
            path.write_bytes(dictionary())
            metadata = build({'en': path}, root / 'made', 'test-version')
            self.assertEqual(metadata['Count'], 1)
            self.assertEqual(metadata['Source']['Version'], 'test-version')
            self.assertEqual(len(metadata['Source']['Files']['en']['SHA256']), 64)
            self.assertTrue((root / 'made/catalog.json').is_file())
            with self.assertRaises(ValueError):
                build({'../en': path}, root / 'bad')


if __name__ == '__main__':
    unittest.main()
