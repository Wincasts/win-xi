#!/usr/bin/env python3
"""Makes the plain sounds that come with winxi.sound: open, move, tab, confirm, back and error.

They are short tones, made here so that there is something to hear without borrowing the game's own
files. Run it in this folder to make them again; put any wav of the same name in their place to change
one.
"""
import math
import os
import struct
import wave

RATE = 22050
VOLUME = 0.22


def tone(frequency, end_frequency, seconds, decay):
    """A sine sliding from one pitch to another, dying away."""
    samples = []
    phase = 0.0
    count = int(RATE * seconds)
    for i in range(count):
        t = i / count
        phase += 2 * math.pi * (frequency + (end_frequency - frequency) * t) / RATE
        attack = min(1.0, i / (RATE * 0.003))
        samples.append(math.sin(phase) * attack * math.exp(-decay * t))
    return samples


def silence(seconds):
    return [0.0] * int(RATE * seconds)


SOUNDS = {
    'open': tone(660, 660, 0.04, 2) + tone(880, 880, 0.04, 2) + tone(1175, 1175, 0.1, 5),
    'move': tone(1400, 1400, 0.035, 6),
    'tab': tone(520, 1040, 0.07, 3),
    'confirm': tone(880, 880, 0.045, 3) + tone(1320, 1320, 0.09, 5),
    'back': tone(700, 470, 0.09, 4),
    'error': tone(200, 200, 0.06, 2) + silence(0.03) + tone(200, 200, 0.08, 3),
}

here = os.path.dirname(os.path.abspath(__file__))
for name, samples in SOUNDS.items():
    with wave.open(os.path.join(here, name + '.wav'), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(s * VOLUME * 32767)) for s in samples))
