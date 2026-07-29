// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable internal import DSX

extension PlatformSession {
  internal init(port: UInt16? = nil, executable: consuming String? = nil,
                logging: consuming String? = nil,
                launch: consuming Debuggee.Launch = Debuggee.Launch(),
                directory: consuming String? = nil,
                servers: consuming Array<HostProcess.Information> = []) {
    var tracking = PlatformProcesses()
    for server in servers {
      let process = HostProcess(process: server.process, port: server.port)
      _ = tracking.record(consume process)
    }
    self.init(port: port, executable: consume executable,
              logging: consume logging, launch: consume launch,
              directory: consume directory, tracking: consume tracking)
  }
}
