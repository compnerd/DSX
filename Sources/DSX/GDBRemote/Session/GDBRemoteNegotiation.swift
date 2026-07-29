// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

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
