// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeProcess {
  internal borrowing func notification() throws(Debuggee.Error) -> UInt16 {
    var port = ChildPort()
    while true {
      if let port = try port.consume(byte()) {
        return port
      }
    }
  }

  internal borrowing func wait(_ timeout: UInt64,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let result: Debuggee.ProgramStatus
    do {
      try prepare()
      let deadline = try Deadline(seconds: timeout, now: Host.time)
      while true {
        try drain(Configuration.Process.Capacity * Configuration.Process.Burst,
                  into: &output)
        if let status = try status(0) {
          result = .completed(status)
          break
        }
        let remaining = try deadline.remaining(Host.time)
        if remaining == 0 {
          try terminate()
          result = .timeout
          break
        }
        let interval = min(remaining, Configuration.Process.Interval)
        if let status = try status(Int32(interval)) {
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
