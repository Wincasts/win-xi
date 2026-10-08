#!/usr/bin/env bash
# Moves addons between this project folder and the live Ashita install.
#
#   ./deploy.sh status            every addon here, and how it differs from live
#   ./deploy.sh diff <addon>      the files that differ, and their changes line by line
#   ./deploy.sh push <addon>      copy the project copy to live, after showing what will change
#   ./deploy.sh rollback <addon>  put back the files the last push replaced
#   ./deploy.sh pull <addon>      copy the live copy into the project folder
#
# A shared library under addons/libs is named with its folder: ./deploy.sh push libs/xiui
#
# push and rollback are the only commands that write to the live install. Both show what they are
# about to do and wait for "y", and both refuse to run unless a person is at the terminal.
# Every file a push replaces is first kept under deploy-backups/<addon>/<time>/.
# Nothing is ever deleted from live: a file that exists only there is listed, and left alone.

set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${ASHITA_LIVE:-$HOME/Games/PhoenixXI}"
BACKUPS="$PROJECT/deploy-backups"
# Repository and build leftovers that have no business in a live addon folder
EXCLUDES=(--exclude=.git/ --exclude=.github/ --exclude=.gitignore --exclude=__pycache__/ --exclude='*.pyc')

die() { echo "deploy: $*" >&2; exit 1; }

# The folder holding an addon's files in the project: addons/<name>, or addons/<name>/<name> for one
# kept a level down beside its other material. It is the one with <name>.lua in it.
source_dir() {
    local name="$1"
    # a shared library is its whole folder
    if [[ "$name" == libs/?* && -d "$PROJECT/addons/$name" ]]; then
        echo "$PROJECT/addons/$name"
    elif [[ -f "$PROJECT/addons/$name/$name.lua" ]]; then
        echo "$PROJECT/addons/$name"
    elif [[ -f "$PROJECT/addons/$name/$name/$name.lua" ]]; then
        echo "$PROJECT/addons/$name/$name"
    else
        return 1
    fi
}

live_dir() { echo "$LIVE/addons/$1"; }

# Files that a copy from $1 to $2 would add or replace, one per line: "new <path>" or "changed <path>"
pending() {
    rsync -rcn --itemize-changes "${EXCLUDES[@]}" "$1/" "$2/" 2>/dev/null |
        awk '$1 ~ /^>f\+/ { $1 = ""; print "new    " substr($0, 2); next }
             $1 ~ /^>f/   { $1 = ""; print "changed" substr($0, 1) }'
}

# Files in $2 that $1 does not have
only_in() {
    rsync -rn --itemize-changes --ignore-existing "${EXCLUDES[@]}" "$2/" "$1/" 2>/dev/null |
        awk '$1 ~ /^>f/ { $1 = ""; print substr($0, 2) }'
}

