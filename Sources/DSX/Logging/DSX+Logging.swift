// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let kLogger = LogStream(level: .off)

extension DSX {
  @inline(__always)
  internal static func log(_ message: @autoclosure () -> String,
                           level: LogLevel, channel: LogChannel) {
    kLogger(level, channel: channel, message())
  }

  @inline(__always)
  internal static func log(_ bytes: borrowing Span<UInt8>,
                           level: LogLevel = .trace,
                           channel: LogChannel = .packet,
                           direction: LogDirection) {
    kLogger.bytes(bytes, level: level, channel: channel, direction: direction)
  }

  @inline(__always)
  internal static func enabled(_ level: LogLevel, channel: LogChannel) -> Bool {
    kLogger.enabled(level, channel: channel)
  }

  @inline(__always)
  internal static func level(_ level: LogLevel) {
    kLogger.level(level)
  }

  internal static func logging(_ channels: borrowing String? = nil,
                               to file: borrowing String? = nil)
      throws(LogConfigurationError) {
    let configuration = try LogConfiguration.parse(channels)
    switch file {
    case .some(let file):
      if file.isEmpty {
        kLogger.redirect(LogSystem.error, close: false, colour: .auto)
      } else {
        let descriptor: CInt
        do throws(LogError) {
          descriptor = try LogSystem.open(file, append: false)
        } catch {
          switch error {
          case .open(let code):
            throw .destination(code)
          }
        }
        kLogger.redirect(descriptor, close: true, colour: .never)
      }
    case .none:
      kLogger.redirect(LogSystem.error, close: false, colour: .auto)
    }
    kLogger.select(configuration.channels)
    kLogger.level(configuration.level)
  }
}
