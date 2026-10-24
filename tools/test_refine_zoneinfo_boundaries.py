import unittest
from pathlib import Path
from refine_zoneinfo_boundaries import apply_refinements, valid_polygon, load_refinements


class RefinementTests(unittest.TestCase):
    def setup_maps(self):
        return [{'key': 'map_hash', 'areas': [{'id': 'river', 'name': 'River', 'enabled': True,
                                              'polygon': [[0, 0], [10, 0], [10, 10]]}]}]

    def patch(self):
        return {'map_key': 'map_hash', 'area_id': 'river', 'enabled': False,
                'method': 'player_authored_example', 'name': 'Named River',
                'polygon': [[20, 10], [30, 30], [25, 50], [15, 30]]}

    def test_preserves_geometry_name_and_disabled_flag(self):
        patch = self.patch()
        area = apply_refinements(self.setup_maps(), {'areas': [patch]})[0]['areas'][0]
        self.assertEqual(area['polygon'], patch['polygon'])
        self.assertEqual(area['name'], patch['name'])
        self.assertFalse(area['enabled'])
        self.assertEqual(area['provenance'], 'player_authored_example')

    def test_no_inheritance_to_other_raster(self):
        patch = self.patch(); patch['map_key'] = 'different_hash'
        with self.assertRaises(ValueError):
            apply_refinements(self.setup_maps(), {'areas': [patch]})

    def test_unknown_feature_rejected(self):
        patch = self.patch(); patch['area_id'] = 'invented'
        with self.assertRaises(ValueError):
            apply_refinements(self.setup_maps(), {'areas': [patch]})

    def test_added_feature_needs_the_flag_and_a_name(self):
        patch = self.patch(); patch['area_id'] = 'outpost'; patch['add'] = True; patch['enabled'] = True
        areas = apply_refinements(self.setup_maps(), {'areas': [patch]})[0]['areas']
        self.assertEqual([a['id'] for a in areas], ['river', 'outpost'])
        self.assertEqual(areas[1]['name'], 'Named River')
        self.assertEqual(areas[1]['polygon'], patch['polygon'])
        del patch['name']
        with self.assertRaises(ValueError):
            apply_refinements(self.setup_maps(), {'areas': [patch]})

    def test_exact_flag_is_set_and_cleared(self):
        patch = self.patch(); patch['exact'] = True
        maps = self.setup_maps()
        self.assertTrue(apply_refinements(maps, {'areas': [patch]})[0]['areas'][0]['exact'])
        del patch['exact']
        self.assertNotIn('exact', apply_refinements(maps, {'areas': [patch]})[0]['areas'][0])

    def test_height_limits_are_set_cleared_and_checked(self):
        patch = self.patch(); patch['z_min'] = 1.0
        maps = self.setup_maps()
        area = apply_refinements(maps, {'areas': [patch]})[0]['areas'][0]
        self.assertEqual((area['z_min'], area.get('z_max')), (1.0, None))
        del patch['z_min']
        self.assertNotIn('z_min', apply_refinements(maps, {'areas': [patch]})[0]['areas'][0])
        patch['z_max'] = 'low'
        with self.assertRaises(ValueError):
            apply_refinements(self.setup_maps(), {'areas': [patch]})

    def test_invalid_geometry_rejected(self):
        for polygon in [[], [[0, 0], [10, 10], [0, 10], [10, 0]],
                        [[0, 0], [10, 0], [513, 10]], [[True, 0], [10, 0], [10, 10]],
                        [[0, 0], [float('nan'), 0], [10, 10]]]:
            self.assertFalse(valid_polygon(polygon))
        patch = self.patch(); patch['polygon'] = [[0, 0], [0, 0], [10, 10]]
        with self.assertRaises(ValueError):
            apply_refinements(self.setup_maps(), {'areas': [patch]})

    def test_checked_source_counts_by_method(self):
        source = load_refinements(Path(__file__).resolve().parent.parent / 'addons/zone/research/boundary_refinements.json')
        self.assertEqual(sum(a['method'] == 'player_authored_example' for a in source['areas']), 27)
        self.assertEqual(sum(a['method'] == 'visually_traced_player_style_draft' for a in source['areas']), 152)
        self.assertEqual(sum(a['method'] == 'building_footprint_traced_from_map_fill' for a in source['areas']), 163)
        self.assertTrue(all(a.get('exact') is True for a in source['areas'] if a['method'] == 'building_footprint_traced_from_map_fill'))
        self.assertEqual(sum(a['method'] == 'inherited_from_identical_raster' for a in source['areas']), 13)
        self.assertEqual(sum(a['method'] == 'inherited_from_present_day_raster' for a in source['areas']), 55)
        self.assertEqual(sum(a['method'] == 'placed_from_phoenix_npc_and_door_positions' for a in source['areas']), 1)
        self.assertEqual(sum(a.get('add') is True for a in source['areas']), 145)
        self.assertTrue(all(valid_polygon(a['polygon']) for a in source['areas']))
        self.assertEqual(len({(a['map_key'], a['area_id']) for a in source['areas']}), 411)


if __name__ == '__main__':
    unittest.main()
