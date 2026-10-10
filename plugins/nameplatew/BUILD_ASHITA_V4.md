# Building Nameplate-AshitaV4

This fork builds Nameplate as a 32-bit Ashita v4 plugin DLL for Final Fantasy XI.

## Requirements

- Windows
- Visual Studio 2022 or Visual Studio 2022 Build Tools
- CMake 3.28 or newer
- Ashita v4 plugin SDK folder containing `Ashita.h`

## Important

Final Fantasy XI and Ashita v4 are 32-bit. Build with Visual Studio's `Win32` generator platform, not x64.

## PowerShell build command

Run this from the repository root and adjust the SDK path if needed:

```powershell
$AshitaSdk="C:\Games\PC\FFXI\Ashita\plugins\sdk"; Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue; cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="$AshitaSdk"; if ($LASTEXITCODE -eq 0) { cmake --build build --config Release }
```

Expected output:

```text
build\Release\Nameplate.dll
```

## Install test

Close FFXI/Ashita first, then copy the DLL:

```powershell
Copy-Item ".\build\Release\Nameplate.dll" "C:\Games\PC\FFXI\Ashita\plugins\Nameplate.dll" -Force
```

Launch FFXI through Ashita and test manually:

```text
/load Nameplate
/nameplate help
```

Do not add Nameplate to startup until manual loading works cleanly.

## Notes for this cleanup

- Replaced the MSVC-incompatible float conversion in `src/bytes/bytes.h` with `std::memcpy`.
- Removed an unused `isspace_or_end(const char*)` overload that generated warning C4505.
- Converted the internal signature helper from a C++ module file to a normal header to avoid Visual Studio module-scanner noise from Windows SDK headers.
- Updated the GitHub Actions workflow to build Win32 Release with Visual Studio.

## Ashita Export Requirements

The Ashita v4 build exports the required plugin entry points through `src/exports_ashita.def`:

```text
expCreatePlugin
expDestroyPlugin
expGetInterfaceVersion
```

If Ashita reports that the plugin is missing required exports, verify that the installed DLL was rebuilt from this source and that only `build\Release\Nameplate.dll` was copied to `<AshitaRoot>\plugins\Nameplate.dll`.
