#!/usr/bin/env python3
"""Makes the plain sounds that come with winxi.sound: open, move, tab, confirm, back and error.

Each is one short, soft blip at a pitch of its own, made here so that there is something to hear
without borrowing the game's own files. Run it in this folder to make them again; put any wav of the same name in their place to change
one.
"""
import math
import os
import struct
import wave

RATE = 22050
VOLUME = 0.15


def blip(frequency, seconds):
    """A sine at one pitch, rising in 2 ms and dying away to nothing by its end."""
    samples = []
    count = int(RATE * seconds)
    for i in range(count):
        t = i / count
        attack = min(1.0, i / (RATE * 0.002))
        samples.append(math.sin(2 * math.pi * frequency * i / RATE) * attack * (1 - t) ** 3)
    return samples


SOUNDS = {
    'open': blip(1050, 0.06),
    'move': blip(1200, 0.025),
    'tab': blip(900, 0.04),
    'confirm': blip(1400, 0.05),
    'back': blip(700, 0.05),
    'error': blip(220, 0.09),
}

here = os.path.dirname(os.path.abspath(__file__))
for name, samples in SOUNDS.items():
    with wave.open(os.path.join(here, name + '.wav'), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(s * VOLUME * 32767)) for s in samples))
