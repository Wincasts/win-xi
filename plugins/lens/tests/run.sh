#!/usr/bin/env bash
# Compiles the capture and stack fixtures and runs them under Wine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../../.toolchain}"
MSVC="${MSVC_PATH:-$TOOLCHAIN/msvc}"
OUT="$HERE/build/tests"
mkdir -p "$OUT"
for check in capture warp mousescan; do
    clang-cl --target=i686-pc-windows-msvc /nologo /std:c++latest /Od /MT /EHa /W4 /permissive- \
        /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS \
        /imsvc "$MSVC/crt/include" /imsvc "$MSVC/sdk/include/ucrt" /imsvc "$MSVC/sdk/include/um" /imsvc "$MSVC/sdk/include/shared" \
        /c "/Fo$OUT/$check.obj" "$HERE/tests/$check.cpp"
    lld-link /nologo /subsystem:console "/out:$OUT/$check.exe" "$OUT/$check.obj" \
        "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86"
    WINEPREFIX="$OUT/prefix" WINEDEBUG=-all wine "$OUT/$check.exe"
done
