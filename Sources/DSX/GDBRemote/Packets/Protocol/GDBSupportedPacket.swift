// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBSupportedPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    var enabled = GDBRemoteFeatures()
    var packet: Int?
    if reader.empty {
      state.negotiation.negotiate(enabled)
      return try advertise(state: &state, writer: &writer)
    }
    guard reader.consume(UInt8(ascii: ":")) ||
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
        try feature(descriptor.feature, reader: &reader, enabled: &enabled)
        try reader.separator()
        matched = true
        break
      }
      if matched {
        continue
      }
      if reader.consume("PacketSize=") {
        let capacity = try reader.hex()
        guard capacity > 0, capacity <= UInt64(Int.max) else {
          throw .malformed
        }
        packet = Int(capacity)
        try reader.separator()
        continue
      }
      reader.skip(UInt8(ascii: ";"))
      _ = reader.consume(UInt8(ascii: ";"))
    }

    state.negotiation.negotiate(enabled, packet: packet)
    try advertise(state: &state, writer: &writer)
  }
}

private func advertise(state: inout GDBRemoteSessionState,
                       writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  state.negotiation.advertise()
  try writer.append("PacketSize=")
  try writer.hex(UInt64(state.negotiation.capacity))
  let capacity = min(writer.capacity, state.negotiation.payload)
  let prefix: StaticString = ";SupportedWatchpointTypes="
  let features = HardwareBreakpoint.features
  let required = prefix.utf8CodeUnitCount + features.utf8CodeUnitCount
  if features.utf8CodeUnitCount > 0, writer.count + required <= capacity {
    try writer.append(prefix)
    try writer.append(features)
  }
  for index in 0 ..< kDescriptors.count {
    let descriptor = kDescriptors[index]
    guard state.negotiation.supported.contains(descriptor.feature),
        advertise(descriptor.feature, compatibility: state.compatibility,
                  enabled: state.negotiation.enabled) else {
      continue
    }
    let required = descriptor.name.utf8CodeUnitCount + 2
    guard capacity - writer.count >= required else {
      break
    }
    try writer.append(";")
    try writer.append(descriptor.name)
    if descriptor.feature == .options {
      try writer.append("=2")
    } else {
      try writer.append("+")
    }
  }
}

private func advertise(_ feature: GDBRemoteFeatures,
                       compatibility: CompatibilityMode,
                       enabled: GDBRemoteFeatures) -> Bool {
  switch feature {
  case .libraries where compatibility == .lldb &&
      DebugCapabilities.current.contains(.images):
    false
  case let feature where compatibility == .lldb && hidden(feature):
    false
  case .ranges, .native:
    compatibility == .lldb
  case .multiprocess:
    enabled.contains(.multiprocess)
  case .fork, .vfork:
    enabled.contains(.multiprocess) && enabled.contains(feature)
  default:
    true
  }
}

private func hidden(_ feature: GDBRemoteFeatures) -> Bool {
  switch feature {
  case .binary, .events, .executable, .execute, .hwbreak, .map,
      .options, .randomization, .reset, .swbreak, .syscalls, .threads,
      .unset, .vcont:
    true
  default:
    false
  }
}

private func feature(_ feature: GDBRemoteFeatures,
                     reader: inout GDBPacketReader,
                     enabled: inout GDBRemoteFeatures) throws(GDBHandlerError) {
  let flag = try reader.read()
  switch flag {
  case UInt8(ascii: "+"):
    enabled.insert(feature)
  case UInt8(ascii: "-"), UInt8(ascii: "?"):
    break
  default:
    throw .malformed
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
