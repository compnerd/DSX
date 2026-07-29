# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

include(FetchContent)

function(dsx_fetch)
  # Older dependency minimums unset these policies despite DSX's 4.4 minimum.
  set(CMAKE_POLICY_DEFAULT_CMP0157 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0181 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0195 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0215 NEW)
  set(BUILD_SHARED_LIBS OFF)
  set(BUILD_TESTING OFF)
  FetchContent_MakeAvailable(${ARGV})
endfunction()

FetchContent_Declare(Yams
  GIT_REPOSITORY https://github.com/jpsim/Yams
  GIT_TAG a27b21e0c81c5bf42049b897a62aaf387e80f279 # 6.2.2
  EXCLUDE_FROM_ALL)

if(ANDROID)
  find_package(Git REQUIRED QUIET)
  FetchContent_Declare(ASN1
    GIT_REPOSITORY https://github.com/apple/swift-asn1
    GIT_TAG d9a5b37470adc940d22c3bcd5ca6953a516b727f # 1.7.2
    EXCLUDE_FROM_ALL)
  FetchContent_Declare(Crypto
    GIT_REPOSITORY https://github.com/apple/swift-crypto
    GIT_TAG da9d28d69ebe3894b18376c8f2395c2f37b8448f # 4.5.2
    # Upstream ships these 32-bit assembly sources but omits the CMake branches.
    PATCH_COMMAND "${GIT_EXECUTABLE}" apply
      "${CMAKE_CURRENT_LIST_DIR}/SwiftCrypto.patch"
    EXCLUDE_FROM_ALL)
endif()
