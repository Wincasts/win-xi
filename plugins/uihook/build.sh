#!/usr/bin/env bash
# Builds build/uihook.dll on Linux with clang-cl and lld-link, as a 32-bit Windows plugin.
#
#   ./build.sh                 the plugin as it is played with
#   ./build.sh --diagnostics   with the tools the game's menus were studied with built in as well: /uihook census
#                              and /uihook textures (src/modules/census/diagnostics.h)
#
# Needs two things that are not part of this folder, both looked for under TOOLCHAIN
# (default: <project>/.toolchain):
#   ashita/plugins/sdk   the Ashita v4 plugin SDK, the folder with Ashita.h
#                        git clone https://github.com/AshitaXI/Ashita-v4beta ashita
#   msvc/                the Microsoft C runtime and Windows SDK for x86, as laid out by xwin
#                        xwin --accept-license --arch x86 splat --output msvc
# ASHITA_SDK_PATH and MSVC_PATH name either one somewhere else.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../../.toolchain}"
SDK="${ASHITA_SDK_PATH:-$TOOLCHAIN/ashita/plugins/sdk}"
MSVC="${MSVC_PATH:-$TOOLCHAIN/msvc}"
OUT="$HERE/build"

die() { echo "build: $*" >&2; exit 1; }

DIAGNOSTICS=0
for arg in "$@"; do
    case "$arg" in
        --diagnostics) DIAGNOSTICS=1 ;;
        *) die "unknown option $arg (./build.sh [--diagnostics])" ;;
    esac
done

[[ -f "$SDK/Ashita.h" ]] || die "no Ashita.h in $SDK"
[[ -d "$MSVC/crt/include" && -d "$MSVC/sdk/include/um" ]] || die "no C runtime and Windows SDK in $MSVC"

mkdir -p "$OUT"

INCLUDES=(
    /imsvc "$MSVC/crt/include"
    /imsvc "$MSVC/sdk/include/ucrt"
    /imsvc "$MSVC/sdk/include/um"
    /imsvc "$MSVC/sdk/include/shared"
)

objects=()
for source in src/uihook.cpp src/modules/buffs/buffhook.cpp src/modules/party/partyhook.cpp; do
    object="$OUT/$(basename "${source%.cpp}").obj"
    clang-cl --target=i686-pc-windows-msvc /nologo /c /std:c++latest /O2 /MD /EHa /W4 /permissive- \
        /DWIN32_LEAN_AND_MEAN /DNDEBUG /D_CRT_SECURE_NO_WARNINGS /DUIHOOK_DIAGNOSTICS=$DIAGNOSTICS \
        "${INCLUDES[@]}" /imsvc "$SDK" \
        "/Fo$object" "$HERE/$source"
    objects+=("$object")
done

llvm-rc /nologo /I "$MSVC/sdk/include/um" /I "$MSVC/sdk/include/shared" \
    /fo "$OUT/versioninfo.res" "$HERE/src/versioninfo.rc"

# The Ashita SDK asks for Psapi.lib by a spelling the Windows SDK does not have on a
# case-sensitive file system
mkdir -p "$OUT/lib"
ln -sf "$MSVC/sdk/lib/um/x86/psapi.lib" "$OUT/lib/Psapi.lib"

lld-link /nologo /dll /machine:x86 /opt:ref /opt:icf \
    "/def:$HERE/src/exports.def" "/out:$OUT/uihook.dll" \
    "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86" "/libpath:$OUT/lib" \
    "${objects[@]}" "$OUT/versioninfo.res" user32.lib gdi32.lib ole32.lib windowscodecs.lib uuid.lib

if (( DIAGNOSTICS )); then echo "built $OUT/uihook.dll, with the diagnostics"; else echo "built $OUT/uihook.dll"; fi
