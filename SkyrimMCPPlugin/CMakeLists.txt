cmake_minimum_required(VERSION 3.21)

# Keep vcpkg on the same VS instance during automatic CMake regeneration.
if(CMAKE_GENERATOR_INSTANCE)
    set(ENV{VCPKG_VISUAL_STUDIO_PATH} "${CMAKE_GENERATOR_INSTANCE}")
endif()

project(
    SkyrimMCPPlugin
    VERSION 1.0.0
    LANGUAGES CXX
)

# iVault's audited VS2022 flags-off profile applies to the SDK and plugin.
if(NOT MSVC OR MSVC_VERSION LESS 1930 OR MSVC_VERSION GREATER_EQUAL 1950)
    message(FATAL_ERROR "Use VS2022 MSVC and a fresh build directory")
endif()
foreach(_configuration RELEASE RELWITHDEBINFO)
    string(REGEX REPLACE "(^|[ \t])[-/]O[12dsx]([ \t]|$)" "\\1\\2"
        CMAKE_CXX_FLAGS_${_configuration} "${CMAKE_CXX_FLAGS_${_configuration}}")
    string(REGEX REPLACE "(^|[ \t])[-/]Ob[0-3]([ \t]|$)" "\\1\\2"
        CMAKE_CXX_FLAGS_${_configuration} "${CMAKE_CXX_FLAGS_${_configuration}}")
    string(APPEND CMAKE_CXX_FLAGS_${_configuration} " /Od /Ob0")
endforeach()
include(CheckCXXCompilerFlag)
check_cxx_compiler_flag("/std:c++23" HAS_FIXED_CXX23)
if(HAS_FIXED_CXX23)
    set(_cxx23_option "/std:c++23")
else()
    check_cxx_compiler_flag("/std:c++23preview" HAS_CXX23_PREVIEW)
    if(NOT HAS_CXX23_PREVIEW)
        message(FATAL_ERROR "VS2022 must support /std:c++23 or /std:c++23preview")
    endif()
    set(_cxx23_option "/std:c++23preview")
endif()
set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "${_cxx23_option}")
set(CMAKE_CXX23_EXTENSION_COMPILE_OPTION "${_cxx23_option}")

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Find dependencies
find_package(nlohmann_json CONFIG REQUIRED)

set(BUILD_TESTS OFF CACHE BOOL "CommonLib tests" FORCE)
set(SKSE_SUPPORT_XBYAK OFF CACHE BOOL "No Xbyak" FORCE)
set(ENABLE_SKYRIM_SE ON CACHE BOOL "SE support" FORCE)
set(ENABLE_SKYRIM_AE ON CACHE BOOL "AE support" FORCE)
set(ENABLE_SKYRIM_VR OFF CACHE BOOL "No VR support" FORCE)
set(COMMONLIB_PREBUILT OFF CACHE BOOL "Source-build the audited SDK" FORCE)
set(COMMONLIB_PREBUILT_DIR "" CACHE PATH "No prebuilt override" FORCE)

set(_minll_source "${CMAKE_CURRENT_SOURCE_DIR}/extern/CommonLibVR")
set(_minll_commit "550cc4fb9114649dcf526d1f3d73d710c5d7003b")
find_package(Git REQUIRED)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_minll_source}" rev-parse HEAD
    RESULT_VARIABLE _rev_result OUTPUT_VARIABLE _rev OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _rev_result EQUAL 0 OR NOT _rev STREQUAL _minll_commit)
    message(FATAL_ERROR "Clone MinLL/CommonLibVR v4.39.5 at ${_minll_commit}; resolved ${_rev}")
endif()
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${_minll_source}"
    status --porcelain --untracked-files=all
    RESULT_VARIABLE _status_result OUTPUT_VARIABLE _status OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _status_result EQUAL 0 OR NOT _status STREQUAL "")
    message(FATAL_ERROR "CommonLibVR checkout must be clean: ${_status}")
endif()
file(STRINGS "${_minll_source}/LICENSE" _license LIMIT_COUNT 1)
if(NOT _license STREQUAL "MIT License")
    message(FATAL_ERROR "CommonLibVR must retain its MIT license")
