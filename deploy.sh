#!/usr/bin/env bash
# Moves addons between this project folder and the live Ashita install.
#
#   ./deploy.sh [flags] status            every addon here, and how it differs from live
#   ./deploy.sh [flags] diff <addon>      the files that differ, and their changes line by line
#   ./deploy.sh [flags] push <addon>      copy the project copy to live, after showing what will change
#   ./deploy.sh [flags] rollback <addon>  put back the files the last push replaced
#   ./deploy.sh [flags] pull <addon>      copy the live copy into the project folder
#
# Flags go before the command:
#   -y, --yes   skip the "y" question
#   -a, --all   with push or diff: every addon and library that differs from live, in place of a name
#
#   ./deploy.sh -a push       push everything that has changed, after one question
#   ./deploy.sh -y -a push    the same, without the question
#
# A shared library under addons/libs is named with its folder: ./deploy.sh push libs/winxi
# With -a, libraries are pushed before the addons that use them.
#
# push and rollback are the only commands that write to the live install. Both show what they are
# about to do and wait for "y" (unless given -y), and both refuse to run unless a person is at the
# terminal, with or without -y.
# Every file a push replaces is first kept under deploy-backups/<addon>/<time>/.
# Nothing is ever deleted from live: a file that exists only there is listed, and left alone.

set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${ASHITA_LIVE:-$HOME/Games/PhoenixXI}"
BACKUPS="${DEPLOY_BACKUPS:-$PROJECT/deploy-backups}"
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
    # -y answers the question, but the step is still only for a person at the terminal
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        echo "$1 yes (-y)"
        return 0
    fi
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" == y || "$answer" == Y ]]
}

# The name of every folder under addons, and of every library under addons/libs (as libs/<name>).
# Libraries first, so that when all are pushed they land before the addons that use them.
all_names() {
    local dir
    for dir in "$PROJECT"/addons/libs/*/; do
        [[ -d "$dir" ]] && echo "libs/$(basename "$dir")"
    done
    for dir in "$PROJECT"/addons/*/; do
        [[ -d "$dir" && "$(basename "$dir")" != libs ]] && basename "$dir"
    done
    return 0
}

# The names, from all_names, of everything that a push would change
changed_names() {
    local name src
    while read -r name; do
        src="$(source_dir "$name")" || continue
        [[ -n "$(pending "$src" "$(live_dir "$name")")" ]] && echo "$name"
    done < <(all_names)
    return 0
}

cmd_status() {
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"
    printf '%-16s %s\n' ADDON STATE
    local name src dst changes extra
    while read -r name; do
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
    done < <(all_names)
}

# diff for everything that differs from live
cmd_diff_all() {
    local names name
    names="$(changed_names)"
    if [[ -z "$names" ]]; then
        echo "Nothing differs from live."
        return
    fi
    while read -r name; do
        cmd_diff "$name"
        echo
    done <<< "$names"
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

# Copies one addon or library to live, keeping what it replaces. The asking is done by the caller.
# $1 is its name and $2 the list from pending.
do_push() {
    local name="$1" list="$2" src dst stamp backup
    src="$(source_dir "$name")"
    dst="$(live_dir "$name")"

    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$BACKUPS/$name/$stamp"
    mkdir -p "$backup" "$dst"
    rsync -rc --times --backup --backup-dir="$backup" "${EXCLUDES[@]}" "$src/" "$dst/"

    # what was newly added, so that a rollback can say so
    echo "$list" | awk '$1 == "new" { $1 = ""; print substr($0, 2) }' > "$backup/.added"

    echo "Pushed $name. Replaced files are kept in deploy-backups/$name/$stamp"
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

    do_push "$1" "$list"
    reload_hint "$1"
}

# push for everything that differs from live: all of it shown, then one question for the lot
cmd_push_all() {
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"

    local names name
    names="$(changed_names)"
    if [[ -z "$names" ]]; then
        echo "Nothing to push: live already matches everything here."
        return
    fi

    while read -r name; do
        echo "$name: about to copy into $(live_dir "$name")"
        pending "$(source_dir "$name")" "$(live_dir "$name")" | sed 's/^/  /'
    done <<< "$names"
    confirm "Push all of these to live?" || { echo "Nothing was changed."; return; }

    local addons=()
    while read -r name; do
        do_push "$name" "$(pending "$(source_dir "$name")" "$(live_dir "$name")")"
        [[ "$name" != libs/* ]] && addons+=("$name")
    done <<< "$names"

    echo
    if [[ "$names" == *libs/* ]]; then
        echo "A library changed: in game, reload every addon that uses it."
    fi
    for name in "${addons[@]+"${addons[@]}"}"; do
        echo "In game: /addon reload $name"
    done
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

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Flags come first, before the command: ./deploy.sh -y -a push
ASSUME_YES=0
ALL=0
while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        -a|--all) ALL=1 ;;
        -ya|-ay)  ASSUME_YES=1; ALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *)        die "unknown flag '$1' (flags are -y and -a)" ;;
    esac
    shift
done

# anything flag-like after the command is a flag in the wrong place, not an addon's name
for arg in "$@"; do
    [[ "$arg" == -* ]] && die "flags go before the command: ./deploy.sh $arg ${1:-push} ..."
done

COMMAND="${1:-}"
[[ $# -gt 0 ]] && shift

if [[ "$ALL" -eq 1 ]]; then
    [[ $# -eq 0 ]] || die "-a takes the place of a name: leave out '$1'"
    case "$COMMAND" in
        push)   cmd_push_all ;;
        diff)   cmd_diff_all ;;
        status) cmd_status ;;
        *)      die "-a goes with push or diff" ;;
    esac
    exit 0
fi

case "$COMMAND" in
    status)   cmd_status ;;
    diff)     cmd_diff "$@" ;;
    push)     cmd_push "$@" ;;
    rollback) cmd_rollback "$@" ;;
    pull)     cmd_pull "$@" ;;
    *)        usage ;;
esac
