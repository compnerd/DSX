# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  Array+Environment.swift
  Array+Ordering.swift
  Duration+Extensions.swift
  OutputSpan+Debuggee.swift
  OutputSpan+Registers.swift
  Span+Continuations.swift
  Span+Matching.swift
  Span+NumericParsing.swift
  Span+Path.swift
  Span+Registers.swift
  Span+Slicing.swift
  String+Architecture.swift
  String+Extensions.swift
  String+MachO.swift
  String+Module.swift
  String+PE.swift
  String+Truth.swift
  String+Windows.swift
  UInt8+Hex.swift
  UnsafeMutableRawBufferPointer+Linux.swift)
