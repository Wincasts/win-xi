#!/usr/bin/env bash
# Builds build/nameplatehook.dll on Linux with clang-cl and lld-link, as a 32-bit Windows plugin.
#
#   ./build.sh
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
for source in src/Nameplate.cpp src/Ashita/Ashita.cpp; do
    object="$OUT/$(basename "${source%.cpp}").obj"
    clang-cl --target=i686-pc-windows-msvc /nologo /c /std:c++latest /O2 /MD /EHa /W4 /permissive- \
        /DWIN32_LEAN_AND_MEAN /DNDEBUG /D_CRT_SECURE_NO_WARNINGS \
        "${INCLUDES[@]}" /imsvc "$SDK" \
        "/Fo$object" "$HERE/$source"
    objects+=("$object")
done

llvm-rc /nologo /I "$MSVC/sdk/include/um" /I "$MSVC/sdk/include/shared" \
    /fo "$OUT/versioninfo.res" "$HERE/src/versioninfo.rc.in"

# The Ashita SDK asks for Psapi.lib by a spelling the Windows SDK does not have on a
# case-sensitive file system
mkdir -p "$OUT/lib"
ln -sf "$MSVC/sdk/lib/um/x86/psapi.lib" "$OUT/lib/Psapi.lib"

lld-link /nologo /dll /machine:x86 /opt:ref /opt:icf \
    "/def:$HERE/src/exports_ashita.def" "/out:$OUT/nameplatehook.dll" \
    "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86" "/libpath:$OUT/lib" \
    "${objects[@]}" "$OUT/versioninfo.res"

echo "built $OUT/nameplatehook.dll"
