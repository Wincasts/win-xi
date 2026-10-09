# Checks

    ./tests/run.sh

Each check loads an addon, or a part of winxi, against `harness.lua` (a stand-in for Ashita: imgui, the
settings library, the game's memory and the rest are stubs that do little and count what they are asked)
and prints what it finds, a claim to a line. A line ending in `false`, or an error, is something to look
at.

They show that the code loads, runs and takes the paths expected: an addon brings its settings over,
draws its window, answers its command, takes and gives back the controller, sends the packets it should.
They do not show that anything looks right, or that the game behaves as the stubs do.

To add one: a `<name>_check.lua` that works the addon through the table `H` (see the end of
`harness.lua` for what it offers), and a line in `run.sh`.
