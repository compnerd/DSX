// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBStopPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    if state.nonstop {
      state.stops.restart()
      try session.snapshot(state: &state)
      if let reply = state.stops.first {
        try writer.append(reply.span)
      } else {
        try writer.append("OK")
      }
      return .reply
    }
    guard !session.debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    if let stopped = state.selection.stopped,
        let thread = session.debuggee.state(stopped),
        case .stopped(let record) = thread {
      try reply(record, session: &session, state: &state, writer: &writer)
      return .reply
    }
    for process in session.debuggee.processes {
      for thread in process.threads {
        if case .stopped(let record) = thread.state {
          try reply(record, session: &session, state: &state, writer: &writer)
          return .reply
        }
      }
    }
    for process in session.debuggee.processes {
      if case .exited(let status) = process.state {
        try exit(process.identifier, status: status, state: state,
                 writer: &writer)
        return .reply
      }
    }
    throw .debuggee(.state)
  }

  internal static func write(_ event: Debuggee.Event,
                             session: inout DebugSession,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch event {
    case .executed(let thread):
      let stop = Debuggee.Stop(thread: thread, reason: .executed)
      try reply(stop, session: &session, state: &state, writer: &writer)
    case .exited(let process, let status):
      try exit(process, status: status, state: state, writer: &writer)
    case .forked(let fork):
      let stop = Debuggee.Stop(thread: fork.parent,
                               reason: fork.vfork ? .vfork : .fork,
                               child: fork.child)
      try reply(stop, session: &session, state: &state, writer: &writer)
    case .started(let thread):
      let stop = Debuggee.Stop(thread: thread, reason: .create)
      try reply(stop, session: &session, state: &state, writer: &writer)
    case .stopped(let stop):
      try reply(stop, session: &session, state: &state, writer: &writer)
    case .terminated(let thread, let status):
      try terminated(thread, status: status, state: state, writer: &writer)
    case .image, .output:
      throw .unsupported
    }
    return .reply
  }

  internal static func stop(_ stop: Debuggee.Stop, session: inout DebugSession,
                            state: borrowing GDBRemoteSessionState,
                            writer: inout GDBPacketWriter,
                            registers: Bool = true) throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "T"))
    try writer.hex(signal(stop.reason, compatibility: state.compatibility))
    try writer.append("thread:")
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try writer.thread(stop.thread, multiprocess: multiprocess)
    try writer.append(UInt8(ascii: ";"))
    try reason(stop, session: session, state: state, writer: &writer)
    try fault(stop, compatibility: state.compatibility, writer: &writer)
    let info: Debuggee.Thread.Info?
    do {
      info = try stop.thread.info
    } catch {
      DSX.log("failed to read thread information: \(error)", level: .warning,
              channel: .process)
      info = nil
    }
    if let name = info?.name {
      try writer.append("name:")
      for byte in name.utf8 {
        try writer.append(byte)
      }
      try writer.append(UInt8(ascii: ";"))
    }
    if registers {
      try expedited(stop.thread, state: state, writer: &writer)
    }
    if state.negotiation.enabled.contains(.stopthreads) {
      try writer.append("threads:")
      let list = state.compatibility == .gdb && multiprocess
      var first = true
      for process in session.debuggee.processes
          where process.identifier == stop.thread.process {
        for thread in process.threads
            where session.debuggee.alive(thread.identifier) {
          if first {
            first = false
          } else {
            try writer.append(UInt8(ascii: ","))
          }
          try writer.thread(thread.identifier, multiprocess: list)
        }
      }
      try writer.append(UInt8(ascii: ";"))
      var programs = Configuration.ThreadStorage<UInt64?> { _ in nil }
      var count = 0
      var complete = true
      collect: for process in session.debuggee.processes
          where process.identifier == stop.thread.process {
        for thread in process.threads
            where session.debuggee.alive(thread.identifier) {
          guard count < programs.count else {
            complete = false
            break collect
          }
          do {
            programs[count] = try session.program(thread.identifier)
          } catch {
            complete = false
            break collect
          }
          count += 1
        }
      }
      if complete {
        try writer.append("thread-pcs:")
      }
      first = true
      for index in 0 ..< count where complete {
        if first {
          first = false
        } else {
          try writer.append(UInt8(ascii: ","))
        }
        if let program = programs[index] {
          try writer.hex(program)
        }
      }
      if complete {
        try writer.append(UInt8(ascii: ";"))
      }
    }
  }

  internal static func detail(_ signal: CInt, code: UInt64?) -> StaticString? {
    guard let code else {
      return nil
    }
    return switch (signal, code) {
    case (7, 1): "illegal alignment"
    case (7, 2): "illegal address"
    case (7, 3): "hardware error"
    case (11, 1): "address not mapped to object"
    case (11, 2): "invalid permissions for mapped object"
    case (11, 3): "failed address bounds checks"
    case (11, 8): "async tag check fault"
    case (11, 9): "sync tag check fault"
    case (11, 10): "control protection fault"
    case (11, 0x80): "invalid address"
    default: nil
    }
  }

  internal static func exception(_ code: UInt64, address: UInt64, encoded: Bool,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if encoded {
      try writer.encoded("Exception 0x")
      try hexadecimal(code, writer: &writer)
      try writer.encoded(" encountered at address 0x")
      try hexadecimal(address, writer: &writer)
    } else {
      try writer.append("Exception 0x")
      try writer.hex(code)
      try writer.append(" encountered at address 0x")
      try writer.hex(address)
    }
  }

  internal static func signal(_ reason: Debuggee.StopReason,
                              compatibility: CompatibilityMode = .gdb)
      -> UInt8 {
    switch reason {
    case .interrupt:
      compatibility == .lldb ? Host.interrupt : 0x02
    case .signal(let signal):
      GDBSignal.protocol(signal, compatibility: compatibility)
    case .exception(let code):
      code == 0x91 ? 0x91 : 0x05
    case .breakpoint, .create, .executed, .fork, .library, .spawn, .syscall,
         .trace, .vfork, .vforkdone, .watchpoint:
      0x05
    }
  }
}

