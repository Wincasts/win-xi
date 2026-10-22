#!/usr/bin/env python3
"""padkey: a controller button that presses a keyboard key, for Discord's Toggle Mute.

Reads the Victrix Pro BFG (PS5 mode) raw from its hidraw node, which the game reads
too through Proton's hidraw passthrough, and presses a key on a virtual keyboard
(uinput) while the button is held. The button still reaches the game, so leave it
unbound there.

    padkey.py                      PS presses F19
    padkey.py --button touchpad --key KEY_F18
    padkey.py --debug              print each press

The input report (id 1): six axis bytes, a vendor byte, then the hat in the low four
bits of byte 8 and the 14 buttons from its bit 4 on; PS is button 13 (byte 10 bit 0),
the touchpad button 14 (byte 10 bit 1).
"""
import argparse, glob, os, select, sys, time
from evdev import UInput, ecodes

BUTTONS = {"square": 0, "cross": 1, "circle": 2, "triangle": 3, "l1": 4, "r1": 5,
           "l2": 6, "r2": 7, "create": 8, "options": 9, "l3": 10, "r3": 11,
           "ps": 12, "touchpad": 13}
DEVICE = "/dev/input/by-id/usb-Performance_Designed_Products_Victrix_Pro_BFG*-hidraw"

def held(report, index):
    bit = 4 + index
    return report[8 + bit // 8] >> (bit % 8) & 1

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--button", default="ps", choices=BUTTONS)
    p.add_argument("--key", default="KEY_F19")
    p.add_argument("--device", default=DEVICE)
    p.add_argument("--debug", action="store_true")
    a = p.parse_args()
    key = ecodes.ecodes[a.key]
    index = BUTTONS[a.button]
    ui = UInput({ecodes.EV_KEY: [key]}, name="padkey")
    while True:
        paths = glob.glob(a.device)
        if not paths:
            time.sleep(2)
            continue
        try:
            fd = os.open(paths[0], os.O_RDONLY)
        except OSError as e:
            print(f"padkey: {paths[0]}: {e}", file=sys.stderr)
            time.sleep(2)
            continue
        if a.debug:
            print(f"padkey: reading {os.path.realpath(paths[0])}, {a.button} -> {a.key}")
        down = 0
        try:
            while True:
                select.select([fd], [], [])
                r = os.read(fd, 128)
                if len(r) < 11 or r[0] != 1:
                    continue
                now = held(r, index)
                if now != down:
                    down = now
                    ui.write(ecodes.EV_KEY, key, down)
                    ui.syn()
                    if a.debug:
                        print(f"padkey: {a.button} {'down' if down else 'up'}", flush=True)
        except OSError:
            # The pad went away (asleep, unplugged): let go of the key and wait for it.
            if down:
                ui.write(ecodes.EV_KEY, key, 0)
                ui.syn()
            os.close(fd)
            time.sleep(2)

if __name__ == "__main__":
    main()
