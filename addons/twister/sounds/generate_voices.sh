#!/usr/bin/env bash
# Makes the spoken sounds that come with twister, one for each event and one for triggers to start
# with, in two voices: a woman's, voicef-<event>.wav, and a man's, voicem-<event>.wav.
#
# They are spoken by Piper (https://github.com/OHF-Voice/piper1-gpl), a text-to-speech program, with
# its voices en_US-amy-medium (hers) and en_US-ryan-high (his), then trimmed of the silence at either
# end and brought to one loudness with ffmpeg. Piper is not part of the addon: this is only run to
# make the files again.
#
#   PIPER=/path/to/piper VOICES=/folder/of/voices ./generate_voices.sh [event ...]
#   WHOSE=m ./generate_voices.sh        only his (f: only hers)
#
# With events named, only theirs are made, and with WHOSE only that voice's: the program does not say
# a thing the same way twice, so making them all again changes every file.
#
# The words are written as they are to be said: letters said one at a time are set apart.
set -euo pipefail
PIPER="${PIPER:-$HOME/.cache/chime-voices/venv/bin/piper}"
VOICES="${VOICES:-$HOME/.cache/chime-voices/voices}"
WHOSE="${WHOSE:-f m}"
declare -A voice=( [f]="en_US-amy-medium" [m]="en_US-ryan-high" )
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
raw="$(mktemp -d)"
trap 'rm -rf "$raw"' EXIT

only=" $* "
say() {
    [[ "$only" == "  " || "$only" == *" $1 "* ]] || return 0
    local who
    for who in $WHOSE; do
        echo "$2" | "$PIPER" -m "$VOICES/${voice[$who]}.onnx" -f "$raw/$who-$1.wav" >/dev/null 2>&1
        ffmpeg -hide_banner -loglevel error -y -i "$raw/$who-$1.wav" -af \
            "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,loudnorm=I=-16:TP=-1.5:LRA=7,afade=t=in:d=0.005" \
            -ar 22050 -ac 1 -c:a pcm_s16le "$here/voice$who-$1.wav"
    done
}

say tell       "Tell."
say mention    "Mentioned."
say invite     "Invite."
say trade      "Trade."
say examine    "Examined."
say tp         "T P ready."
say lowhp      "Low H P."
say lowmp      "Low M P."
say ko         "Member down."
say skillup    "Skill up."
say drop       "Item drop."
say trigger    "Heads up."
# and one that is no event's: the addon's own name
say twister    "Twister."
