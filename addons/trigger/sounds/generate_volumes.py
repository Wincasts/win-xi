#!/usr/bin/env python3
"""Generate low/high copies of root-level PCM WAVs; originals remain the medium sounds.

Run after generate.py/generate_voices.sh, or after adding a custom WAV. Low is -6 dB;
high is up to +3 dB, limited by each file's peak headroom to avoid clipping.
Only the low/ and high/ copies are overwritten, never the originals.
"""
import math
from pathlib import Path
import wave

GAINS = {'low': 10 ** (-6 / 20), 'high': 10 ** (3 / 20)}


def generate(source, destination, level):
    with wave.open(str(source), 'rb') as wav:
        params = wav.getparams()
        width = wav.getsampwidth()
        if wav.getcomptype() != 'NONE' or width not in (1, 2, 3, 4):
            raise ValueError(f'{source}: expected 8/16/24/32-bit PCM WAV')
        frames = wav.readframes(wav.getnframes())
    # 8-bit PCM is unsigned; the other widths are signed little-endian.
    samples = [int.from_bytes(frames[i:i + width], 'little', signed=width != 1)
               - (128 if width == 1 else 0) for i in range(0, len(frames), width)]
    limit = 2 ** (width * 8 - 1) - 1
    peak = max((abs(sample) for sample in samples), default=0)
    gain = GAINS[level]
    if level == 'high' and peak:
        gain = min(gain, limit / peak)
    output = bytearray()
    for sample in samples:
        value = max(-limit - 1, min(limit, round(sample * gain)))
        output.extend((value + (128 if width == 1 else 0)).to_bytes(
            width, 'little', signed=width != 1))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), 'wb') as wav:
        wav.setparams(params)
        wav.writeframes(output)
    return gain


def main():
    folder = Path(__file__).resolve().parent
    sources = sorted(folder.glob('*.wav'))
    for source in sources:
        for level in GAINS:
            gain = generate(source, folder / level / source.name, level)
            print(f'{level}/{source.name}: {20 * math.log10(gain):+.2f} dB')
    print(f'Generated {len(sources) * len(GAINS)} copies; medium originals unchanged.')


if __name__ == '__main__':
    main()
