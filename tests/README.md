# Checks

    ./tests/run.sh

Each check loads an addon, or a part of winxi, against `harness.lua` (a stand-in for Ashita: imgui, the
settings library, the game's memory and the rest are stubs that do little and count what they are asked)
and prints what it finds, a claim to a line. A check fails when a line ends in `false` or it stops with an
error (exits non-zero). Every check runs even after one fails; `run.sh` then lists the failures, each with
its line in the output, and exits 1. It ends with `== every check passed` and exits 0 otherwise.

They show that the code loads, runs and takes the paths expected: an addon brings its settings over,
draws its window, answers its command, takes and gives back the controller, sends the packets it should.
They do not show that anything looks right, or that the game behaves as the stubs do.

To add one: a `<name>_check.lua` that works the addon through the table `H` (see the end of
`harness.lua` for what it offers), and a line in `run.sh`.

## What is drawn, and what it costs

`capture.lua` runs an addon on the harness and records every call it makes on a draw list. `run.sh`
does so for winparty, over a scene (`party_scene.lua`: a full alliance, pets, a target, an
invite and treasure, from a character's saved settings) and compares the record with the copy kept
in `golden/`: a change to the code that is not meant to change what is drawn should leave it as kept.

    ./tests/run.sh keep       keep what is drawn now as the copy, after a change that is meant to alter it
    ./tests/run.sh measure    what one frame of the scene costs: calls, changes of image, colours packed, memory

