// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeProcess {
  private static let startup = Duration.seconds(30)

  internal borrowing func notification(timeout: Duration =
                                           NativeProcess.startup)
      throws(Debuggee.Error) -> UInt16 {
    let deadline = try Deadline(timeout, now: Host.time)
    var port = ChildPort()
    while true {
      let remaining = try deadline.remaining(at: Host.time)
      guard remaining > .zero else {
        throw .state
      }
      let interval = min(remaining, Tuning.Process.polling)
      if let byte = try byte(timeout: interval),
          let port = try port.consume(byte) {
        return port
      }
    }
  }

  internal borrowing func wait(timeout: Duration?,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let result: Debuggee.ProgramStatus
    do {
      let deadline = if let timeout {
        try Deadline(timeout, now: Host.time)
      } else {
        nil as Deadline?
      }
      while true {
        try drain(Tuning.Process.capacity * Tuning.Process.burst, into: &output)
        if let status = try status(timeout: .zero) {
          result = .completed(status)
          break
        }
        let remaining =
            try deadline?.remaining(at: Host.time) ?? Tuning.Process.polling
        if remaining == .zero {
          try terminate()
          result = .timeout
          break
        }
        let interval = min(remaining, Tuning.Process.polling)
        if let status = try status(timeout: interval) {
          result = .completed(status)
          break
        }
      }
    } catch {
      try? terminate()
      throw error
    }
    try drain(output.freeCapacity, into: &output)
    return result
  }

  @inline(never)
  private borrowing func drain(_ limit: Int,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let capacity = Tuning.Process.capacity
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(Debuggee.Error) in
      var remaining = limit
      while remaining > 0 {
        let count = try read(buffer)
        guard count > 0 else {
          return
        }
        let retained = min(count, output.freeCapacity)
        for index in 0 ..< retained {
          output.append(buffer[index])
        }
        remaining -= min(count, remaining)
      }
    })
  }
}