private func reply(_ stop: Debuggee.Stop, session: inout DebugSession,
                   state: inout GDBRemoteSessionState,
                   writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  try GDBStopPacket.stop(stop, session: &session, state: state, writer: &writer)
  if state.compatibility == .lldb, state.negotiation.advertised,
      state.negotiation.supported.contains(.libraries), state.modules {
    try writer.append("library:1;")
  }
  if state.compatibility == .gdb {
    state.selection.general = .thread(stop.thread)
    state.selection.resume = .thread(stop.thread)
  }
}

private func expedited(_ thread: ProcessThreadIdentifier,
                       state: borrowing GDBRemoteSessionState,
                       writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  let snapshot: DebugSession.RegisterState
  do {
    snapshot = try NativeRegisters.snapshot(thread)
  } catch {
    return DSX.log("failed to read stop registers: \(error)", level: .warning,
                   channel: .process)
  }
  let description = RegisterDescription()
  let compatibility = state.compatibility
  for index in 0 ..< description.count {
    guard let register = description.register(index),
        register.role?.expedited == true,
        let number = description.number(register,
                                        compatibility: compatibility) else {
      continue
    }
    try writer.hex(UInt64(number))
    try writer.append(UInt8(ascii: ":"))
    try GDBRegisterPacket.read(snapshot, register: register, model: description,
                               writer: &writer)
    try writer.append(UInt8(ascii: ";"))
  }
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
    try writer.append("metype:")
    try writer.hex(code)
    try writer.append(";mecount:")
    try writer.hex(UInt64(data.count))
    try writer.append(UInt8(ascii: ";"))
    for index in 0 ..< data.count {
      try writer.field("medata:", hex: data[index])
    }
    return
  }
  if case .exception(let code) = stop.reason {
    if fault.domain == .windows {
      try writer.append("description:")
      try GDBStopPacket.exception(code, address: fault.address.rawValue,
                                  encoded: true, writer: &writer)
      return try writer.append(UInt8(ascii: ";"))
    }
    try writer.append("metype:")
    try writer.hex(code)
    try writer.append(";mecount:")
    try writer.hex(UInt64(fault.data?.count ?? 0))
    try writer.append(UInt8(ascii: ";"))
    if let data = fault.data {
      for index in 0 ..< data.count {
        try writer.field("medata:", hex: data[index])
      }
    }
    return
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
  try writer.append("description:")
  try writer.encoded("signal ")
  try writer.encoded(name)
  if fault.domain == .posix,
      let detail = GDBStopPacket.detail(signal, code: fault.code) {
    try writer.encoded(": ")
    try writer.encoded(detail)
  }
  try writer.encoded(" (fault address=0x")
  try hexadecimal(fault.address.rawValue, writer: &writer)
  try writer.encoded(")")
  try writer.append(UInt8(ascii: ";"))
}

private func hexadecimal(_ value: UInt64, writer: inout GDBPacketWriter)
    throws(GDBHandlerError) {
  var shift = 60
  while shift > 0, value >> shift == 0 {
    shift -= 4
  }
  while shift >= 0 {
    let digit = UInt8(truncatingIfNeeded: value >> shift)
    try writer.hex(GDBPacketWriter.hexadecimal(digit))
    shift -= 4
  }
}

