# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

if(NOT DSX_CODEGEN_EXECUTABLE)
  set(DSX_CODEGEN_EXECUTABLE "$<TARGET_FILE:DSXCodeGen>")
endif()

add_custom_command(OUTPUT
    "${PROJECT_BINARY_DIR}/generated/ARMRegisters.swift"
    "${PROJECT_BINARY_DIR}/generated/ARM64Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/I386Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/X86_64Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/NativeRegisterProfile.swift"
    "${PROJECT_BINARY_DIR}/generated/GDBPacketRoutes.swift"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/generated"
  COMMAND "${DSX_CODEGEN_EXECUTABLE}"
    --profile "${CMAKE_CURRENT_SOURCE_DIR}/Registers/ARM.yaml"
      "${PROJECT_BINARY_DIR}/generated/ARMRegisters.swift"
    --profile "${CMAKE_CURRENT_SOURCE_DIR}/Registers/ARM64.yaml"
      "${PROJECT_BINARY_DIR}/generated/ARM64Registers.swift"
    --profile "${CMAKE_CURRENT_SOURCE_DIR}/Registers/I386.yaml"
      "${PROJECT_BINARY_DIR}/generated/I386Registers.swift"
    --profile "${CMAKE_CURRENT_SOURCE_DIR}/Registers/X86_64.yaml"
      "${PROJECT_BINARY_DIR}/generated/X86_64Registers.swift"
    --registry "${PROJECT_BINARY_DIR}/generated/NativeRegisterProfile.swift"
    --packets "${CMAKE_CURRENT_SOURCE_DIR}/Packets.yaml"
      "${PROJECT_BINARY_DIR}/generated/GDBPacketRoutes.swift"
  DEPENDS "${DSX_CODEGEN_EXECUTABLE}"
    Registers/ARM.yaml
    Registers/ARM64.yaml
    Registers/I386.yaml
    Registers/X86_64.yaml
    Packets.yaml
  COMMENT "Generating register definitions and packet routes"
  VERBATIM)

add_custom_target(DSXDefinitions DEPENDS
  "${PROJECT_BINARY_DIR}/generated/ARMRegisters.swift"
  "${PROJECT_BINARY_DIR}/generated/ARM64Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/I386Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/X86_64Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/NativeRegisterProfile.swift"
  "${PROJECT_BINARY_DIR}/generated/GDBPacketRoutes.swift")
target_sources(DSXCore PRIVATE
  "${PROJECT_BINARY_DIR}/generated/ARMRegisters.swift"
  "${PROJECT_BINARY_DIR}/generated/ARM64Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/I386Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/X86_64Registers.swift"
  "${PROJECT_BINARY_DIR}/generated/NativeRegisterProfile.swift"
  "${PROJECT_BINARY_DIR}/generated/GDBPacketRoutes.swift")
add_dependencies(DSXCore DSXDefinitions)
if(WIN32)
  target_sources(DSX PRIVATE
    "${PROJECT_BINARY_DIR}/generated/ARMRegisters.swift"
    "${PROJECT_BINARY_DIR}/generated/ARM64Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/I386Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/X86_64Registers.swift"
    "${PROJECT_BINARY_DIR}/generated/NativeRegisterProfile.swift"
    "${PROJECT_BINARY_DIR}/generated/GDBPacketRoutes.swift")
  add_dependencies(DSX DSXDefinitions)
endif()
