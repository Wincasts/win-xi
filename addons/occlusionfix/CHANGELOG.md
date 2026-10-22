# occlusionfix changelog

## 1.0 — first release

- Characters near walls, door frames and counters no longer blink out of view: the game's occlusion test, which counts them as covered when they are not, is turned off for characters, and the depth buffer decides what is seen.
- `/occlusionfix [on|off]`; unloading puts the game back.
