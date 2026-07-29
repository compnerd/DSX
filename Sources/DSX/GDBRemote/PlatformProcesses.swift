// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias WaitBody<Failure: Error> =
    (Int32, borrowing Span<WaitHandle>) throws(Failure) -> WaitResult

internal struct PlatformProcesses: ~Copyable, Sendable {
  private var storage = Array<HostProcessRecord>()

  internal init() {
  }

  deinit {
    for child in storage {
      child.close()
    }
  }

  internal var isEmpty: Bool {
    storage.isEmpty
  }

  internal var last: HostProcess.Information? {
    storage.last?.information
  }

  internal mutating func record(_ child: consuming HostProcess)
      -> HostProcess.Information {
    let result = child.information
    storage.append(child.take())
    return result
  }

  internal mutating func remove(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    guard let index = storage.firstIndex(where: { child in
      child.information.process == process
    }) else {
      throw .process
    }
    try storage[index].terminate()
    discard(at: index)
  }

  internal mutating func reap() {
    var index = storage.count
    while index > 0 {
      index -= 1
      let server = storage[index].information
      do {
        guard try storage[index].reap() else {
          continue
        }
        DSX.log("reaped child \(server.process.rawValue)", level: .trace,
                channel: .process)
        discard(at: index)
      } catch {
        DSX.log("failed to reap child \(server.process.rawValue): \(error)",
                level: .warning, channel: .process)
      }
    }
  }

  internal borrowing func wait<Failure: Error>(_ body: WaitBody<Failure>)
      throws(Failure) -> WaitResult {
    try withUnsafeTemporaryAllocation(of: WaitHandle.self,
                                      capacity: storage.count,
                                      { buffer throws(Failure) in
      var events = OutputSpan(buffer: buffer, initializedCount: 0)
      var timeout: Int32 = -1
      for child in storage {
        if let handle = child.monitor {
          events.append(handle)
        } else {
          timeout = Int32(Configuration.Process.Interval)
        }
      }
      return try body(timeout, events.span)
    })
  }

  private mutating func discard(at index: Int) {
    storage[index].close()
    storage.remove(at: index)
  }

  internal mutating func take() -> PlatformProcesses {
    var processes = PlatformProcesses()
    swap(&processes, &self)
    return consume processes
  }
}
