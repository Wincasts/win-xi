import sqlite3
import tempfile
import unittest
from pathlib import Path

from build_item_data import enabled_files, lua, replay, statements, translate


class ItemsBuildTest(unittest.TestCase):
    def test_strings_comments_and_variables(self):
        sql = "-- ignored;\nINSERT INTO item_basic VALUES (1,'king\\'s; blade',@FLAG | 2); # comment\n"
        parts = list(statements(sql))
        self.assertEqual(len(parts), 1)
        translated = translate(parts[0], {'@flag': 4})
        db = sqlite3.connect(':memory:')
        db.execute('CREATE TABLE item_basic (id, name, flags)')
        db.execute(translated)
        self.assertEqual(db.execute('SELECT * FROM item_basic').fetchone(), (1, "king's; blade", 6))
        self.assertEqual(translate("'@missing'", {}), "'@missing'")
        with self.assertRaises(ValueError):
            translate('@missing', {})
        with self.assertRaises(ValueError):
            list(statements('UPDATE item_basic SET flags=0'))

    def test_replay_update_delete_replace_and_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'data.sql'
            path.write_text('CREATE TABLE `item_mods` (\n `itemId` int,\n `modId` int,\n `value` int,\n PRIMARY KEY (`itemId`,`modId`)\n) ENGINE=Aria;\nINSERT INTO item_mods VALUES (1,2,3);')
            db = sqlite3.connect(':memory:')
            replay(db, path, {})
            path.write_text('REPLACE INTO item_mods VALUES (1,2,7); UPDATE item_mods SET value=value|8 WHERE itemId=1;')
            replay(db, path, {}, True)
            self.assertEqual(db.execute('SELECT * FROM item_mods').fetchall(), [(1, 2, 15)])
            path.write_text('DELETE FROM item_mods WHERE itemId=1;')
            replay(db, path, {}, True)
            self.assertEqual(db.execute('SELECT count(*) FROM item_mods').fetchone()[0], 0)
            path.write_text('TRUNCATE TABLE item_mods;')
            with self.assertRaises(ValueError):
                replay(db, path, {}, True)

    def test_enabled_order_recursive_disabled_and_duplicates(self):
        with tempfile.TemporaryDirectory() as tmp:
            server = Path(tmp)
            modules = server / 'modules'
            (modules / 'a/nested').mkdir(parents=True)
            (modules / 'b').mkdir()
            for name in ('a/z.sql', 'a/nested/x.sql', 'b/disabled.sql'):
                (modules / name).write_text('')
            (modules / 'init.txt').write_text('# b\na/\na/z.sql\n')
            self.assertEqual([str(p.relative_to(modules)) for p in enabled_files(server, '.sql')], ['a/nested/x.sql', 'a/z.sql'])

    def test_lua_escaping(self):
        self.assertEqual(lua('a\n"b\\'), '"a\\n\\"b\\\\"')


if __name__ == '__main__':
    unittest.main()
