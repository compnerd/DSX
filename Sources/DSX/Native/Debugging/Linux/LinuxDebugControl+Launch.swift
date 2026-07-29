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
    var descriptors: UnixDescriptors = [-1, -1]
    if capture {
      try UnixPseudoTerminal.open(&descriptors, terminal: config.terminal)
    }
    defer {
      for index in 0 ..< descriptors.count where descriptors[index] >= 0 {
        _ = DSX::close(descriptors[index])
      }
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
      _ = DSX::close(descriptors[1])
      descriptors[1] = -1
      reader = descriptors[0]
      descriptors[0] = -1
      let message = "capturing debuggee input and output with a pseudo-terminal"
      DSX.log(message, level: .trace, channel: .process)
    }
    return identifier
  }
}
#endif
