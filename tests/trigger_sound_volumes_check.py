"""Validate all shipped volume copies and the generator's PCM handling."""
import importlib.util
from pathlib import Path
import tempfile
import wave

folder = Path(__file__).resolve().parents[1] / 'addons/trigger/sounds'
spec = importlib.util.spec_from_file_location('generate_volumes', folder / 'generate_volumes.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def read(path):
    with wave.open(str(path), 'rb') as wav:
        return wav.getparams(), wav.readframes(wav.getnframes())


sources = sorted(folder.glob('*.wav'))
assert len(sources) == 50
with tempfile.TemporaryDirectory() as temp:
    target = Path(temp) / 'expected.wav'
    for source in sources:
        params, data = read(source)
        for level in generator.GAINS:
            gain = generator.generate(source, target, level)
            assert read(folder / level / source.name) == read(target), (source, level)
            assert read(target)[0] == params, 'duration and format must be preserved'
            assert read(target)[1] != data, 'bundled variant must change amplitude'
            if level == 'high':
                assert gain > 1, 'every bundled high sound must be louder'
        assert read(source) == (params, data), 'medium original must not change'

    # Exercise every supported sample width, including unsigned 8-bit and clipped peaks.
    for width in (1, 2, 3, 4):
        limit = 2 ** (8 * width - 1) - 1
        values = [-limit - 1, -limit // 2, 0, limit // 2, limit]
        encoded = b''.join((v + (128 if width == 1 else 0)).to_bytes(
            width, 'little', signed=width != 1) for v in values)
        source = Path(temp) / 'source.wav'
        with wave.open(str(source), 'wb') as wav:
            wav.setparams((1, width, 22050, 0, 'NONE', 'not compressed'))
            wav.writeframes(encoded)
        for level in generator.GAINS:
            generator.generate(source, target, level)
            params, result = read(target)
            assert params.nframes == len(values) and params.sampwidth == width
            assert len(result) == len(encoded)
print('Trigger sound copies: 100 variants and all PCM widths verified')
