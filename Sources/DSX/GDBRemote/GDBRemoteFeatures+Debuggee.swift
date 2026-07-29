// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteFeatures {
  internal init(_ capabilities: DebugCapabilities) {
    var features: GDBRemoteFeatures = [
      .batch, .binary, .execute, .features, .hwbreak, .map, .multiprocess,
      .native, .noack, .nonstop, .reset, .stopthreads, .swbreak, .threads,
      .threadsuffix, .unset, .vcont, .ranges,
    ]
    if capabilities.contains(.auxiliary) {
      features.insert(.auxiliary)
    }
    if capabilities.contains(.executable) {
      features.insert(.executable)
    }
    if capabilities.contains(.libraries) {
      features.insert(.libraries)
    }
    if capabilities.contains(.randomization) {
      features.insert(.randomization)
    }
    if capabilities.contains(.passthrough) {
      features.insert(.pass)
    }
    if capabilities.contains(.fork) {
      features.insert(.fork)
    }
    if capabilities.contains(.vfork) {
      features.insert(.vfork)
    }
    if capabilities.contains(.threads) {
      features.insert(.events)
      features.insert(.options)
    }
    if capabilities.contains(.syscalls) {
      features.insert(.syscalls)
    }
    if capabilities.contains(.signal) {
      features.insert(.signal)
    }
    if capabilities.contains(.svr4) {
      features.insert(.svr4)
    }
    if capabilities.contains(.core) {
      features.insert(.savecore)
    }
    self = features
  }
}
