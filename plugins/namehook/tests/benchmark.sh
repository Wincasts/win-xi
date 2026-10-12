#!/usr/bin/env bash
# CPU lookup microbenchmark under Wine, not an in-game rendering benchmark.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../../.toolchain}"
MSVC="${MSVC_PATH:-$TOOLCHAIN/msvc}"
OUT="$HERE/build/tests"
mkdir -p "$OUT"
clang-cl --target=i686-pc-windows-msvc /nologo /std:c++latest /O2 /MT /EHa /W4 /permissive- \
    /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS \
    /imsvc "$MSVC/crt/include" /imsvc "$MSVC/sdk/include/ucrt" /imsvc "$MSVC/sdk/include/um" /imsvc "$MSVC/sdk/include/shared" \
    /c "/Fo$OUT/whitelist_bench.obj" "$HERE/tests/whitelist_bench.cpp"
lld-link /nologo /subsystem:console "/out:$OUT/whitelist_bench.exe" "$OUT/whitelist_bench.obj" \
    "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86"
WINEPREFIX="$OUT/prefix" WINEDEBUG=-all wine "$OUT/whitelist_bench.exe"
