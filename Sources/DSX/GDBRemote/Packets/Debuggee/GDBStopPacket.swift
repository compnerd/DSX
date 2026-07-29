// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  private borrowing func reply(_ stop: Debuggee.Stop,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try emit(stop, state: state, writer: &writer)
    if state.compatibility == .lldb, state.negotiation.advertised,
        state.negotiation.supported.contains(.libraries), state.modules {
      try writer.append("library:1;")
    }
    if state.compatibility == .gdb {
      state.selection.general = .thread(stop.thread)
      state.selection.resume = .thread(stop.thread)
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func expedited(_ thread: ProcessThreadIdentifier,
                                      state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let snapshot: NativeRegisterState
    do {
      snapshot = try NativeRegisterState(thread)
    } catch {
      return error.log("register read", level: .warning)
    }
    let description = RegisterDescription(snapshot.configuration)
    let compatibility = state.compatibility
    for index in 0 ..< RegisterDescription.expedited.count {
      let index = Int(RegisterDescription.expedited[index])
      guard let register = description.record(index),
          let number =
              description.number(register, compatibility: compatibility) else {
        continue
      }
      try hex(UInt64(number))
      try append(UInt8(ascii: ":"))
      try emit(snapshot, register: register, model: description)
      try append(UInt8(ascii: ";"))
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func fault(_ stop: borrowing Debuggee.Stop,
                                  compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    guard compatibility == .lldb, let fault = stop.fault else {
      return
    }
    if case .watchpoint = stop.reason {
      return
    }
    if fault.domain == .mach, let data = fault.data, let code = fault.code {
      try append("metype:")
      try hex(code)
      try append(";mecount:")
      try hex(UInt64(data.count))
      try append(UInt8(ascii: ";"))
      for index in 0 ..< data.count {
        try field("medata:", hex: data[index])
      }
      return
    }
    if case .exception(let code) = stop.reason {
      if fault.domain == .windows {
        try append("description:")
        try exception(code, address: fault.address.rawValue, encoded: true)
        return try append(UInt8(ascii: ";"))
      }
      try append("metype:")
      try hex(code)
      try append(";mecount:")
      try hex(UInt64(fault.data?.count ?? 0))
      try append(UInt8(ascii: ";"))
      if let data = fault.data {
        for index in 0 ..< data.count {
          try field("medata:", hex: data[index])
        }
      }
      return
    }
    guard case .signal(let signal) = stop.reason else {
      return
    }
    guard let description = fault.description(signal) else {
      return
    }
    try append("description:")
    try encoded("signal ")
    try encoded(description.name)
    if let detail = description.detail {
      try encoded(": ")
      try encoded(detail)
    }
    if let address = fault.location {
      try encoded(" (fault address=0x")
      try hexadecimal(address.rawValue)
      try encoded(")")
    }
    try append(UInt8(ascii: ";"))
  }
}

extension GDBPacketWriter {
  private mutating func hexadecimal(_ value: UInt64) throws(GDBHandlerError) {
    var shift = 60
    while shift > 0, value >> shift == 0 {
      shift -= 4
    }
    while shift >= 0 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      try hex(digit.hexadecimal)
      shift -= 4
    }
  }
}

extension DebugSession {
  private borrowing func reason(_ stop: borrowing Debuggee.Stop,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if case .watchpoint(let access, let address) = stop.reason {
      return try writer.watchpoint(access, address: address,
                                   compatibility: state.compatibility)
    }
    if try breakpoint(stop, state: state, writer: &writer) {
      return
    }
    if state.compatibility == .gdb {
      return try gdb(stop, writer: &writer)
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
      try writer.child(stop, name: "fork:")
    case .vfork:
      try writer.child(stop, name: "vfork:")
    default:
      break
    }
  }
}

extension DebugSession {
  private borrowing func gdb(_ stop: borrowing Debuggee.Stop,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    switch stop.reason {
    case .create:
      try writer.append("create:;")
    case .executed:
      try writer.append("exec:")
      do {
        let image = try image(stop.thread.process)
        try writer.encoded(image.path)
      } catch {
        DSX.log("failed to read executed image: \(error)", level: .warning,
                channel: .process)
      }
      try writer.append(UInt8(ascii: ";"))
    case .fork, .spawn:
      try writer.child(stop, name: "fork:")
    case .library:
      try writer.append("library:;")
    case .syscall(let number, let entry):
      try writer.append(entry ? "syscall_entry:" : "syscall_return:")
      try writer.hex(number)
      try writer.append(UInt8(ascii: ";"))
    case .vfork:
      try writer.child(stop, name: "vfork:")
    case .vforkdone:
      try writer.append("vforkdone:;")
    case .breakpoint, .exception, .interrupt, .signal, .trace, .watchpoint:
      break
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func child(_ stop: borrowing Debuggee.Stop,
                                  name: StaticString) throws(GDBHandlerError) {
    guard let child = stop.child else {
      return
    }
    try append(name)
    try thread(child, multiprocess: true)
    try append(UInt8(ascii: ";"))
  }
}

extension GDBPacketWriter {
  fileprivate mutating func watchpoint(_ access: Debuggee.Access,
                                       address: Debuggee.Address,
                                       compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    if compatibility == .lldb {
      try append("reason:watchpoint;description:")
      try encoded(address.rawValue)
      return try append(UInt8(ascii: ";"))
    }
    let kind: StaticString = switch access {
    case .execute, .write: "watch:"
    case .read: "rwatch:"
    case .readwrite: "awatch:"
    }
    try append(kind)
    try hex(address.rawValue)
    try append(UInt8(ascii: ";"))
  }
}

extension DebugSession {
  private borrowing func breakpoint(_ stop: borrowing Debuggee.Stop,
                                    state: borrowing GDBRemoteSessionState,
                                    writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> Bool {
    guard state.compatibility == .gdb, stop.reason == .breakpoint,
        let identifier = stop.breakpoint,
        let site = breakpoints.site(identifier) else {
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
}

extension DebugSession {
  internal borrowing func status(_ payload: borrowing Span<UInt8>,
                                 state: inout GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    if state.nonstop {
      state.stops.restart()
      try snapshot(state: &state)
      if let reply = state.stops.first {
        try writer.append(reply.span)
      } else {
        try writer.append("OK")
      }
      return .reply
    }
    guard !debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    if let stopped = state.selection.stopped,
        let thread = debuggee.state(stopped),
        case .stopped(let record) = thread {
      try reply(record, state: &state, writer: &writer)
      return .reply
    }
    for process in debuggee.processes {
      for thread in process.threads {
        if case .stopped(let record) = thread.state {
          try reply(record, state: &state, writer: &writer)
          return .reply
        }
      }
    }
    for process in debuggee.processes {
      if case .exited(let status) = process.state {
        try writer.exit(process.identifier, status: status, state: state)
        return .reply
      }
    }
    throw .debuggee(.state)
  }
}

extension DebugSession {
  @inline(never)
  internal borrowing func emit(_ event: Debuggee.Event,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch event {
    case .executed(let thread):
      let stop = Debuggee.Stop(thread: thread, reason: .executed)
      try reply(stop, state: &state, writer: &writer)
    case .exited(let process, let status):
      try writer.exit(process, status: status, state: state)
    case .forked(let fork):
      let stop = Debuggee.Stop(thread: fork.parent,
                               reason: fork.vfork ? .vfork : .fork,
                               child: fork.child)
      try reply(stop, state: &state, writer: &writer)
    case .started(let thread):
      let stop = Debuggee.Stop(thread: thread, reason: .create)
      try reply(stop, state: &state, writer: &writer)
    case .stopped(let stop):
      try reply(stop, state: &state, writer: &writer)
    case .terminated(let thread, let status):
      try writer.terminated(thread, status: status, state: state)
    case .image, .output:
      throw .unsupported
    }
    return .reply
  }
}

extension DebugSession {
  internal borrowing func emit(_ stop: Debuggee.Stop,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter,
                               registers: Bool = true) throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "T"))
    let signal = state.compatibility.signal(stop.reason)
    try writer.hex(signal)
    try writer.append("thread:")
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try writer.thread(stop.thread, multiprocess: multiprocess)
    try writer.append(UInt8(ascii: ";"))
    try reason(stop, state: state, writer: &writer)
    try writer.fault(stop, compatibility: state.compatibility)
    let info: Debuggee.Thread.Info?
    do {
      info = try stop.thread.info
    } catch {
      error.log("failed to read thread information", level: .warning)
      info = nil
    }
    if let name = info?.name {
      try writer.append("name:")
      try writer.append(name.utf8Span.span)
      try writer.append(UInt8(ascii: ";"))
    }
    if let queue = info?.queue {
      try writer.field("qaddr:", hex: queue)
    }
    if registers {
      try writer.expedited(stop.thread, state: state)
    }
    if state.negotiation.enabled.contains(.stopthreads) {
      try writer.append("threads:")
      let list = state.compatibility == .gdb && multiprocess
      var first = true
      for process in debuggee.processes
          where process.identifier == stop.thread.process {
        for thread in process.threads
            where debuggee.alive(thread.identifier) {
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
      collect: for process in debuggee.processes
          where process.identifier == stop.thread.process {
        for thread in process.threads
            where debuggee.alive(thread.identifier) {
          guard count < programs.count else {
            complete = false
            break collect
          }
          do {
            let registers = try NativeRegisterState(thread.identifier)
            programs[count] = try registers.pc
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
}

extension GDBPacketWriter {
  internal mutating func exception(_ code: UInt64, address: UInt64,
                                   encoded encoding: Bool)
      throws(GDBHandlerError) {
    if encoding {
      try encoded("Exception 0x")
      try hexadecimal(code)
      try encoded(" encountered at address 0x")
      try hexadecimal(address)
    } else {
      try append("Exception 0x")
      try hex(code)
      try append(" encountered at address 0x")
      try hex(address)
    }
  }
}
