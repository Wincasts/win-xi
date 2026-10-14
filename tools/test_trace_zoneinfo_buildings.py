import unittest

import numpy as np
from PIL import Image, ImageDraw

from refine_zoneinfo_boundaries import valid_polygon
from trace_zoneinfo_buildings import WORK, outline, simplify, slug, trace_box

STREET, BUILDING, LINE = (249, 232, 185), (240, 200, 110), (110, 60, 20)


def page():
    image = Image.new('RGB', (WORK, WORK), STREET)
    return image, ImageDraw.Draw(image)


def bounds(polygon):
    xs, ys = [p[0] for p in polygon], [p[1] for p in polygon]
    return min(xs), min(ys), max(xs), max(ys)


class TraceTests(unittest.TestCase):
    def test_outline_of_a_rectangle_is_its_four_corners(self):
        mask = np.zeros((20, 30), bool); mask[5:15, 4:24] = True
        self.assertEqual(sorted(simplify(outline(mask), 1.2)), [(4, 5), (4, 15), (24, 5), (24, 15)])

    def test_outline_follows_an_l_shape(self):
        mask = np.zeros((30, 30), bool); mask[5:25, 5:15] = True; mask[15:25, 15:25] = True
        self.assertEqual(len(simplify(outline(mask), 1.2)), 6)

    def test_building_is_traced_to_its_wall(self):
        image, pen = page()
        pen.rectangle((200, 300, 280, 360), fill=BUILDING, outline=LINE, width=3)   # 100..140 by 150..180 in map units
        polygon, note = trace_box(image, (90, 140, 150, 190), BUILDING)
        self.assertIsNone(note)
        self.assertTrue(valid_polygon(polygon))
        x0, y0, x1, y1 = bounds(polygon)
        for found, wanted in zip((x0, y0, x1, y1), (100, 150, 140, 180)):
            self.assertAlmostEqual(found, wanted, delta=2)

    def test_lines_and_lettering_across_a_building_do_not_split_it(self):
        image, pen = page()
        pen.rectangle((200, 300, 280, 360), fill=BUILDING, outline=LINE, width=3)
        pen.line((240, 300, 240, 360), fill=LINE, width=3)     # A wall inside it.
        pen.line((150, 250, 330, 400), fill=LINE, width=2)     # A leader line over it.
        polygon, _ = trace_box(image, (90, 140, 150, 190), BUILDING)
        x0, y0, x1, y1 = bounds(polygon)
        self.assertLess(x0, 103); self.assertGreater(x1, 137)

    def test_a_neighbour_cut_by_the_box_is_left_out(self):
        image, pen = page()
        pen.rectangle((200, 300, 280, 360), fill=BUILDING, outline=LINE, width=3)
        pen.rectangle((290, 300, 400, 360), fill=BUILDING, outline=LINE, width=3)   # From 145 across: the box stops at 150.
        polygon, _ = trace_box(image, (90, 140, 150, 190), BUILDING)
        self.assertLess(bounds(polygon)[2], 143)

    def test_an_empty_box_is_reported(self):
        image, _ = page()
        polygon, note = trace_box(image, (90, 140, 150, 190), BUILDING)
        self.assertIsNone(polygon); self.assertIn('nothing painted', note)

    def test_ids_are_made_as_the_label_review_makes_them(self):
        self.assertEqual(slug("Hohbiba-Mubiba's Wands of Wonder"), 'hohbiba_mubiba_s_wands_of_wonder')


if __name__ == '__main__':
    unittest.main()
