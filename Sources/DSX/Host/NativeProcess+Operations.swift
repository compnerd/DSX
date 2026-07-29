// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeProcess {
  internal borrowing func notification(timeout: UInt64 =
                                           Configuration.Process.Startup)
      throws(Debuggee.Error) -> UInt16 {
    let deadline = try Deadline(milliseconds: timeout, now: Host.time)
    var port = ChildPort()
    while true {
      let remaining = try deadline.remaining(at: Host.time)
      guard remaining > 0 else {
        throw .state
      }
      let interval = Int32(min(remaining, Configuration.Process.Interval))
      if let byte = try byte(timeout: interval),
          let port = try port.consume(byte) {
        return port
      }
    }
  }

  internal borrowing func wait(timeout: UInt64,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let result: Debuggee.ProgramStatus
    do {
      let deadline = try Deadline(seconds: timeout, now: Host.time)
      while true {
        try drain(Configuration.Process.Capacity * Configuration.Process.Burst,
                  into: &output)
        if let status = try status(timeout: 0) {
          result = .completed(status)
          break
        }
        let remaining = try deadline.remaining(at: Host.time)
        if remaining == 0 {
          try terminate()
          result = .timeout
          break
        }
        let interval = min(remaining, Configuration.Process.Interval)
        if let status = try status(timeout: Int32(interval)) {
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
    let capacity = Configuration.Process.Capacity
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
