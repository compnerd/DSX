# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

if(WIN32)
  # COFF module metadata distinguishes static references from DLL imports.
  # Compile both forms rather than importing DLL symbols into the static CLI.
  add_library(DSXCore STATIC)
else()
  add_library(DSXCore OBJECT)
endif()

add_subdirectory(API)
add_subdirectory(Core)
add_subdirectory(Debuggee)
add_subdirectory(Extensions)
add_subdirectory(Formats)
add_subdirectory(GDBRemote)
add_subdirectory(Host)
add_subdirectory(Logging)
add_subdirectory(Native)
add_subdirectory(Server)
add_subdirectory(Transport)

set_target_properties(DSXCore PROPERTIES
  Swift_MODULE_NAME DSX
  OUTPUT_NAME DSX)
target_compile_options(DSXCore PRIVATE
  "SHELL:-module-link-name DSX")

# Core consumers receive its definitions through the CMake dependency graph.
# The installed module autolinks the public DSX shared library.
target_compile_options(DSXCore INTERFACE
  "SHELL:-Xfrontend -disable-autolink-library -Xfrontend DSX")
target_link_libraries(DSXCore PUBLIC DSXShims)
if(WIN32)
  target_link_libraries(DSXCore PUBLIC
    bcrypt
    Pathcch
    ntdll
    Ws2_32)
elseif(ANDROID)
  target_link_libraries(DSXCore PUBLIC
    Crypto)
elseif(LINUX)
  find_package(OpenSSL REQUIRED COMPONENTS Crypto)
  target_link_libraries(DSXCore PUBLIC
    OpenSSL::Crypto)
elseif(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
  target_link_libraries(DSXCore PUBLIC
    md)
endif()

if(WIN32)
  set_target_properties(DSXCore PROPERTIES
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/static")
  target_include_directories(DSXCore INTERFACE
    "${CMAKE_CURRENT_BINARY_DIR}/static")
  get_target_property(sources DSXCore SOURCES)
  add_library(DSX SHARED ${sources})
  target_link_libraries(DSX PRIVATE
    DSXShims
    bcrypt
    Pathcch
    ntdll
    Ws2_32)
else()
  add_library(DSX SHARED)
  target_link_libraries(DSX PRIVATE DSXCore)
endif()
install(DIRECTORY "${CMAKE_Swift_MODULE_DIRECTORY}/DSX.swiftmodule"
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/swift)
