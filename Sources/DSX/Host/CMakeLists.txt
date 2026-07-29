# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  ChildPort.swift
  FileFailure.swift
  FileSystem.swift
  Host.swift
  HostProcess.swift
  NativeProcess+Operations.swift
  NativeProcessCursor+Processes.swift)
