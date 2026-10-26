#!/usr/bin/env bash
# Compile the migrated modules' signature/ABI/detour fixtures and run under Wine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HERE/../../.toolchain}"
MSVC="${MSVC_PATH:-$TOOLCHAIN/msvc}"
SDK="${ASHITA_SDK_PATH:-$TOOLCHAIN/ashita/plugins/sdk}"
OUT="$HERE/build/tests"
# a font file for the font drawing's checks (the game's prefix's Trebuchet, where it is), else they are skipped
GAME_FONT="${GAME_FONT:-$HOME/.local/share/com.phoenixxi.launcher/prefix/0/drive_c/windows/Fonts/trebuc.ttf}"
mkdir -p "$OUT"
for module in buffs party hud chat chat_controls chat_windows menus history texttap native mirror textures skin skinfont keys; do
    clang-cl --target=i686-pc-windows-msvc /nologo /std:c++latest /Od /MT /EHa /W4 /permissive- \
        /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS -Wno-keyword-macro \
        /imsvc "$MSVC/crt/include" /imsvc "$MSVC/sdk/include/ucrt" /imsvc "$MSVC/sdk/include/um" /imsvc "$MSVC/sdk/include/shared" /imsvc "$SDK/d3d8/includes" \
        /c "/Fo$OUT/$module.obj" "$HERE/tests/$module.cpp"
    lld-link /nologo /subsystem:console "/out:$OUT/$module.exe" "$OUT/$module.obj" \
        "/libpath:$MSVC/crt/lib/x86" "/libpath:$MSVC/sdk/lib/ucrt/x86" "/libpath:$MSVC/sdk/lib/um/x86" gdi32.lib ole32.lib windowscodecs.lib uuid.lib
    font=""
    [[ "$module" == skinfont && -f "$GAME_FONT" ]] && font="Z:${GAME_FONT//\//\\}"
    WINEPREFIX="$OUT/prefix" WINEDEBUG=-all wine "$OUT/$module.exe" $font
done
cd "$HERE/../.."
luajit tests/nativehud_check.lua
luajit tests/nativechat_check.lua
luajit tests/harness.lua nativeui addons/nativeui/nativeui.lua tests/nativeui_check.lua
luajit tests/groupmirror_check.lua > /dev/null && echo 'groupmirror: 0 failures'
luajit tests/harness.lua nativeui tests/nativeui_group_stand_in.lua tests/nativeui_group_check.lua
luajit tests/party_hook_check.lua
luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_hook_check.lua
