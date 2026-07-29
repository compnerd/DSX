// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct PlatformSession: ~Copyable, Sendable {
  internal var launch: Debuggee.Launch
  internal var files: FileSystem = FileSystem()
  internal private(set) var servers: PlatformProcesses
  private let executable: String?
  private let logging: String?
  private let port: UInt16?

  internal init(port: UInt16? = nil, executable: consuming String? = nil,
                logging: consuming String? = nil,
                launch: consuming Debuggee.Launch = Debuggee.Launch(),
                working: consuming String? = nil,
                tracking servers: consuming PlatformProcesses) {
    var launch = consume launch
    if launch.working == nil {
      launch.working = consume working ?? Host.working
    }
    self.launch = launch
    self.executable = consume executable
    self.logging = consume logging
    self.port = port
    self.servers = consume servers
  }

  internal mutating func launch(host _: String? = nil, port: UInt16? = nil)
      throws(Debuggee.Error) -> HostProcess.Information {
    guard let executable else {
      throw .unsupported
    }
    let port = port ?? self.port ?? 0
    let address = ":\(port)"
    var arguments = ["gdbserver", "--pipe", "1"]
    if let logging {
      arguments.append(contentsOf: ["--log-channels", logging])
    }
    arguments.append(address)
    DSX.log("launching child debug server", level: .trace, channel: .process)
    return try servers.record(Host.launch(executable,
                                          arguments: arguments.span))
  }

  internal mutating func launch(_ configuration: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> HostProcess.Information {
    guard case .some = configuration.executable else {
      throw .process
    }
    return try servers.record(Host.spawn(configuration))
  }

  internal mutating func remove(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    try servers.remove(process)
  }

  internal mutating func close() throws(Debuggee.Error) {
    reap()
    try files.clear()
  }

  internal mutating func reap() {
    servers.reap()
  }

  internal mutating func release() -> PlatformProcesses {
    reap()
    return servers.take()
  }
}
