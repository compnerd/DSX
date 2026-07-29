# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  DSX+Logging.swift
  Debuggee.Error+Logging.swift
  LogChannel.swift
  LogConfiguration.swift
  LogDirection.swift
  LogError.swift
  LogLevel.swift
  LogState.swift
  LogStream.swift
  Mutex+Windows.swift
  NativeLog.swift)
