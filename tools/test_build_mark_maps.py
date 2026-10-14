import hashlib
import json
from pathlib import Path
import struct
import re
import tempfile
import unittest

from PIL import Image
from build_mark_maps import ROOT, export_maps


def indexed_dat(size):
    data = bytearray(65)
    data[57:65] = b'm_100_00'
    data += struct.pack('<IiiHHIIIIIII', 40, size, size, 1, 8, 0, size * size, 0, 0, 256, 0, 10)
    data += bytes(channel for i in range(256) for channel in (i, i, i, 255))
    # Distinct top/bottom halves detect flipping or cropping as well as native dimensions.
    data += bytes([220]) * (size * size // 2) + bytes([30]) * (size * size // 2)
    return data


class MarkMapExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pack = self.root / 'pack'
        self.pack.mkdir()
        self.catalog = self.root / 'maps.lua'
        self.manifest = self.root / 'source.json'
        self.output = self.root / 'output'

    def source(self, name, size):
        data = indexed_dat(size)
        (self.pack / f'{name}.DAT').write_bytes(data)
        return dict(image=f'maps/all/{name}.jpg', dat=f'{name}.DAT', sha256=hashlib.sha256(data).hexdigest(), zone_id=100, floor_id=0)

    def prepare(self, records, catalog=None):
        self.manifest.write_text(json.dumps(dict(maps=records)))
        self.catalog.write_text(catalog or "return { { image = 'high.jpg' }, { image = \"low.jpg\" } }")

    def export(self):
        return export_maps(self.pack, self.catalog, self.manifest, self.output)

    def test_native_resolution_orientation_and_selection(self):
        self.prepare([self.source('high', 2048), self.source('low', 512), self.source('unused', 16)])
        result = self.export()
        self.assertEqual(result['summary'], dict(maps=2, sizes={'512x512': 1, '2048x2048': 1}))
        self.assertFalse(result['resized'])
        self.assertEqual(result['reference_size'], 512)
        for name, size in [('high', 2048), ('low', 512)]:
            with Image.open(self.output / f'{name}.jpg') as image:
                self.assertEqual(image.size, (size, size))
                self.assertLess(image.getpixel((size // 2, 0))[0], 40)
                self.assertGreater(image.getpixel((size // 2, size - 1))[0], 210)
        self.assertFalse((self.output / 'unused.jpg').exists())
        self.assertEqual(json.loads((self.output / 'manifest.json').read_text()), result)

    def test_rejects_wrong_source_hash(self):
        record = self.source('high', 16)
        record['sha256'] = '0' * 64
        self.prepare([record], "return {{image = 'high.jpg'}}")
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.export()
        self.assertFalse((self.output / 'high.jpg').exists())

    def test_rejects_missing_and_ambiguous_mapping(self):
        record = self.source('high', 16)
        self.prepare([record])
        with self.assertRaisesRegex(ValueError, 'No source mapping'):
            self.export()
        self.prepare([record, record], "return {{image = 'high.jpg'}}")
        with self.assertRaisesRegex(ValueError, 'Duplicate source'):
            self.export()

    def test_rejects_empty_catalog_and_path_traversal(self):
        self.prepare([], 'return {}')
        with self.assertRaisesRegex(ValueError, 'No map images'):
            self.export()
        self.prepare([], "return {{image = '../outside.jpg'}}")
        with self.assertRaisesRegex(ValueError, 'plain .jpg filenames'):
            self.export()
        record = self.source('high', 16)
        record['dat'] = '../outside.DAT'
        self.prepare([record], "return {{image = 'high.jpg'}}")
        with self.assertRaisesRegex(ValueError, 'Invalid DAT path'):
            self.export()


class BundledMapTests(unittest.TestCase):
    def test_generated_assets_match_catalog_and_native_manifest(self):
        output = ROOT / 'addons/mark/assets/maps'
        manifest = json.loads((output / 'manifest.json').read_text())
        catalog = (ROOT / 'addons/mark/data/maps.lua').read_text()
        wanted = set(re.findall(r"image\s*=\s*['\"]([^'\"]+)['\"]", catalog))
        self.assertEqual({record['image'] for record in manifest['maps']}, wanted)
        self.assertEqual(manifest['summary']['maps'], len(wanted))
        self.assertFalse(manifest['resized'])
        self.assertEqual(manifest['reference_size'], 512)
        for record in manifest['maps']:
            with self.subTest(image=record['image']):
                with Image.open(output / record['image']) as image:
                    self.assertEqual(list(image.size), record['size'])


if __name__ == '__main__':
    unittest.main()
