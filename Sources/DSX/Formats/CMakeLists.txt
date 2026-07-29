# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  ELFModule.swift
  MachOLoadCommand.swift
  MachOModule.swift
  PEModule.swift)
