cmake_minimum_required(VERSION 3.20)
project(LLVMStrengthReduction VERSION 1.0.0 LANGUAGES CXX)

# ---------------------------------------------------------------------------
# Locate LLVM.  Point CMake at it with either
#   -DLLVM_DIR=$(llvm-config --cmakedir)     or
#   -DCMAKE_PREFIX_PATH=/path/to/llvm/install
# ---------------------------------------------------------------------------
find_package(LLVM REQUIRED CONFIG)

if(LLVM_VERSION_MAJOR LESS 15)
  message(FATAL_ERROR
    "LLVM ${LLVM_PACKAGE_VERSION} found, but pass plugins for the new pass "
    "manager require LLVM >= 15.")
endif()

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")
message(STATUS "LLVM tools directory:      ${LLVM_TOOLS_BINARY_DIR}")

# Match LLVM's language standard (>= 17 is fine for every supported LLVM).
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# ---------------------------------------------------------------------------
# The plugin.  A MODULE library: it is dlopen()ed by opt / clang, which
# already provide every LLVM symbol, so we deliberately link *no* LLVM libs
# (linking them would duplicate global state such as cl::opt registries).
# ---------------------------------------------------------------------------
add_library(StrengthReductionPass MODULE src/StrengthReductionPass.cpp)

target_include_directories(StrengthReductionPass SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
separate_arguments(LLVM_DEFS_LIST NATIVE_COMMAND "${LLVM_DEFINITIONS}")
target_compile_definitions(StrengthReductionPass PRIVATE ${LLVM_DEFS_LIST})

# LLVM is normally built without RTTI/exceptions; mixing them breaks dyn_cast
# machinery and typeinfo lookups across the plugin boundary.
if(NOT LLVM_ENABLE_RTTI)
  if(MSVC)
    target_compile_options(StrengthReductionPass PRIVATE /GR-)
  else()
    target_compile_options(StrengthReductionPass PRIVATE -fno-rtti)
  endif()
endif()
if(NOT LLVM_ENABLE_EH AND NOT MSVC)
  target_compile_options(StrengthReductionPass PRIVATE -fno-exceptions)
endif()

if(NOT MSVC)
  target_compile_options(StrengthReductionPass PRIVATE -Wall -Wextra)
endif()

# Output is exactly "StrengthReductionPass.so" / ".dylib" (no "lib" prefix).
set_target_properties(StrengthReductionPass PROPERTIES
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# Symbols are resolved from the host executable at load time.
if(APPLE)
  target_link_options(StrengthReductionPass PRIVATE -undefined dynamic_lookup)
endif()

# ---------------------------------------------------------------------------
# lit / FileCheck test suite:   cmake --build build --target check-strength-reduction
# ---------------------------------------------------------------------------
find_program(LIT_EXECUTABLE NAMES lit llvm-lit lit.py
             HINTS "${LLVM_TOOLS_BINARY_DIR}")

set(SR_PLUGIN_PATH "$<TARGET_FILE:StrengthReductionPass>")
set(SR_LLVM_TOOLS_DIR "${LLVM_TOOLS_BINARY_DIR}")
set(SR_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

# Config contains a generator expression, so use file(GENERATE).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/test/lit.site.cfg.py.in" _SITE_CFG_IN)
string(CONFIGURE "${_SITE_CFG_IN}" _SITE_CFG @ONLY)
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/test/lit.site.cfg.py" CONTENT "${_SITE_CFG}")

if(LIT_EXECUTABLE)
  add_custom_target(check-strength-reduction
    COMMAND "${LIT_EXECUTABLE}" -v "${CMAKE_BINARY_DIR}/test"
    DEPENDS StrengthReductionPass
    COMMENT "Running lit/FileCheck tests"
    USES_TERMINAL)
else()
  add_custom_target(check-strength-reduction
    COMMAND "${CMAKE_COMMAND}" -E echo
            "lit not found: install it with 'pip install lit' and re-run cmake."
    COMMAND "${CMAKE_COMMAND}" -E false)
endif()
