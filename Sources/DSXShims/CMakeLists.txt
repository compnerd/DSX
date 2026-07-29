# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

add_library(DSXShims STATIC
  DSXShims.c)
target_sources(DSXShims PUBLIC FILE_SET HEADERS
  BASE_DIRS
    include
  FILES
    include/DSXShims.h
    include/module.modulemap)

install(TARGETS DSXShims
  ARCHIVE EXCLUDE_FROM_ALL
  FILE_SET HEADERS
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/DSXShims)
