import unittest
from build_name_cast_times import parse, render


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

    def test_deterministic_sorted_output(self):
        text = render({300: 2, 257: .25})
        self.assertLess(text.index('[257]'), text.index('[300]'))
        self.assertIn('Estimates only', text)
        self.assertIn('[257] = 0.25', text)


if __name__ == '__main__':
    unittest.main()
