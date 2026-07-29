// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Error {
  internal func log(_ message: StaticString, level: LogLevel = .error,
                    channel: LogChannel = .process) {
    DSX.log("\(message): \(self)", level: level, channel: channel)
  }
}
