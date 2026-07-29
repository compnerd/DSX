// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

extension LinuxDebugControl {
  internal mutating func launch(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    guard let executable = config.executable else {
      throw .process
    }
    let capture = config.input == nil || config.output == nil ||
        config.error == nil
    var descriptors = UnixDescriptors(reader: -1, writer: -1)
    if capture {
      descriptors = try UnixDescriptors(terminal: config.terminal)
    }
    let process =
        try UnixDebugSpawn.run(executable, arguments: config.arguments.span,
                               environment: config.environment.span,
                               config: config, descriptors: descriptors)
    let identifier = ProcessIdentifier(rawValue: UInt64(process))
    self.process = identifier
    attached = false
    configured = false
    owners[process] = identifier
    if capture {
      reader = descriptors.release()
      let message = "capturing debuggee input and output with a pseudo-terminal"
      DSX.log(message, level: .trace, channel: .process)
    }
    return identifier
  }
}
#endif
