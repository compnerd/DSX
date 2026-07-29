// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct HostMetadata: Sendable {
  internal let cpu: UInt64?
  internal let subtype: UInt64?
  internal let platform: StaticString?
  internal let vendor: StaticString?
  internal let system: StaticString?
  internal let environment: StaticString?
  internal let watchpoint: StaticString?
  internal let addressing: UInt64?

  internal var triple: Bool {
    cpu == nil
  }

  internal init(cpu: UInt64? = nil, subtype: UInt64? = nil,
                platform: StaticString? = nil, vendor: StaticString? = nil,
                system: StaticString? = nil, environment: StaticString? = nil,
                watchpoint: StaticString? = ABI.watchpoint,
                addressing: UInt64? = nil) {
    self.cpu = cpu
    self.subtype = subtype
    self.platform = platform
    self.vendor = vendor
    self.system = system
    self.environment = environment
    self.watchpoint = watchpoint
    self.addressing = addressing
  }
}

internal enum Host: Sendable {
  internal static var platform: StaticString {
    metadata.platform ?? system
  }
}
