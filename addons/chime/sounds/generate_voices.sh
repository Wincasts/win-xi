#!/usr/bin/env bash
# Makes the spoken sounds that come with chime, voice-<event>.wav, one for each event.
#
# They are spoken by Piper (https://github.com/OHF-Voice/piper1-gpl), a text-to-speech program, with
# its voice en_US-amy-medium, then trimmed of the silence at either end and brought to one loudness
# with ffmpeg. Piper is not part of the addon: this is only run to make the files again.
#
#   PIPER=/path/to/piper VOICE=/path/to/en_US-amy-medium.onnx ./generate_voices.sh
#
# The words are written as they are to be said: letters said one at a time are set apart.
set -euo pipefail
PIPER="${PIPER:-$HOME/.cache/chime-voices/venv/bin/piper}"
VOICE="${VOICE:-$HOME/.cache/chime-voices/voices/en_US-amy-medium.onnx}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
raw="$(mktemp -d)"
trap 'rm -rf "$raw"' EXIT

say() {
    echo "$2" | "$PIPER" -m "$VOICE" -f "$raw/$1.wav" >/dev/null 2>&1
    ffmpeg -hide_banner -loglevel error -y -i "$raw/$1.wav" -af \
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,loudnorm=I=-16:TP=-1.5:LRA=7,afade=t=in:d=0.005" \
        -ar 22050 -ac 1 -c:a pcm_s16le "$here/voice-$1.wav"
}

say tell       "Tell."
say mention    "Mentioned."
say invite     "Invite."
say skillchain "Skillchain."
say tp         "T P ready."
say lowhp      "Low H P."
say lowmp      "Low M P."
say ko         "Member down."
