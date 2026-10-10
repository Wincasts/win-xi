#!/usr/bin/env python3
"""Makes the tones that come with twister: two for each event it knows, and two for triggers.

They are short tones, made here so that there is something to hear without borrowing anyone's files.
The first of each, <event>.wav, is plain notes. The second, tone-<event>2.wav, is the same event said
another way, on bells: something else to choose where the first does not suit.
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


def bell(frequency, seconds, decay=4):
    """A struck note: the pitch with the overtones of a bell above it, which die away sooner than it does."""
    samples = []
    count = int(RATE * seconds)
    for i in range(count):
        t = i / count
        time = i / RATE
        attack = min(1.0, i / (RATE * 0.002))
        sample = (math.sin(2 * math.pi * frequency * time) * math.exp(-decay * t)
                  + 0.45 * math.sin(2 * math.pi * frequency * 2.76 * time) * math.exp(-decay * 2.5 * t)
                  + 0.2 * math.sin(2 * math.pi * frequency * 5.4 * time) * math.exp(-decay * 5 * t))
        samples.append(sample / 1.65 * attack)
    return samples


def together(*parts):
    """Several sounds at once."""
    out = [0.0] * max(len(p) for p in parts)
    for part in parts:
        for i, sample in enumerate(part):
            out[i] += sample / len(parts)
    return out


def after(seconds, samples):
    """A sound that waits before it starts: for laying one over the end of another."""
    return silence(seconds) + samples


SOUNDS = {
    # two soft rising notes: someone is speaking to you
    'tell': tone(784, 784, 0.09, 3) + tone(1047, 1047, 0.22, 5),
    # one light note: your name came up
    'mention': tone(1319, 1319, 0.05, 3) + tone(1319, 1319, 0.16, 6),
    # three rising notes: an invitation
    'invite': tone(659, 659, 0.08, 3) + tone(784, 784, 0.08, 3) + tone(988, 988, 0.25, 5),
    # a note, the one above it, and the first again: something offered across
    'trade': tone(880, 880, 0.08, 3) + tone(1109, 1109, 0.08, 3) + tone(880, 880, 0.22, 5),
    # a slide up and a slide back down: someone looking you over
    'examine': tone(660, 990, 0.12, 2) + tone(990, 660, 0.2, 4),
    # a quick rise: TP is ready
    'tp': tone(523, 1047, 0.08, 2) + tone(1047, 1047, 0.14, 6),
    # two low urgent beats: HP is low
    'lowhp': tone(330, 300, 0.11, 3) + silence(0.05) + tone(330, 300, 0.16, 4),
    # two falling notes: MP is low
    'lowmp': tone(698, 698, 0.09, 3) + tone(523, 494, 0.2, 5),
    # a long low falling note: someone is down
    'ko': tone(392, 196, 0.5, 3),
    # four quick steps up: a skill has risen
    'skillup': tone(784, 784, 0.05, 2) + tone(988, 988, 0.05, 2) + tone(1175, 1175, 0.05, 2) + tone(1568, 1568, 0.18, 6),
    # three notes falling and a bright one after: something has dropped, and it is the one
    'drop': tone(1319, 1319, 0.06, 2) + tone(1047, 1047, 0.06, 2) + tone(784, 784, 0.06, 2) + tone(1568, 1568, 0.22, 5),
    # three sharp beats on one high note: a trigger, something a mob has begun
    'trigger': tone(1760, 1760, 0.06, 4) + silence(0.03) + tone(1760, 1760, 0.06, 4) + silence(0.03) + tone(1760, 1760, 0.14, 6),
}

# The second tone of each, on bells
SECOND = {
    # two bells, the second a third up and ringing on: someone at the door
    'tell': bell(1047, 0.12) + bell(1319, 0.4, 5),
    # one high bell left to ring: your name
    'mention': bell(1760, 0.45, 5),
    # four bells climbing, each begun before the last is done: come along
    'invite': together(bell(523, 0.5, 6), after(0.08, bell(659, 0.5, 6)), after(0.16, bell(784, 0.5, 6)), after(0.24, bell(1047, 0.5, 5))),
    # a bell and the one a fourth above it, twice over: this for that
    'trade': bell(698, 0.1) + bell(932, 0.1) + bell(698, 0.1) + bell(932, 0.3, 5),
    # two soft low bells, the same: looked at, and looked at again
    'examine': bell(587, 0.16, 5) + silence(0.04) + bell(587, 0.32, 5),
    # three bells struck as one, a bright chord: ready
    'tp': together(bell(784, 0.5, 5), bell(988, 0.5, 5), bell(1175, 0.5, 5)),
    # three low bells, each a little lower: going
    'lowhp': bell(294, 0.14, 3) + bell(277, 0.14, 3) + bell(262, 0.3, 4),
    # three bells coming down a chord: draining
    'lowmp': bell(880, 0.12) + bell(659, 0.12) + bell(523, 0.34, 5),
    # two low bells a step apart, struck as one and left to die: down
    'ko': together(bell(196, 0.8, 4), bell(185, 0.8, 4)),
    # four quick bells up a chord, the top one ringing: better at it
    'skillup': bell(1047, 0.06) + bell(1319, 0.06) + bell(1568, 0.06) + bell(2093, 0.36, 5),
    # a high bell, a lower, and the high one again over it: there it is
    'drop': together(bell(2093, 0.5, 6), after(0.09, bell(1568, 0.5, 6)), after(0.18, bell(2093, 0.5, 5))),
    # two bells a third apart, to and fro, twice: look out
    'trigger': bell(1480, 0.09, 3) + bell(1175, 0.09, 3) + bell(1480, 0.09, 3) + bell(1175, 0.26, 5),
}


def write(name, samples):
    with wave.open(os.path.join(here, name + '.wav'), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s)) * VOLUME * 32767)) for s in samples))


here = os.path.dirname(os.path.abspath(__file__))
for name, samples in SOUNDS.items():
    write(name, samples)
for name, samples in SECOND.items():
    # brought to one loudness: bells laid over each other come out quieter than bells one after another
    peak = max(abs(sample) for sample in samples)
    write('tone-%s2' % name, [sample / peak * 0.88 for sample in samples])