private func reason(_ stop: borrowing Debuggee.Stop,
                    session: borrowing DebugSession,
                    state: borrowing GDBRemoteSessionState,
                    writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  if case .watchpoint(let access, let address) = stop.reason {
    return try watchpoint(access, address: address,
                          compatibility: state.compatibility, writer: &writer)
  }
  if try breakpoint(stop, session: session, state: state, writer: &writer) {
    return
  }
  if state.compatibility == .gdb {
    return try gdb(stop, session: session, writer: &writer)
  }
  if stop.fault?.domain == .mach {
    switch stop.reason {
    case .breakpoint, .exception, .trace:
      return
    default:
      break
    }
  }
  try writer.append("reason:")
  switch stop.reason {
  case .breakpoint: try writer.append("breakpoint")
  case .create: try writer.append("create")
  case .executed: try writer.append("exec")
  case .exception: try writer.append("exception")
  case .fork: try writer.append("fork")
  case .interrupt, .signal: try writer.append("signal")
  case .library: try writer.append("shared-library-event")
  case .spawn: try writer.append("fork")
  case .syscall: try writer.append("trace")
  case .trace: try writer.append("trace")
  case .vfork: try writer.append("vfork")
  case .vforkdone: try writer.append("vforkdone")
  case .watchpoint: try writer.append("watchpoint")
  }
  try writer.append(UInt8(ascii: ";"))
  switch stop.reason {
  case .fork, .spawn:
    try child(stop, name: "fork:", writer: &writer)
  case .vfork:
    try child(stop, name: "vfork:", writer: &writer)
  default:
    break
  }
}

private func gdb(_ stop: borrowing Debuggee.Stop,
                 session: borrowing DebugSession,
                 writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  switch stop.reason {
  case .create:
    try writer.append("create:;")
  case .executed:
    try writer.append("exec:")
    do {
      let image = try session.image(stop.thread.process)
      try writer.encoded(image.path)
    } catch {
      DSX.log("failed to read executed image: \(error)", level: .warning,
              channel: .process)
    }
    try writer.append(UInt8(ascii: ";"))
  case .fork, .spawn:
    try child(stop, name: "fork:", writer: &writer)
  case .library:
    try writer.append("library:;")
  case .syscall(let number, let entry):
    try writer.append(entry ? "syscall_entry:" : "syscall_return:")
    try writer.hex(number)
    try writer.append(UInt8(ascii: ";"))
  case .vfork:
    try child(stop, name: "vfork:", writer: &writer)
  case .vforkdone:
    try writer.append("vforkdone:;")
  case .breakpoint, .exception, .interrupt, .signal, .trace, .watchpoint:
    break
  }
}

private func child(_ stop: borrowing Debuggee.Stop, name: StaticString,
                   writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  guard let child = stop.child else {
    return
  }
  try writer.append(name)
  try writer.thread(child, multiprocess: true)
  try writer.append(UInt8(ascii: ";"))
}

private func watchpoint(_ access: Debuggee.Access, address: Debuggee.Address,
                        compatibility: CompatibilityMode,
                        writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  if compatibility == .lldb {
    try writer.append("reason:watchpoint;description:")
    try encoded(address.rawValue, writer: &writer)
    return try writer.append(UInt8(ascii: ";"))
  }
  let kind: StaticString = switch access {
  case .execute, .write: "watch:"
  case .read: "rwatch:"
  case .readwrite: "awatch:"
  }
  try writer.append(kind)
  try writer.hex(address.rawValue)
  try writer.append(UInt8(ascii: ";"))
}

private func encoded(_ value: UInt64, writer: inout GDBPacketWriter)
    throws(GDBHandlerError) {
  var divisor: UInt64 = 1
  while value / divisor >= 10 {
    divisor *= 10
  }
  while divisor > 0 {
    let byte = UInt8(value / divisor % 10) + UInt8(ascii: "0")
    try writer.hex(byte)
    divisor /= 10
  }
}

private func breakpoint(_ stop: borrowing Debuggee.Stop,
                        session: borrowing DebugSession,
                        state: borrowing GDBRemoteSessionState,
                        writer: inout GDBPacketWriter)
    throws(GDBHandlerError) -> Bool {
  guard state.compatibility == .gdb, stop.reason == .breakpoint,
      let identifier = stop.breakpoint,
      let site = session.breakpoints.site(identifier) else {
    return false
  }
  switch site.kind {
  case .software:
    guard state.negotiation.enabled.contains(.swbreak) else {
      return false
    }
    try writer.append("swbreak:;")
  case .hardware:
    guard state.negotiation.enabled.contains(.hwbreak) else {
      return false
    }
    try writer.append("hwbreak:;")
  case .watchpoint:
    return false
  }
  return true
}
