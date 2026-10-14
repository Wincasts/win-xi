import unittest
from build_zoneinfo_maps import anchor, build, guessed_polygon


class MapDraftTests(unittest.TestCase):
    def test_feature_anchor_beats_text(self):
        self.assertEqual(anchor({'name': 'Knightwell', 'map_x': 238, 'map_y': 336}, {}, 0, 1),
                         (238, 336, 'reviewed_feature_anchor', True))

    def test_ocr_hint_is_normalized_and_marked(self):
        record = {'width': 2048, 'height': 2048, 'ocr_candidates': [
            {'text': 'Parradamo', 'sightings': [{'text_box': [800, 1000, 160, 80]}]}]}
        x, y, method, enabled = anchor({'name': 'Parradamo Tor'}, record, 0, 1)
        self.assertEqual((x, y), (220, 260))
        self.assertIn('NOT_feature_extent', method)
        self.assertTrue(enabled)

    def test_unlocalized_name_is_disabled(self):
        x, y, method, enabled = anchor({'name': 'Missing Landmark'}, {'ocr_candidates': []}, 0, 1)
        self.assertEqual((x, y), (256, 256))
        self.assertFalse(enabled)
        self.assertEqual(method, 'unlocalized_editor_template')

    def test_guess_keeps_vertices_inside_image(self):
        for name in ['River', 'Lake', 'Hill', 'Sands', 'Street', 'Knightwell', 'Landmark']:
            for x, y in [(0, 0), (512, 512), (256, 256)]:
                polygon = guessed_polygon(name, 'geography', x, y)
                self.assertEqual(len(polygon), 8)
                self.assertTrue(all(0 <= p[0] <= 512 and 0 <= p[1] <= 512 for p in polygon))

    def test_bridge_is_not_misclassified_as_ridge(self):
        polygon = guessed_polygon('Artisan Bridge', 'landmark', 256, 256)
        self.assertEqual(max(p[0] for p in polygon) - min(p[0] for p in polygon), 80)
        self.assertEqual(max(p[1] for p in polygon) - min(p[1] for p in polygon), 24)
        ridge = guessed_polygon('Thousandfall Ridge', 'geography', 256, 256)
        self.assertEqual(max(p[1] for p in ridge) - min(p[1] for p in ridge), 68)

    def test_crag_has_broader_surrounding_terrain_than_pond(self):
        crag = guessed_polygon('Crag of Holla', 'landmark', 256, 256)
        pond = guessed_polygon('Knightwell', 'pond', 256, 256)
        self.assertGreater(max(p[0] for p in crag) - min(p[0] for p in crag), max(p[0] for p in pond) - min(p[0] for p in pond))

    def test_every_raster_including_empty_and_unknown_floor(self):
        catalog = {'zones': [{'zone_id': 100, 'zone_name': 'Test', 'maps': [
            {'texture': 'm_100_00', 'map_index': 0, 'sha256': 'a' * 64, 'dat': 'a.DAT',
             'review_status': 'pending', 'reviewed_labels': []},
            {'texture': 'm_100_01', 'map_index': 1, 'sha256': 'b' * 64, 'dat': 'b.DAT',
             'review_status': 'reviewed', 'reviewed_labels': [{'name': 'Lake', 'kind': 'lake', 'map_x': 10, 'map_y': 10}]}]}]}
        maps = build(catalog, {100: {0: 0}})
        self.assertEqual(len(maps), 2)
        self.assertNotEqual(maps[0]['key'], maps[1]['key'])
        self.assertFalse(maps[0]['areas'][0]['enabled'])
        self.assertEqual(maps[0]['table_index'], 0)
        self.assertIsNone(maps[1]['table_index'])
        self.assertTrue(maps[1]['areas'][0]['enabled'])


if __name__ == '__main__':
    unittest.main()
