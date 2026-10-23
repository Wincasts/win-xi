#!/usr/bin/env bash
# Moves addons, plugins and uihook's skins between this project folder and the live Ashita install.
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
#   ./deploy.sh -a push       push everything that has changed: listed, then pushed, with no question
#
# A shared library under addons/libs is named with its folder: ./deploy.sh push libs/winxi
# A plugin is named plugins/<name>: its build, plugins/<name>/build/<name>.dll, to the live plugins/<name>.dll
# (./deploy.sh push plugins/uihook). With -a, only the plugins live already has: a new one is pushed by name.
# A uihook skin is named skins/<name>: plugins/uihook/build/skins/<name>/ (as tools/uihook_skin.py makes it) to the
# live config/uihook/skins/<name>/ (./deploy.sh push skins/winxi).
# With -a, libraries are pushed first, then plugins and skins, then the addons.
#
# Addons are looked for in addons/, then in forks/addons/ (other people's addons with changes of ours).
#
# push and rollback are the only commands that write to the live install. Both show what they are
# about to do; push of one addon and rollback wait for "y" (unless given -y). Both refuse to
# run unless a person is at the terminal, -a push and -y included.
# Every file a push replaces is first kept under deploy-backups/<addon>/<time>/.
# Nothing is ever deleted from live: a file that exists only there is listed, and left alone.

set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${ASHITA_LIVE:-$HOME/Games/PhoenixXI}"
BACKUPS="${DEPLOY_BACKUPS:-$PROJECT/deploy-backups}"
# Repository and build leftovers that have no business in a live addon folder
EXCLUDES=(--exclude=.git/ --exclude=.github/ --exclude=.gitignore --exclude=__pycache__/ --exclude='*.pyc')
# What of a folder a name moves: an addon, library or skin all of it; a plugin its .dll alone (its build folder and
# the live plugins folder hold others')
filters() {
    if [[ "$1" == plugins/?* ]]; then
        echo "--include=${1#plugins/}.dll --exclude=*"
    else
        echo "${EXCLUDES[*]}"
    fi
}

die() { echo "deploy: $*" >&2; exit 1; }

# Where addons are kept in the project: our own first, then the forks of other people's
ADDON_ROOTS=("$PROJECT/addons" "$PROJECT/forks/addons")

# The folder holding an addon's files in the project: <root>/<name>, or <root>/<name>/<name> for one
# kept a level down beside its other material. It is the one with <name>.lua in it.
source_dir() {
    local name="$1" root
    # a plugin's build folder, with its .dll in it
    if [[ "$name" == plugins/?* ]]; then
        local plugin="${name#plugins/}"
        [[ -f "$PROJECT/plugins/$plugin/build/$plugin.dll" ]] && { echo "$PROJECT/plugins/$plugin/build"; return 0; }
        return 1
    fi
    # a uihook skin, as tools/uihook_skin.py makes it
    if [[ "$name" == skins/?* ]]; then
        [[ -d "$PROJECT/plugins/uihook/build/$name" ]] && { echo "$PROJECT/plugins/uihook/build/$name"; return 0; }
        return 1
    fi
    # a shared library is its whole folder
    if [[ "$name" == libs/?* && -d "$PROJECT/addons/$name" ]]; then
        echo "$PROJECT/addons/$name"
        return 0
    fi
    for root in "${ADDON_ROOTS[@]}"; do
        if [[ -f "$root/$name/$name.lua" ]]; then
            echo "$root/$name"
            return 0
        elif [[ -f "$root/$name/$name/$name.lua" ]]; then
            echo "$root/$name/$name"
            return 0
        fi
    done
    return 1
}

live_dir() {
    case "$1" in
        plugins/?*) echo "$LIVE/plugins" ;;
        skins/?*)   echo "$LIVE/config/uihook/$1" ;;
        *)          echo "$LIVE/addons/$1" ;;
    esac
}

# Files that a copy from $1 to $2 would add or replace, one per line: "new <path>" or "changed <path>"
pending() {
    local name="${3:-}" f
    read -r -a f <<< "$(filters "$name")"
    rsync -rcn --itemize-changes "${f[@]}" "$1/" "$2/" 2>/dev/null |
        awk '$1 ~ /^>f\+/ { $1 = ""; print "new    " substr($0, 2); next }
             $1 ~ /^>f/   { $1 = ""; print "changed" substr($0, 1) }'
}

# Files in $2 that $1 does not have
only_in() {
    local name="${3:-}" f
    read -r -a f <<< "$(filters "$name")"
    rsync -rn --itemize-changes --ignore-existing "${f[@]}" "$2/" "$1/" 2>/dev/null |
        awk '$1 ~ /^>f/ { $1 = ""; print substr($0, 2) }'
}

need_addon() {
    [[ $# -ge 1 && -n "$1" ]] || die "which addon? (see: ./deploy.sh status)"
    case "$1" in
        plugins/?*) SRC="$(source_dir "$1")" || die "no build of '${1#plugins/}' (looked for plugins/${1#plugins/}/build/${1#plugins/}.dll: run its build.sh)" ;;
        skins/?*)   SRC="$(source_dir "$1")" || die "no skin '${1#skins/}' (looked for plugins/uihook/build/$1: make it with tools/uihook_skin.py)" ;;
        *)          SRC="$(source_dir "$1")" || die "no addon '$1' in addons/ or forks/addons/ (looked for $1.lua)" ;;
    esac
    DST="$(live_dir "$1")"
}

