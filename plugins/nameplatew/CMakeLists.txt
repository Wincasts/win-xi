cmake_minimum_required(VERSION 3.28)

project(Nameplate
    VERSION 0.71
    LANGUAGES CXX
    DESCRIPTION "Corrects defects in Final Fantasy XI nameplate rendering."
    HOMEPAGE_URL "https://www.github.com/Shirk/Nameplate"
)

# Nameplate is a 32-bit injected plugin for Final Fantasy XI/Ashita v4.
# Build with Visual Studio's Win32 generator platform, not x64.
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Nameplate must be built as a 32-bit DLL. Reconfigure with: -A Win32")
endif()

option(NAMEPLATE_BUILD_WINDOWER "Also build/export Windower 4 compatibility entry points." OFF)

# Prefer an explicit -DASHITA_SDK_PATH=... value, but allow an environment
# variable to make local builds less annoying.
if(NOT DEFINED ASHITA_SDK_PATH OR ASHITA_SDK_PATH STREQUAL "")
    if(DEFINED ENV{ASHITA_SDK_PATH})
        set(ASHITA_SDK_PATH "$ENV{ASHITA_SDK_PATH}" CACHE PATH "Ashita v4 plugin SDK path" FORCE)
    else()
        set(ASHITA_SDK_PATH "" CACHE PATH "Ashita v4 plugin SDK path")
    endif()
endif()

if(NOT EXISTS "${ASHITA_SDK_PATH}/Ashita.h")
    message(FATAL_ERROR "ASHITA_SDK_PATH must point to Ashita's plugin SDK folder containing Ashita.h. Example: -DASHITA_SDK_PATH=C:/Games/Ashita/plugins/sdk")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS True)

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/versioninfo.rc.in versioninfo.rc @ONLY)

add_library(nameplatew SHARED)

set(NAMEPLATE_SOURCES
    src/Nameplate.cpp
    src/Nameplate.h
    src/Ashita/Ashita.cpp
    src/Ashita/exports.h
    "${CMAKE_CURRENT_BINARY_DIR}/versioninfo.rc"
)

if(NAMEPLATE_BUILD_WINDOWER)
    list(APPEND NAMEPLATE_SOURCES
        src/Windozer/Windozer.cpp
        src/Windozer/Windozer.h
        src/exports.def
    )
else()
    list(APPEND NAMEPLATE_SOURCES
        src/exports_ashita.def
    )
endif()

target_sources(nameplatew PRIVATE
    ${NAMEPLATE_SOURCES}
    src/findsignature.h
)

target_include_directories(nameplatew PRIVATE ${ASHITA_SDK_PATH})
target_compile_definitions(nameplatew PRIVATE WIN32_LEAN_AND_MEAN)

# Interprocedural optimization is nice, but keep it opt-in friendly on older
# local toolchains.  CMake will ignore this if the generator/toolchain cannot
# support it cleanly.
set_property(TARGET nameplatew PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)

if(MSVC)
    target_compile_options(nameplatew PRIVATE /EHa /W4 /permissive-)
else()
    target_compile_options(nameplatew PRIVATE
        -m32
        -fno-rtti -march=nehalem -fomit-frame-pointer -ffast-math -mfpmath=sse -mtune=skylake
        -Wall -Wextra -Wpedantic -W
        -Wno-c++98-compat -Wno-reserved-macro-identifier -Wno-nonportable-system-include-path
        -Wno-reserved-identifier -Wno-gnu-anonymous-struct -Wno-nested-anon-types
        -Wno-c++98-compat-pedantic -Wno-non-virtual-dtor -Wno-extra-semi -Wno-shadow-field
        -Wno-old-style-cast -Wno-float-equal -Wno-documentation -Wno-microsoft-end-of-file
        -Wno-sign-conversion -Wno-cast-align
        -Wno-newline-eof -Wno-language-extension-token -Wno-cast-qual -Wno-extra-semi-stmt
        -Wno-deprecated-copy-with-user-provided-dtor -Wno-missing-noreturn
        -Wno-tautological-unsigned-zero-compare -Wno-duplicate-enum -Wno-double-promotion
        -Wno-documentation-unknown-command -Wno-unused-function
        -Wno-c99-extensions -Wno-missing-braces)
    target_link_options(nameplatew PRIVATE -m32)
endif()