endif()
message(STATUS "CommonLibVR source: ${_minll_source} @ ${_rev}")
add_subdirectory(extern/CommonLibVR)
get_target_property(_imported CommonLibSSE IMPORTED)
if(_imported)
    message(FATAL_ERROR "The audited ABI requires source-built CommonLib")
endif()
# The SDK only imports this helper automatically on its prebuilt route.
include("${_minll_source}/cmake/CommonLibSSE.cmake")

# This exact non-VR pin declares one VR-only virtual in the SE/AE view.
file(READ "${_minll_source}/include/RE/T/TESObjectREFR.h" _header)
string(REPLACE "\r\n" "\n" _header "${_header}")
string(SHA256 _original_sha "${_header}")
if(NOT _original_sha STREQUAL "98a8a1cb24f51b893b4343c4c552e363d9bc90ee7a611c05f7719c2479bec2b6")
    message(FATAL_ERROR "TESObjectREFR header changed; re-audit the non-VR ABI")
endif()
string(REGEX REPLACE
    "\n[ \t]*SKYRIM_REL_VR_VIRTUAL void[ \t]+Unk_8C\\(void\\);[^\n]*"
    "" _fixed "${_header}")
string(SHA256 _fixed_sha "${_fixed}")
if(NOT _fixed_sha STREQUAL "6ff59cd37693e301cc3282099a11b785f4a386334f0947adc37511afeabf690f")
    message(FATAL_ERROR "Unexpected corrected TESObjectREFR header")
endif()
set(_abi_include "${CMAKE_CURRENT_BINARY_DIR}/commonlib-abi/include")
file(MAKE_DIRECTORY "${_abi_include}/RE/T")
file(GENERATE OUTPUT "${_abi_include}/RE/T/TESObjectREFR.h" CONTENT "${_fixed}")
target_include_directories(CommonLibSSE BEFORE PUBLIC "$<BUILD_INTERFACE:${_abi_include}>")

# Plugin sources
set(SOURCES
    src/CombatAnalysis.cpp
    src/EventSystem.cpp
    src/InventoryManager.cpp
    src/Main.cpp
    src/NPCManager.cpp
    src/PapyrusBridge.cpp
    src/PipeServer.cpp
    src/PlayerQueries.cpp
    src/Protocol.cpp
    src/QuestManager.cpp
    src/TaskQueue.cpp
    src/UIManager.cpp
    src/UtilityManager.cpp
    src/WorldManager.cpp
)

set(HEADERS
    src/CombatAnalysis.h
    src/EventSystem.h
    src/GameInterface.h
    src/Helpers.h
    src/InventoryManager.h
    src/NPCManager.h
    src/PCH.h
    src/PapyrusBridge.h
    src/PipeServer.h
    src/PlayerQueries.h
    src/Protocol.h
    src/QuestManager.h
    src/TaskQueue.h
    src/UIManager.h
    src/UtilityManager.h
    src/WorldManager.h
)

add_commonlibsse_plugin(${PROJECT_NAME}
    NAME "${PROJECT_NAME}"
    AUTHOR "SkyrimMCP"
    USE_ADDRESS_LIBRARY
    SOURCES ${SOURCES} ${HEADERS})
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)

target_include_directories(${PROJECT_NAME} PRIVATE src)

target_link_libraries(${PROJECT_NAME} PRIVATE
    nlohmann_json::nlohmann_json
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
)

# Set output name without "lib" prefix
set_target_properties(${PROJECT_NAME} PROPERTIES
    PREFIX ""
    OUTPUT_NAME "SkyrimMCPPlugin"
)

# Copy output to a convenient location
add_custom_command(
    TARGET ${PROJECT_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "$<TARGET_FILE:${PROJECT_NAME}>"
        "${CMAKE_SOURCE_DIR}/output/$<TARGET_FILE_NAME:${PROJECT_NAME}>"
    COMMENT "Copying plugin DLL to output/"
)
