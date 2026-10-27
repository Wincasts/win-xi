import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from build_name_cast_times import handle, parse, ready_times, render

TABLE = ("CREATE TABLE IF NOT EXISTS `mob_skills` (\n  `mob_skill_id` smallint(4) unsigned NOT NULL,\n"
         "  `mob_skill_name` varchar(40) NOT NULL,\n  `mob_prepare_time` smallint(4) unsigned NOT NULL DEFAULT '1000',\n"
         "  PRIMARY KEY (`mob_skill_id`)\n) ENGINE=Aria;\n")


class CastTimeTests(unittest.TestCase):
    def test_base_ready_time_not_animation_time(self):
        text = "INSERT INTO `mob_skills` VALUES (257,1,'move',0,0,6,9000,1500,4);\n"
        self.assertEqual(parse(text), {257: 1.5})

    def test_zero_is_not_a_fabricated_duration(self):
        text = "INSERT INTO `mob_skills` VALUES (258,2,'a',0,0,6,9000,0,4);\n"
        text += "INSERT INTO `mob_skills` VALUES (259,2,'b',0,0,6,9000,2000,4);\n"
        self.assertEqual(parse(text), {259: 2})

    def test_bad_bounds_and_missing_data(self):
        for text in ['', "INSERT INTO `mob_skills` VALUES (257,1,'move');",
                     "INSERT INTO `mob_skills` VALUES (257,1,'move',0,0,6,9000,999999,4);"]:
            with self.assertRaises(ValueError):
                parse(text)

    def test_commented_out_rows_are_not_loaded(self):
        text = "-- INSERT INTO `mob_skills` VALUES (256,253,'#0',2,0.0,50.0,2000,500,6);\n"
        text += "INSERT INTO `mob_skills` VALUES (259,2,'b',0,0,6,9000,2000,4);\n"
        self.assertEqual(parse(text), {259: 2})

    def test_module_sql_over_the_base(self):
        root = Path(tempfile.mkdtemp())
        (root / 'sql').mkdir()
        (root / 'sql/mob_skills.sql').write_text(TABLE + "INSERT INTO `mob_skills` VALUES (370,'baleful_gaze_lizard',1500);\n"
                                                 "INSERT INTO `mob_skills` VALUES (1026,'arbor_storm',1000);\n"
                                                 "-- INSERT INTO `mob_skills` VALUES (256,'gone',500);\n")
        (root / 'modules/live/sql').mkdir(parents=True)
        (root / 'modules/init.txt').write_text('live/sql\n')
        (root / 'modules/live/sql/a.sql').write_text("UPDATE `mob_skills` SET `mob_prepare_time` = 1800 WHERE `mob_skill_name` = 'baleful_gaze_lizard';\n"
                                                     "DELETE FROM `mob_skills` WHERE `mob_skill_id` = 1026;\n"
                                                     "INSERT INTO `mob_skills` VALUES (1026,'arbor_storm',2500);\n")
        rows, applied = ready_times(root)
        self.assertEqual(rows, {370: 1.8, 1026: 2.5})
        self.assertEqual(applied, ['modules/live/sql/a.sql'])

    def test_overrides(self):
        self.assertEqual(handle(SimpleNamespace(body='function(mob) mob:useMobAbility(1234) end')), 'leaves ready times')
        self.assertTrue(handle(SimpleNamespace(body='function(mob) mob:useMobAbility(1234, target, 3000) end')).startswith('gives'))
        self.assertIsNone(handle(SimpleNamespace(body='function(mob, skill) skill:setActivationTime(3) end')))

    def test_deterministic_sorted_output(self):
        text = render({300: 2, 257: .25})
        self.assertLess(text.index('[257]'), text.index('[300]'))
        self.assertIn('Estimates only', text)
        self.assertIn('[257] = 0.25', text)


if __name__ == '__main__':
    unittest.main()
