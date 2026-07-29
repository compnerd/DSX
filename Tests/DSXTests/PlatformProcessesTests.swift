// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct PlatformProcessesTests {
  @Test
  internal func timeout() {
    var processes = PlatformProcesses()
    let process = ProcessIdentifier(rawValue: 1)
    _ = processes.record(HostProcess(process: process, port: 0))
    let result = processes.wait { timeout, events in
      #expect(timeout == Int32(Configuration.Process.Interval))
      let empty = events.isEmpty
      #expect(empty)
      return WaitResult.timeout
    }
    #expect(result == .timeout)
  }
}
