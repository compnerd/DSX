# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

# The NDK supplies Clang driver syntax in language-independent linker flags.
# Use CMake's portable spelling so Swift receives -Xlinker, not -Wl, options.
foreach(kind EXE SHARED MODULE)
  string(REPLACE "-Wl," "LINKER:" flags "${CMAKE_${kind}_LINKER_FLAGS_INIT}")
  string(REPLACE "-Qunused-arguments" "" flags "${flags}")
  set(CMAKE_${kind}_LINKER_FLAGS_INIT "${flags}")
endforeach()
