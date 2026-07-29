// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func emit(threads session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let start = count
    do throws(GDBHandlerError) {
      try emit(threads: session, state: state, memory: true)
    } catch .capacity {
      output.removeLast(count - start)
      try emit(threads: session, state: state, memory: false)
    }
  }

  private mutating func emit(threads session: borrowing DebugSession,
                             state: borrowing GDBRemoteSessionState,
                             memory: Bool) throws(GDBHandlerError) {
    try append(UInt8(ascii: "["))
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
          try append(UInt8(ascii: ","))
        }
        try append(UInt8(ascii: "{"))
        let stop: Debuggee.Stop? = switch thread.state {
        case .stopped(let stop): stop
        case .running, .stepping, .terminated: nil
        }
        if let stop {
          try emit(registers: stop.thread, session: session, state: state,
                   memory: memory)
        }
        try append("\"tid\":")
        try decimal(thread.identifier.thread.rawValue)
        let info = try? thread.identifier.info
        if let name = info?.name {
          try append(",\"name\":\"")
          try json(name)
          try append(UInt8(ascii: "\""))
        }
        if let queue = info?.queue {
          try append(",\"qaddr\":")
          try decimal(queue)
        }
        if let stop {
          try reason(stop, compatibility: state.compatibility)
        }
        if let core = stop?.core ?? info?.core {
          try append(",\"core\":")
          try decimal(UInt64(core))
        }
        try append(UInt8(ascii: "}"))
      }
    }
    try append(UInt8(ascii: "]"))
  }
}

extension GDBPacketWriter {
  private mutating func emit(registers thread: ProcessThreadIdentifier,
                             session: borrowing DebugSession,
                             state: borrowing GDBRemoteSessionState,
                             memory: Bool) throws(GDBHandlerError) {
    let start = count
    do throws(GDBHandlerError) {
      let snapshot = try translate(NativeRegisterState(thread))
      let description = RegisterDescription(snapshot.configuration)
      try append("\"registers\":{")
      var first = true
      for index in 0 ..< RegisterDescription.expedited.count {
        let index = Int(RegisterDescription.expedited[index])
        guard let register = description.record(index),
            let number =
                description.number(register,
                                   compatibility: state.compatibility) else {
          continue
        }
        if first {
          first = false
        } else {
          try append(UInt8(ascii: ","))
        }
        try append(UInt8(ascii: "\""))
        try decimal(UInt64(number))
        try append("\":\"")
        try emit(snapshot, register: register, model: description)
        try append(UInt8(ascii: "\""))
      }
      try append("},")
      if memory, let frame = try? snapshot.fp {
        try emit(memory: thread.process, frame: frame, session: session)
      }
    } catch .debuggee(let error) {
      output.removeLast(count - start)
      return error.log("register read", level: .warning)
    }
  }
}

extension GDBPacketWriter {
  private mutating func reason(_ stop: borrowing Debuggee.Stop,
                               compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    if compatibility == .lldb, stop.fault?.domain == .mach {
      switch stop.reason {
      case .breakpoint, .exception, .trace:
        try append(",\"reason\":\"exception\"")
        return try fault(stop, compatibility: compatibility)
      default:
        break
      }
    }
    switch stop.reason {
    case .breakpoint:
      try append(",\"reason\":\"breakpoint\"")
    case .executed:
      try append(",\"reason\":\"exec\"")
    case .exception:
      try append(",\"reason\":\"exception\"")
    case .interrupt:
      try append(",\"reason\":\"signal\",\"signal\":")
      let signal = compatibility.signal(.interrupt)
      try decimal(UInt64(signal))
    case .library:
      try append(",\"reason\":\"shared-library-event\"")
    case .signal(let signal):
      try append(",\"reason\":\"signal\",\"signal\":")
      try decimal(UInt64(signal))
    case .create, .spawn:
      try append(",\"reason\":\"fork\"")
    case .syscall:
      try append(",\"reason\":\"trace\"")
    case .fork, .vfork:
      if stop.reason == .fork {
        try append(",\"reason\":\"fork\"")
      } else {
        try append(",\"reason\":\"vfork\"")
      }
      if let child = stop.child {
        try append(",\"description\":\"")
        try decimal(child.process.rawValue)
        try append(UInt8(ascii: " "))
        try decimal(child.thread.rawValue)
        try append(UInt8(ascii: "\""))
      }
    case .trace:
      try append(",\"reason\":\"trace\"")
    case .vforkdone:
      try append(",\"reason\":\"vforkdone\"")
    case .watchpoint(_, let address):
      try append(",\"reason\":\"watchpoint\",\"description\":\"")
      try decimal(address.rawValue)
      try append(UInt8(ascii: "\""))
    }
    try fault(stop, compatibility: compatibility)
  }
}

extension GDBPacketWriter {
  private mutating func fault(_ stop: borrowing Debuggee.Stop,
                              compatibility: CompatibilityMode)
      throws(GDBHandlerError) {
    guard compatibility == .lldb, let fault = stop.fault else {
      return
    }
    if case .watchpoint = stop.reason {
      return
    }
    if fault.domain == .mach, let data = fault.data, let code = fault.code {
      try append(",\"metype\":")
      try decimal(code)
      try append(",\"medata\":[")
      for index in 0 ..< data.count {
        if index > 0 {
          try append(UInt8(ascii: ","))
        }
        try decimal(data[index])
      }
      return try append(UInt8(ascii: "]"))
    }
    if case .exception(let code) = stop.reason {
      if fault.domain == .windows {
        try append(",\"description\":\"")
        try exception(code, address: fault.address.rawValue, encoded: false)
        try append("\",\"signal\":")
        let signal = compatibility.signal(stop.reason)
        return try decimal(UInt64(signal))
      }
      try append(",\"metype\":")
      try decimal(code)
      try append(",\"medata\":[")
      if let data = fault.data {
        for index in 0 ..< data.count {
          if index > 0 {
            try append(UInt8(ascii: ","))
          }
          try decimal(data[index])
        }
      }
      return try append(UInt8(ascii: "]"))
    }
    guard case .signal(let signal) = stop.reason else {
      return
    }
    guard let description = fault.description(signal) else {
      return
    }
    try append(",\"description\":\"signal ")
    try append(description.name)
    if let detail = description.detail {
      try append(": ")
      try append(detail)
    }
    if let address = fault.location {
      try append(" (fault address=0x")
      try hex(address.rawValue)
      try append(")")
    }
    try append("\"")
  }
}
