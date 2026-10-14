import tempfile
import unittest
from pathlib import Path

from build_map_label_catalog import build_catalog, candidate_lines, compact_records, write_lua, zone_names
import json


def record():
    return {
        'zone_id': 100, 'map_index': 0, 'dat': 'ROM/17/24.DAT',
        'duplicate_dats': ['ROM/other.DAT'], 'texture': 'm_100_00',
        'sha256': 'abc', 'image': 'map.png', 'width': 2048, 'height': 2048,
        'ocr': [{'variant': 'original', 'lines': [
            {'text': 'Cheval River', 'confidence': 90, 'box': [1, 2, 3, 4]},
            {'text': 'West Ronfaure', 'confidence': 95, 'box': [5, 6, 7, 8]},
            {'text': 'remapster.com', 'confidence': 95, 'box': [5, 6, 7, 8]},
        ]}],
    }


class CatalogTests(unittest.TestCase):
    def inputs(self):
        return (
            {'source_pack': 'pack', 'scanned_dats': 3, 'maps': [record()], 'decode_errors': [], 'unmatched_dats': []},
            {100: 'West Ronfaure', 101: 'East Ronfaure'},
            {'scope': 'Selected areas', 'maps': []},
        )

    def test_missing_map_not_counted_as_mapped_or_reviewed(self):
        catalog = build_catalog(*self.inputs())
        self.assertEqual(catalog['summary']['zones_with_maps'], 1)
        self.assertEqual(catalog['summary']['zones_without_maps'], 1)
        self.assertEqual(catalog['summary']['zone_map_dats'], 2)
        self.assertEqual(catalog['zones'][0]['coverage_status'], 'extracted_pending_review')
        self.assertEqual(catalog['zones'][1]['coverage_status'], 'no_map_in_pack')
        self.assertEqual(catalog['zones'][0]['reviewed_names'], [])

    def test_candidate_hints_do_not_approve_names(self):
        candidates = candidate_lines(record(), {'westronfaure'})
        self.assertEqual(len(candidates), 2)
        self.assertEqual(candidates[0]['category_hint'], 'possible_area_label')
        self.assertEqual(candidates[1]['category_hint'], 'zone_title_or_destination')
        self.assertTrue(all(c['review_status'] == 'unreviewed' for c in candidates))

    def test_review_alias_resolves_to_identical_raster(self):
        manifest, names, reviews = self.inputs()
        reviews['maps'] = [{
            'dat': 'ROM/other.DAT', 'review_status': 'selected_labels_reviewed',
            'labels': [{'name': 'Cheval River', 'kind': 'river', 'map_x': 20, 'map_y': 30}],
        }]
        catalog = build_catalog(manifest, names, reviews)
        self.assertEqual(catalog['summary']['reviewed_label_entries'], 1)
        self.assertEqual(catalog['zones'][0]['maps'][0]['ocr_candidates'][0]['review_status'], 'text_matches_reviewed_label')
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'data.lua'
            write_lua(catalog, output)
            text = output.read_text()
            self.assertIn('map_x = 20, map_y = 30', text)
            self.assertIn('zones_without_maps', text)
            self.assertNotIn('name = "West Ronfaure", kind', text)

    def test_unknown_review_dat_is_rejected(self):
        manifest, names, reviews = self.inputs()
        reviews['maps'] = [{'dat': 'absent.DAT', 'labels': []}]
        with self.assertRaisesRegex(ValueError, 'Review DAT not in extracted manifest'):
            build_catalog(manifest, names, reviews)

    def test_compact_serialization_roundtrips(self):
        catalog = build_catalog(*self.inputs())
        self.assertEqual(json.loads(compact_records(catalog, 'zones')), catalog)

    def test_resource_names_support_both_quote_styles(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'zones.lua'
            path.write_text('return {\n [1] = { id = 1, en = "King Ranperre\'s Tomb", ja = \'x\' },\n'
                            ' [2] = { id = 2, en = \'West Ronfaure\', ja = \'x\' },\n}\n')
            self.assertEqual(zone_names(path), {1: "King Ranperre's Tomb", 2: 'West Ronfaure'})


if __name__ == '__main__':
    unittest.main()
