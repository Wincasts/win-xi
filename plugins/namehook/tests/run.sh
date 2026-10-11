#!/usr/bin/env bash
# Builds tests/test.cpp as a 32-bit Windows program and runs it under wine, in a wine prefix of its
# own under build/. Needs what ../build.sh needs, less the Ashita SDK.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../../.toolchain}"
MSVC="${MSVC_PATH:-$TOOLCHAIN/msvc}"
OUT="$HERE/build/tests"

mkdir -p "$OUT"

clang-cl --target=i686-pc-windows-msvc /nologo /std:c++latest /Od /MT /EHa /W4 /permissive- \
    /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS -Wno-keyword-macro \
    /imsvc "$MSVC/crt/include" /imsvc "$MSVC/sdk/include/ucrt" /imsvc "$MSVC/sdk/include/um" /imsvc "$MSVC/sdk/include/shared" \
    /c "/Fo$OUT/test.obj" "$HERE/tests/test.cpp"

lld-link /nologo /subsystem:console "/out:$OUT/test.exe" "$OUT/test.obj" \
    "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86"

WINEPREFIX="$OUT/prefix" WINEDEBUG=-all wine "$OUT/test.exe"