need_addon() {
    [[ $# -ge 1 && -n "$1" ]] || die "which addon? (see: ./deploy.sh status)"
    SRC="$(source_dir "$1")" || die "no addon '$1' in $PROJECT/addons (looked for $1.lua)"
    DST="$(live_dir "$1")"
}

# What to do in game for a change to take effect
reload_hint() {
    if [[ "$1" == libs/* ]]; then
        echo "In game: reload each addon that uses ${1#libs/} (/addon reload <addon>)"
    else
        echo "In game: /addon reload $1"
    fi
}

confirm() {
    [[ -t 0 ]] || die "this step needs a person at the terminal to confirm it"
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" == y || "$answer" == Y ]]
}

cmd_status() {
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"
    printf '%-16s %s\n' ADDON STATE
    local dir name src dst changes extra
    for dir in "$PROJECT"/addons/*/ "$PROJECT"/addons/libs/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        [[ "$dir" == "$PROJECT"/addons/libs/*/ ]] && name="libs/$name"
        [[ "$name" == libs ]] && continue
        src="$(source_dir "$name")" || { printf '%-16s %s\n' "$name" "(no $name.lua here: not an addon, skipped)"; continue; }
        dst="$(live_dir "$name")"
        if [[ ! -d "$dst" ]]; then
            printf '%-16s %s\n' "$name" "not in live yet"
            continue
        fi
        changes="$(pending "$src" "$dst" | wc -l)"
        extra="$(only_in "$src" "$dst" | wc -l)"
        if [[ "$changes" -eq 0 ]]; then
            printf '%-16s %s' "$name" "same as live"
        else
            printf '%-16s %s' "$name" "$changes file(s) to push"
        fi
        [[ "$extra" -gt 0 ]] && printf '  (%s file(s) only in live)' "$extra"
        printf '\n'
    done
}

cmd_diff() {
    need_addon "$@"
    [[ -d "$DST" ]] || { echo "$1 is not in live yet: a push would add all of it."; return; }

    local list
    list="$(pending "$SRC" "$DST")"
    if [[ -z "$list" ]]; then
        echo "$1: project and live are the same."
    else
        echo "$1: project -> live"
        echo "$list" | sed 's/^/  /'
        echo
        local kind path
        while read -r kind path; do
            [[ "$kind" == changed ]] || continue
            # text files only; anything else is just named above
            if grep -Iq . "$SRC/$path" 2>/dev/null; then
                command diff -u --label "live/$path" --label "project/$path" "$DST/$path" "$SRC/$path" || true
            fi
        done <<< "$list"
    fi

    local extra
    extra="$(only_in "$SRC" "$DST")"
    if [[ -n "$extra" ]]; then
        echo
        echo "Only in live (never touched by a push):"
        echo "$extra" | sed 's/^/  /'
    fi
}

cmd_push() {
    need_addon "$@"
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"

    local list
    list="$(pending "$SRC" "$DST")"
    if [[ -z "$list" ]]; then
        echo "$1: nothing to push, live already matches."
        return
    fi

    echo "$1: about to copy into $DST"
    echo "$list" | sed 's/^/  /'
    confirm "Push these to live?" || { echo "Nothing was changed."; return; }

    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$BACKUPS/$1/$stamp"
    mkdir -p "$backup" "$DST"
    rsync -rc --times --backup --backup-dir="$backup" "${EXCLUDES[@]}" "$SRC/" "$DST/"

    # what was newly added, so that a rollback can say so
    echo "$list" | awk '$1 == "new" { $1 = ""; print substr($0, 2) }' > "$backup/.added"

    echo "Pushed. Replaced files are kept in deploy-backups/$1/$stamp"
    reload_hint "$1"
}

cmd_rollback() {
    need_addon "$@"
    local latest
    latest="$(find "$BACKUPS/$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)"
    [[ -n "$latest" ]] || die "no push of '$1' has been backed up"

    echo "$1: about to restore into $DST from $(basename "$latest"):"
    (cd "$latest" && find . -type f ! -name .added | sed 's|^\./|  |')
    if [[ -s "$latest/.added" ]]; then
        echo "That push also added these, which a rollback leaves in place:"
        sed 's/^/  /' "$latest/.added"
    fi
    confirm "Restore these in live?" || { echo "Nothing was changed."; return; }

    rsync -r --times --exclude=.added "$latest/" "$DST/"
    mv "$latest" "$latest.restored"
    echo "Restored."
    reload_hint "$1"
}

cmd_pull() {
    [[ $# -ge 1 && -n "$1" ]] || die "which addon?"
    local name="$1" src dst
    src="$(live_dir "$name")"
    [[ -d "$src" ]] || die "no addon '$name' in $LIVE/addons"
    dst="$(source_dir "$name" 2>/dev/null || echo "$PROJECT/addons/$name")"

    local list
    list="$(pending "$src" "$dst")"
    if [[ -z "$list" ]]; then
        echo "$name: the project copy already has everything live has."
        return
    fi

    echo "$name: about to copy from live into $dst"
    echo "$list" | sed 's/^/  /'
    echo "Files marked 'changed' will be overwritten in the project folder."
    confirm "Pull these into the project?" || { echo "Nothing was changed."; return; }

    mkdir -p "$dst"
    rsync -rc --times "${EXCLUDES[@]}" "$src/" "$dst/"
    echo "Pulled."
}

case "${1:-}" in
    status)   cmd_status ;;
    diff)     shift; cmd_diff "$@" ;;
    push)     shift; cmd_push "$@" ;;
    rollback) shift; cmd_rollback "$@" ;;
    pull)     shift; cmd_pull "$@" ;;
    *)        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
esac
