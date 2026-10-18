import unittest

import numpy as np
from PIL import Image, ImageDraw

from trace_walkable_maps import WORK, runs, trace

PARCHMENT, FLOOR, STREET, INK, GRID = (232, 205, 145), (243, 223, 171), (250, 238, 210), (60, 30, 10), (150, 110, 70)


def page(size=WORK, seed=1):
    """Mottled parchment with a grid of faint lines every 16 map units, as the maps have."""
    noise = np.random.default_rng(seed).integers(-12, 13, (size, size, 1))
    pixels = np.clip(np.array(PARCHMENT) + noise, 0, 255).astype(np.uint8)
    image = Image.fromarray(pixels, 'RGB')
    pen = ImageDraw.Draw(image)
    step = size // 32
    for at in range(0, size, step):
        pen.line([(at, 0), (at, size)], fill=GRID, width=max(1, size // 1024))
        pen.line([(0, at), (size, at)], fill=GRID, width=max(1, size // 1024))
    return image, pen


def units(mask, x, y):
    return mask[int(y * WORK / 512), int(x * WORK / 512)]


class RunsTests(unittest.TestCase):
    def test_a_row_is_its_runs_out_of_the_ground_first(self):
        row = np.zeros(10, bool); row[2:5] = True; row[7:8] = True
        self.assertEqual(runs(row), '2,3,2,1,2')

    def test_a_row_starting_on_the_ground_starts_with_none_out(self):
        row = np.zeros(6, bool); row[:2] = True
        self.assertEqual(runs(row), '0,2,4')

    def test_an_empty_row_is_nothing(self):
        self.assertEqual(runs(np.zeros(8, bool)), '')


class TraceTests(unittest.TestCase):
    def test_a_room_painted_the_floors_colour_is_found_across_the_grid(self):
        image, pen = page()
        pen.rounded_rectangle((300, 300, 560, 520), radius=20, fill=FLOOR, outline=INK, width=3)
        pen.line([(320, 0), (320, WORK)], fill=GRID)          # a grid line through the room
        mask = trace(image, {'colors': [{'rgb': list(FLOOR)}]})
        self.assertTrue(units(mask, 215, 205))                 # the room, both sides of the grid line
        self.assertTrue(units(mask, 155, 160))
        self.assertTrue(units(mask, 150.5, 205))               # into its wall, grown over
        self.assertFalse(units(mask, 100, 100))                # the parchment
        self.assertFalse(units(mask, 400, 400))

    def test_a_square_of_parchment_fenced_by_the_grid_is_not_ground(self):
        image, pen = page()
        step = WORK // 32
        pen.rectangle((10 * step + 1, 10 * step + 1, 11 * step - 1, 11 * step - 1), fill=FLOOR)
        mask = trace(image, {'colors': [{'rgb': list(FLOOR)}]})
        self.assertFalse(mask.any())

    def test_a_street_lighter_than_the_parchment_is_filled_within_its_lines(self):
        image, pen = page(2048)
        pen.rectangle((400, 1000, 1600, 1060), fill=STREET, outline=INK, width=4)
        mask = trace(image.resize((WORK, WORK)), {'light': 215, 'seeds': [[250, 257]]}, image)
        self.assertTrue(units(mask, 120, 257))
        self.assertTrue(units(mask, 380, 257))                 # across the grid's lines
        self.assertFalse(units(mask, 250, 230))                # not over the line onto the parchment

    def test_cut_and_paths_are_given_by_hand(self):
        image, _ = page()
        mask = trace(image, {'paths': [{'points': [[100, 100], [300, 100]], 'width': 10}], 'cut': [[[190, 90], [210, 90], [210, 110], [190, 110]]]})
        self.assertTrue(units(mask, 150, 100))
        self.assertFalse(units(mask, 200, 100))
        self.assertFalse(units(mask, 150, 120))


if __name__ == '__main__':
    unittest.main()