# What to do in game for a change to take effect
reload_hint() {
    if [[ "$1" == plugins/* ]]; then
        echo "In game: /unload ${1#plugins/} then /load ${1#plugins/} (or start the game again)"
    elif [[ "$1" == skins/* ]]; then
        echo "In game: Reload in /nativeui (or /uihook skin reload)"
    elif [[ "$1" == libs/* ]]; then
        echo "In game: reload each addon that uses ${1#libs/} (/addon reload <addon>)"
    else
        echo "In game: /addon reload $1"
    fi
}

need_person() {
    [[ -t 0 ]] || die "this step needs a person at the terminal"
}

confirm() {
    need_person
    # -y answers the question, but the step is still only for a person at the terminal
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        echo "$1 yes (-y)"
        return 0
    fi
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" == y || "$answer" == Y ]]
}

# The name of every folder under addons and forks/addons, and of every library under addons/libs (as
# libs/<name>). Libraries first, so that when all are pushed they land before the addons that use them.
all_names() {
    local dir
    for dir in "$PROJECT"/addons/libs/*/; do
        [[ -d "$dir" ]] && echo "libs/$(basename "$dir")"
    done
    # the plugins built here that live has (a new one only by name), then the skins made
    for dir in "$PROJECT"/plugins/*/; do
        local plugin; plugin="$(basename "$dir")"
        [[ "$plugin" == exclude ]] && continue
        [[ -f "$dir/build/$plugin.dll" && -f "$LIVE/plugins/$plugin.dll" ]] && echo "plugins/$plugin"
    done
    for dir in "$PROJECT"/plugins/uihook/build/skins/*/; do
        [[ -d "$dir" ]] && echo "skins/$(basename "$dir")"
    done
    for dir in "$PROJECT"/addons/*/ "$PROJECT"/forks/addons/*/; do
        [[ "$(basename "$dir")" == libs ]] && continue
        [[ -d "$dir" ]] && basename "$dir"
    done | awk '!seen[$0]++'
    return 0
}

# The names, from all_names, of everything that a push would change
changed_names() {
    local name src
    while read -r name; do
        src="$(source_dir "$name")" || continue
        [[ -n "$(pending "$src" "$(live_dir "$name")" "$name")" ]] && echo "$name"
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
        if [[ ! -d "$dst" || ( "$name" == plugins/* && ! -f "$dst/${name#plugins/}.dll" ) ]]; then
            printf '%-16s %s\n' "$name" "not in live yet"
            continue
        fi
        changes="$(pending "$src" "$dst" "$name" | wc -l)"
        extra="$(only_in "$src" "$dst" "$name" | wc -l)"
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
    list="$(pending "$SRC" "$DST" "$1")"
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
    extra="$(only_in "$SRC" "$DST" "$1")"
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
    local f; read -r -a f <<< "$(filters "$name")"
    rsync -rc --times --backup --backup-dir="$backup" "${f[@]}" "$src/" "$dst/"

    # what was newly added, so that a rollback can say so
    echo "$list" | awk '$1 == "new" { $1 = ""; print substr($0, 2) }' > "$backup/.added"

    echo "Pushed $name. Replaced files are kept in deploy-backups/$name/$stamp"
}

cmd_push() {
    need_addon "$@"
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"

    local list
    list="$(pending "$SRC" "$DST" "$1")"
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

# push for everything that differs from live: all of it shown, then pushed, with no question
cmd_push_all() {
    [[ -d "$LIVE/addons" ]] || die "live install not found at $LIVE (set ASHITA_LIVE to change it)"
    need_person

    local names name
    names="$(changed_names)"
    if [[ -z "$names" ]]; then
        echo "Nothing to push: live already matches everything here."
        return
    fi

    while read -r name; do
        echo "$name: about to copy into $(live_dir "$name")"
        pending "$(source_dir "$name")" "$(live_dir "$name")" "$name" | sed 's/^/  /'
    done <<< "$names"
    echo

    local addons=()
    while read -r name; do
        do_push "$name" "$(pending "$(source_dir "$name")" "$(live_dir "$name")" "$name")"
        [[ "$name" != libs/* ]] && addons+=("$name")
    done <<< "$names"

    echo
    if [[ "$names" == *libs/* ]]; then
        echo "A library changed: in game, reload every addon that uses it."
    fi
    for name in "${addons[@]+"${addons[@]}"}"; do
        reload_hint "$name"
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
    [[ -d "$src" ]] || die "no '$name' in $LIVE"
    case "$name" in
        plugins/?*) dst="$PROJECT/plugins/${name#plugins/}/build" ;;
        skins/?*)   dst="$PROJECT/plugins/uihook/build/$name" ;;
        *)          dst="$(source_dir "$name" 2>/dev/null || echo "$PROJECT/addons/$name")" ;;
    esac

    local list
    list="$(pending "$src" "$dst" "$name")"
    if [[ -z "$list" ]]; then
        echo "$name: the project copy already has everything live has."
        return
    fi

    echo "$name: about to copy from live into $dst"
    echo "$list" | sed 's/^/  /'
    echo "Files marked 'changed' will be overwritten in the project folder."
    confirm "Pull these into the project?" || { echo "Nothing was changed."; return; }

    mkdir -p "$dst"
    local f; read -r -a f <<< "$(filters "$name")"
    rsync -rc --times "${f[@]}" "$src/" "$dst/"
    echo "Pulled."
}

usage() { sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
