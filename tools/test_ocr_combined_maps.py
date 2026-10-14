"""Offline tests for the raster OCR inventory pipeline."""
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

from ocr_combined_maps import parse_tsv, recognize, scan
from scan_combined_maps import decode as decode_dat


HEADER = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'


class OcrTests(unittest.TestCase):
    def test_tsv_groups_words_and_preserves_boxes(self):
        text = HEADER + (
            '4\t1\t1\t1\t1\t0\t0\t0\t0\t0\t-1\t\n'
            '5\t1\t1\t1\t1\t1\t10\t20\t30\t10\t90\tCheval\n'
            '5\t1\t1\t1\t1\t2\t45\t18\t20\t12\t80\tRiver\n'
            '5\t1\t2\t1\t1\t1\t100\t100\t20\t10\t50\tOther\n'
        )
        lines = parse_tsv(text)
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]['text'], 'Cheval River')
        self.assertEqual(lines[0]['box'], [10, 18, 55, 12])
        self.assertEqual(lines[0]['confidence'], 85)
        self.assertEqual(lines[0]['words'][0]['box'], [10, 20, 30, 10])

    def test_empty_tsv(self):
        self.assertEqual(parse_tsv(HEADER), [])

    @patch('ocr_combined_maps.subprocess.run')
    def test_tesseract_uses_parameter_without_config_files(self, run):
        run.return_value.stdout = HEADER
        self.assertEqual(recognize(Path('test.png'), Path('/tmp/model')), [])
        args, kwargs = run.call_args
        self.assertIn('tessedit_create_tsv=1', args[0])
        self.assertIn('--tessdata-dir', args[0])
        self.assertTrue(kwargs['check'])
        self.assertEqual(kwargs['env']['OMP_THREAD_LIMIT'], '1')

    @patch('ocr_combined_maps.recognize', return_value=[])
    @patch('ocr_combined_maps.decode', return_value=Image.new('RGB', (16, 16)))
    def test_scan_filters_zones_and_deduplicates_by_hash(self, decode, recognize):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack, output = root / 'pack', root / 'output'
            pack.mkdir()
            selected = bytes(57) + b'm_190_01' + b'payload'
            (pack / 'a.DAT').write_bytes(selected)
            (pack / 'b.DAT').write_bytes(selected)
            (pack / 'c.DAT').write_bytes(bytes(57) + b'm_100_00')
            (pack / 'd.DAT').write_bytes(b'not a map')
            manifest = scan(pack, output, {190})
            self.assertEqual(manifest['scanned_dats'], 4)
            self.assertEqual(len(manifest['maps']), 1)
            record = manifest['maps'][0]
            self.assertEqual(record['duplicate_dats'], ['b.DAT'])
            self.assertEqual(record['zone_id'], 190)
            self.assertEqual(record['map_index'], 1)
            self.assertEqual(decode.call_count, 1)
            self.assertEqual(recognize.call_count, 2)
            self.assertTrue((output / record['image']).exists())
            self.assertEqual(json.loads((output / 'ocr_manifest.json').read_text()), manifest)

    @patch('ocr_combined_maps.recognize', return_value=[])
    @patch('ocr_combined_maps.decode', return_value=Image.new('RGB', (16, 16)))
    def test_resume_reuses_matching_hash_and_invalidates_changed_dat(self, decode, recognize):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack, output = root / 'pack', root / 'output'
            pack.mkdir()
            path = pack / 'a.DAT'
            payload = bytes(57) + b'm_190_01'
            path.write_bytes(payload)
            scan(pack, output, jobs=2)
            scan(pack, output, jobs=2, resume=True)
            self.assertEqual(decode.call_count, 1)
            self.assertEqual(recognize.call_count, 2)
            path.write_bytes(payload + b'changed')
            scan(pack, output, jobs=2, resume=True)
            self.assertEqual(decode.call_count, 2)
            self.assertEqual(recognize.call_count, 4)

    @patch('ocr_combined_maps.decode', side_effect=ValueError('Unsupported map image header'))
    def test_scan_records_decode_failure(self, decode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack = root / 'pack'
            pack.mkdir()
            (pack / 'bad.DAT').write_bytes(bytes(57) + b'm_190_01')
            manifest = scan(pack, root / 'output', {190})
            self.assertEqual(manifest['maps'], [])
            self.assertEqual(manifest['decode_errors'][0]['dat'], 'bad.DAT')


class IndexedBitmapTests(unittest.TestCase):
    def payload(self):
        header = bytes(65) + struct.pack('<IiiHHIIIIIII', 40, 2, 2, 1, 8, 0, 0, 0, 0, 0, 32, 10)
        palette = bytearray(1024)
        # BGRA, deliberately different from RGB and with alpha ignored for OCR.
        palette[0:4] = bytes([0, 0, 255, 0])
        palette[4:8] = bytes([255, 0, 0, 255])
        return header + palette + bytes([0, 0, 1, 1])

    def test_palette_offset_bgra_and_bottom_up_orientation(self):
        image = decode_dat(self.payload())
        self.assertEqual(image.size, (2, 2))
        self.assertEqual(image.getpixel((0, 0)), (0, 0, 255))
        self.assertEqual(image.getpixel((0, 1)), (255, 0, 0))

    def test_truncated_indices_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Truncated indexed'):
            decode_dat(self.payload()[:-1])


if __name__ == '__main__':
    unittest.main()
