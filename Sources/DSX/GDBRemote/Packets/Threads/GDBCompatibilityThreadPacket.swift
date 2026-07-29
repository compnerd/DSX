// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadStopInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection =
        try GDBThreadIdentifier.parse(payload, debuggee: session.debuggee)
    guard case .thread(let identifier) = selection,
        let thread = session.debuggee.state(identifier) else {
      throw .debuggee(.thread)
    }
    let reply = switch thread {
    case .stopped(let stop): (stop, true)
    case .running, .stepping:
      (Debuggee.Stop(thread: identifier, reason: .signal(0)), false)
    case .terminated: throw .debuggee(.thread)
    }
    try GDBStopPacket.stop(reply.0, session: &session, state: state,
                           writer: &writer, registers: reply.1)
    return .reply
  }
}

internal enum GDBThreadExtraInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let selection =
        try GDBThreadIdentifier.parse(payload, debuggee: session.debuggee)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    let info = try translate(thread.info)
    let name = info.name ?? "thread \(thread.thread.rawValue)"
    try writer.encoded(name)
  }
}

internal enum GDBThreadsInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try writer.append(UInt8(ascii: "["))
    var first = true
    for process in session.debuggee.processes {
      if let selected = state.selection.stopped?.process,
          process.identifier != selected {
        continue
      }
      for thread in process.threads {
        guard session.debuggee.alive(thread.identifier) else {
          continue
        }
        if first {
          first = false
        } else {
          try writer.append(UInt8(ascii: ","))
        }
        try writer.append(UInt8(ascii: "{"))
        let stop: Debuggee.Stop? = switch thread.state {
        case .stopped(let stop): stop
        case .running, .stepping, .terminated: nil
        }
        if let stop {
          try registers(stop.thread, session: &session, state: state,
                        writer: &writer)
        }
        try writer.append("\"tid\":")
        try writer.decimal(thread.identifier.thread.rawValue)
        let info = try? thread.identifier.info
        if let name = info?.name {
          try writer.append(",\"name\":\"")
          try writer.json(name)
          try writer.append(UInt8(ascii: "\""))
        }
        if let stop {
          try reason(stop, compatibility: state.compatibility, writer: &writer)
        }
        if let core = stop?.core ?? info?.core {
          try writer.append(",\"core\":")
          try writer.decimal(UInt64(core))
        }
        try writer.append(UInt8(ascii: "}"))
      }
    }
    try writer.append(UInt8(ascii: "]"))
    return .reply
  }
}

private func registers(_ thread: ProcessThreadIdentifier,
                       session: inout DebugSession,
                       state: borrowing GDBRemoteSessionState,
                       writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  let values: InlineArray<3, ExpeditedRegisterValue?>
  do {
    values = try session.expedited(thread, compatibility: state.compatibility)
  } catch {
    return DSX.log("failed to read thread registers: \(error)", level: .warning,
                   channel: .process)
  }
  try writer.append("\"registers\":{")
  var first = true
  for index in 0 ..< values.count {
    guard let value = values[index] else {
      continue
    }
    if first {
      first = false
    } else {
      try writer.append(UInt8(ascii: ","))
    }
    try writer.append(UInt8(ascii: "\""))
    try writer.decimal(UInt64(value.number))
    try writer.append("\":\"")
    for index in 0 ..< value.size {
      let byte = ABI.endian == .little ? index : value.size - index - 1
      let shift = UInt64(byte * 8)
      try writer.hex(UInt8(truncatingIfNeeded: value.value >> shift))
    }
    try writer.append(UInt8(ascii: "\""))
  }
  try writer.append(UInt8(ascii: "}"))
  try writer.append(UInt8(ascii: ","))
}

