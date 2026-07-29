// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteSessionState {
  internal mutating func supported(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    var enabled = GDBRemoteFeatures()
    var packet: Int?
    guard reader.empty || reader.consume(UInt8(ascii: ":")) ||
        reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }

    while reader.count > 0 {
      var matched = false
      for index in 0 ..< kDescriptors.count {
        let descriptor = kDescriptors[index]
        guard descriptor.request, reader.consume(descriptor.name) else {
          continue
        }
        if try reader.enabled() {
          enabled.insert(descriptor.feature)
        }
        try reader.separator()
        matched = true
        break
      }
      if matched {
        continue
      }
      if reader.consume("PacketSize=") {
        let capacity = try reader.hex()
        guard capacity >= 3, capacity <= UInt64(Int.max) else {
          throw .malformed
        }
        packet = Int(capacity)
        try reader.separator()
        continue
      }
      reader.skip(UInt8(ascii: ";"))
      _ = reader.consume(UInt8(ascii: ";"))
    }

    var proposed = negotiation
    proposed.negotiate(enabled, packet: packet)
    try writer.emit(proposed, compatibility: compatibility)
    proposed.advertise()
    negotiation = proposed
  }
}

extension GDBPacketWriter {
  @inline(never)
  fileprivate mutating func emit(_ negotiation: borrowing GDBRemoteNegotiation,
                                 compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    try append("PacketSize=")
    try hex(UInt64(negotiation.capacity))
    let limit = min(capacity, negotiation.payload)
    guard count <= limit else {
      throw .capacity
    }
    let prefix: StaticString = ";SupportedWatchpointTypes="
    let features = HardwareBreakpoint.features
    let required = prefix.utf8CodeUnitCount + features.utf8CodeUnitCount
    if features.utf8CodeUnitCount > 0, count + required <= limit {
      try append(prefix)
      try append(features)
    }
    for index in 0 ..< kDescriptors.count {
      let descriptor = kDescriptors[index]
      guard negotiation.supported.contains(descriptor.feature),
          descriptor.feature.advertise(compatibility: compatibility,
                                       enabled: negotiation.enabled) else {
        continue
      }
      let required = descriptor.name.utf8CodeUnitCount + 2
      guard limit - count >= required else {
        break
      }
      try append(";")
      try append(descriptor.name)
      if descriptor.feature == .options {
        try append("=2")
      } else {
        try append("+")
      }
    }
  }
}

extension GDBRemoteFeatures {
  fileprivate func advertise(compatibility: CompatibilityMode,
                             enabled: GDBRemoteFeatures) -> Bool {
    switch self {
    case .libraries where compatibility == .lldb &&
        DebugCapabilities.current.contains(.images):
      false
    case _ where compatibility == .lldb && hidden:
      false
    case .ranges, .native:
      compatibility == .lldb
    case .multiprocess:
      enabled.contains(.multiprocess)
    case .fork, .vfork:
      enabled.contains(.multiprocess) && enabled.contains(self)
    default:
      true
    }
  }

  private var hidden: Bool {
    switch self {
    case .binary, .events, .executable, .execute, .hwbreak, .map,
        .options, .randomization, .reset, .swbreak, .syscalls, .threads,
        .unset, .vcont:
      true
    default:
      false
    }
  }
}

extension GDBPacketReader {
  fileprivate mutating func enabled() throws(GDBHandlerError) -> Bool {
    switch try read() {
    case UInt8(ascii: "+"): true
    case UInt8(ascii: "-"), UInt8(ascii: "?"): false
    default: throw .malformed
    }
  }
}

private let kDescriptors: InlineArray<32, GDBFeatureDescriptor> = [
  GDBFeatureDescriptor(.noack, "QStartNoAckMode", request: false),
  GDBFeatureDescriptor(.multiprocess, "multiprocess"),
  GDBFeatureDescriptor(.features, "qXfer:features:read"),
  GDBFeatureDescriptor(.executable, "qXfer:exec-file:read"),
  GDBFeatureDescriptor(.auxiliary, "qXfer:auxv:read"),
  GDBFeatureDescriptor(.libraries, "qXfer:libraries:read"),
  GDBFeatureDescriptor(.svr4, "qXfer:libraries-svr4:read"),
  GDBFeatureDescriptor(.threads, "qXfer:threads:read"),
  GDBFeatureDescriptor(.osdata, "qXfer:osdata:read"),
  GDBFeatureDescriptor(.signal, "qXfer:siginfo:read"),
  GDBFeatureDescriptor(.threadsuffix, "QThreadSuffixSupported", request: false),
  GDBFeatureDescriptor(.stopthreads, "QListThreadsInStopReply", request: false),
  GDBFeatureDescriptor(.pass, "QPassSignals", request: false),
  GDBFeatureDescriptor(.fork, "fork-events"),
  GDBFeatureDescriptor(.vfork, "vfork-events"),
  GDBFeatureDescriptor(.randomization, "QDisableRandomization", request: false),
  GDBFeatureDescriptor(.reset, "QEnvironmentReset", request: false),
  GDBFeatureDescriptor(.unset, "QEnvironmentUnset", request: false),
  GDBFeatureDescriptor(.vcont, "vContSupported"),
  GDBFeatureDescriptor(.swbreak, "swbreak"),
  GDBFeatureDescriptor(.hwbreak, "hwbreak"),
  GDBFeatureDescriptor(.savecore, "qSaveCore", request: false),
  GDBFeatureDescriptor(.nonstop, "QNonStop", request: false),
  GDBFeatureDescriptor(.batch, "jMultiBreakpoint", request: false),
  GDBFeatureDescriptor(.binary, "binary-upload", request: false),
  GDBFeatureDescriptor(.execute, "exec-events"),
  GDBFeatureDescriptor(.map, "qXfer:memory-map:read"),
  GDBFeatureDescriptor(.events, "QThreadEvents", request: false),
  GDBFeatureDescriptor(.syscalls, "QCatchSyscalls", request: false),
  GDBFeatureDescriptor(.options, "QThreadOptions", request: false),
  GDBFeatureDescriptor(.ranges, "MultiMemRead", request: false),
  GDBFeatureDescriptor(.native, "native-signals", request: false),
]

extension GDBPacketReader {
  fileprivate mutating func separator() throws(GDBHandlerError) {
    guard empty || consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
  }
}

private struct GDBFeatureDescriptor {
  fileprivate let feature: GDBRemoteFeatures
  fileprivate let name: StaticString
  fileprivate let request: Bool

  fileprivate init(_ feature: GDBRemoteFeatures, _ name: StaticString,
                   request: Bool = true) {
    self.feature = feature
    self.name = name
    self.request = request
  }
}
