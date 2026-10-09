#!/usr/bin/env python3
"""Makes the sounds that come with chime, one for each event it knows.

They are short tones, made here so that there is something to hear without borrowing anyone's files.
Run it in this folder to make them again. Any other wav put in this folder can be chosen for an event
in the settings.
"""
import math
import os
import struct
import wave

RATE = 22050
VOLUME = 0.3


def tone(frequency, end_frequency, seconds, decay):
    """A sine sliding from one pitch to another, dying away, with a little of the octave above."""
    samples = []
    phase = 0.0
    count = int(RATE * seconds)
    for i in range(count):
        t = i / count
        phase += 2 * math.pi * (frequency + (end_frequency - frequency) * t) / RATE
        attack = min(1.0, i / (RATE * 0.004))
        samples.append((math.sin(phase) + 0.25 * math.sin(2 * phase)) / 1.25 * attack * math.exp(-decay * t))
    return samples


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def together(*parts):
    """Several sounds at once."""
    out = [0.0] * max(len(p) for p in parts)
    for part in parts:
        for i, sample in enumerate(part):
            out[i] += sample / len(parts)
    return out


SOUNDS = {
    # two soft rising notes: someone is speaking to you
    'tell': tone(784, 784, 0.09, 3) + tone(1047, 1047, 0.22, 5),
    # one light note: your name came up
    'mention': tone(1319, 1319, 0.05, 3) + tone(1319, 1319, 0.16, 6),
    # three rising notes: an invitation
    'invite': tone(659, 659, 0.08, 3) + tone(784, 784, 0.08, 3) + tone(988, 988, 0.25, 5),
    # a bright chord swept upward: burst now
    'skillchain': together(tone(880, 1760, 0.3, 4), tone(1109, 2217, 0.3, 4), tone(1319, 2637, 0.3, 4)),
    # a quick rise: TP is ready
    'tp': tone(523, 1047, 0.08, 2) + tone(1047, 1047, 0.14, 6),
    # two low urgent beats: HP is low
    'lowhp': tone(330, 300, 0.11, 3) + silence(0.05) + tone(330, 300, 0.16, 4),
    # two falling notes: MP is low
    'lowmp': tone(698, 698, 0.09, 3) + tone(523, 494, 0.2, 5),
    # a long low falling note: someone is down
    'ko': tone(392, 196, 0.5, 3),
}

here = os.path.dirname(os.path.abspath(__file__))
for name, samples in SOUNDS.items():
    with wave.open(os.path.join(here, name + '.wav'), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s)) * VOLUME * 32767)) for s in samples))