private func reason(_ stop: borrowing Debuggee.Stop,
                    compatibility: CompatibilityMode,
                    writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  if compatibility == .lldb, stop.fault?.domain == .mach {
    switch stop.reason {
    case .breakpoint, .exception, .trace:
      try writer.append(",\"reason\":\"exception\"")
      return try fault(stop, compatibility: compatibility, writer: &writer)
    default:
      break
    }
  }
  switch stop.reason {
  case .breakpoint:
    try writer.append(",\"reason\":\"breakpoint\"")
  case .executed:
    try writer.append(",\"reason\":\"exec\"")
  case .exception:
    try writer.append(",\"reason\":\"exception\"")
  case .interrupt:
    try writer.append(",\"reason\":\"signal\",\"signal\":")
    let signal = GDBStopPacket.signal(.interrupt, compatibility: compatibility)
    try writer.decimal(UInt64(signal))
  case .library:
    try writer.append(",\"reason\":\"shared-library-event\"")
  case .signal(let signal):
    try writer.append(",\"reason\":\"signal\",\"signal\":")
    try writer.decimal(UInt64(signal))
  case .create, .spawn:
    try writer.append(",\"reason\":\"fork\"")
  case .syscall:
    try writer.append(",\"reason\":\"trace\"")
  case .fork, .vfork:
    if stop.reason == .fork {
      try writer.append(",\"reason\":\"fork\"")
    } else {
      try writer.append(",\"reason\":\"vfork\"")
    }
    if let child = stop.child {
      try writer.append(",\"description\":\"")
      try writer.decimal(child.process.rawValue)
      try writer.append(UInt8(ascii: " "))
      try writer.decimal(child.thread.rawValue)
      try writer.append(UInt8(ascii: "\""))
    }
  case .trace:
    try writer.append(",\"reason\":\"trace\"")
  case .vforkdone:
    try writer.append(",\"reason\":\"vforkdone\"")
  case .watchpoint(_, let address):
    try writer.append(",\"reason\":\"watchpoint\",\"description\":\"")
    try writer.decimal(address.rawValue)
    try writer.append(UInt8(ascii: "\""))
  }
  try fault(stop, compatibility: compatibility, writer: &writer)
}

private func fault(_ stop: borrowing Debuggee.Stop,
                   compatibility: CompatibilityMode,
                   writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  guard compatibility == .lldb, let fault = stop.fault else {
    return
  }
  if case .watchpoint = stop.reason {
    return
  }
  if fault.domain == .mach, let data = fault.data, let code = fault.code {
    try writer.append(",\"metype\":")
    try writer.decimal(code)
    try writer.append(",\"medata\":[")
    for index in 0 ..< data.count {
      if index > 0 {
        try writer.append(UInt8(ascii: ","))
      }
      try writer.decimal(data[index])
    }
    return try writer.append(UInt8(ascii: "]"))
  }
  if case .exception(let code) = stop.reason {
    if fault.domain == .windows {
      try writer.append(",\"description\":\"")
      try GDBStopPacket.exception(code, address: fault.address.rawValue,
                                  encoded: false, writer: &writer)
      try writer.append("\",\"signal\":")
      let signal =
          GDBStopPacket.signal(stop.reason, compatibility: compatibility)
      return try writer.decimal(UInt64(signal))
    }
    try writer.append(",\"metype\":")
    try writer.decimal(code)
    try writer.append(",\"medata\":[")
    if let data = fault.data {
      for index in 0 ..< data.count {
        if index > 0 {
          try writer.append(UInt8(ascii: ","))
        }
        try writer.decimal(data[index])
      }
    }
    return try writer.append(UInt8(ascii: "]"))
  }
  guard case .signal(let signal) = stop.reason else {
    return
  }
  let name: StaticString? = switch signal {
  case 7: "SIGBUS"
  case 11: "SIGSEGV"
  default: nil
  }
  guard let name else {
    return
  }
  try writer.append(",\"description\":\"signal ")
  try writer.append(name)
  if fault.domain == .posix,
      let detail = GDBStopPacket.detail(signal, code: fault.code) {
    try writer.append(": ")
    try writer.append(detail)
  }
  try writer.append(" (fault address=0x")
  try writer.hex(fault.address.rawValue)
  try writer.append(")\"")
}
