// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRemoteFeatures: OptionSet, Sendable {
  internal let rawValue: UInt64

  internal init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  internal static let multiprocess = GDBRemoteFeatures(rawValue: 1 << 0)
  internal static let noack = GDBRemoteFeatures(rawValue: 1 << 1)
  internal static let features = GDBRemoteFeatures(rawValue: 1 << 2)
  internal static let auxiliary = GDBRemoteFeatures(rawValue: 1 << 3)
  internal static let libraries = GDBRemoteFeatures(rawValue: 1 << 4)
  internal static let threads = GDBRemoteFeatures(rawValue: 1 << 5)
  internal static let osdata = GDBRemoteFeatures(rawValue: 1 << 6)
  internal static let signal = GDBRemoteFeatures(rawValue: 1 << 7)
  internal static let svr4 = GDBRemoteFeatures(rawValue: 1 << 8)
  internal static let threadsuffix = GDBRemoteFeatures(rawValue: 1 << 9)
  internal static let stopthreads = GDBRemoteFeatures(rawValue: 1 << 10)
  internal static let pass = GDBRemoteFeatures(rawValue: 1 << 11)
  internal static let fork = GDBRemoteFeatures(rawValue: 1 << 12)
  internal static let vfork = GDBRemoteFeatures(rawValue: 1 << 13)
  internal static let executable = GDBRemoteFeatures(rawValue: 1 << 14)
  internal static let randomization = GDBRemoteFeatures(rawValue: 1 << 15)
  internal static let reset = GDBRemoteFeatures(rawValue: 1 << 16)
  internal static let unset = GDBRemoteFeatures(rawValue: 1 << 17)
  internal static let vcont = GDBRemoteFeatures(rawValue: 1 << 18)
  internal static let swbreak = GDBRemoteFeatures(rawValue: 1 << 19)
  internal static let hwbreak = GDBRemoteFeatures(rawValue: 1 << 20)
  internal static let savecore = GDBRemoteFeatures(rawValue: 1 << 21)
  internal static let nonstop = GDBRemoteFeatures(rawValue: 1 << 22)
  internal static let batch = GDBRemoteFeatures(rawValue: 1 << 23)
  internal static let binary = GDBRemoteFeatures(rawValue: 1 << 24)
  internal static let execute = GDBRemoteFeatures(rawValue: 1 << 25)
  internal static let map = GDBRemoteFeatures(rawValue: 1 << 26)
  internal static let events = GDBRemoteFeatures(rawValue: 1 << 27)
  internal static let syscalls = GDBRemoteFeatures(rawValue: 1 << 28)
  internal static let options = GDBRemoteFeatures(rawValue: 1 << 29)
  internal static let ranges = GDBRemoteFeatures(rawValue: 1 << 30)
  internal static let native = GDBRemoteFeatures(rawValue: 1 << 31)

  internal static let shared: GDBRemoteFeatures =
      [.multiprocess, .libraries, .fork, .vfork, .execute, .vcont, .swbreak,
       .hwbreak]
  internal static let requested: GDBRemoteFeatures =
      [.noack, .threadsuffix, .stopthreads, .pass]
}

internal struct GDBRemoteNegotiation: Sendable {
  internal var acknowledgements: Bool
  internal let supported: GDBRemoteFeatures
  internal var advertised: Bool
  internal var enabled: GDBRemoteFeatures
  internal var packet: Int?
  internal let capacity: Int

  internal init(acknowledgements: Bool = true,
                supported: GDBRemoteFeatures = [.noack],
                requested: GDBRemoteFeatures = [],
                capacity: Int = Configuration.PacketCapacity,
                packet: Int? = nil) {
    precondition(capacity > 0)
    if let packet {
      precondition(packet > 0)
    }
    self.acknowledgements = acknowledgements
    self.supported = supported
    advertised = false
    enabled = supported.intersection(requested).intersection(.shared)
    self.packet = packet
    self.capacity = capacity
  }

  internal mutating func negotiate(_ requested: GDBRemoteFeatures,
                                   packet: Int? = nil) {
    let explicit = enabled.intersection(.requested)
    enabled = supported.intersection(requested).intersection(.shared)
      .union(explicit)
    self.packet = packet
  }

  internal mutating func advertise() {
    advertised = true
  }

  internal mutating func enable(_ feature: GDBRemoteFeatures) {
    enabled.formUnion(feature.intersection(supported))
  }

  internal mutating func limit(_ capacity: Int) {
    precondition(capacity > 0)
    packet = min(capacity, packet ?? self.capacity)
  }

  internal var payload: Int {
    if let packet {
      min(capacity, packet)
    } else {
      capacity
    }
  }
}
