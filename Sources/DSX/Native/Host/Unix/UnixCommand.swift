// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
@preconcurrency internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif
internal import DSXShims

internal typealias UnixCommandPointer =
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
internal typealias UnixCommandBody =
    (UnixCommandPointer, UnixCommandPointer) throws(Debuggee.Error) -> pid_t

private typealias UnixCommandAccess =
    (UnixCommandPointer) throws(Debuggee.Error) -> pid_t

internal struct UnixCommand: ~Copyable {
  private var argv: Array<UInt8>
  private var envp: Array<UInt8>
  private let inherited: Bool

  internal init(_ arguments: borrowing Span<String>,
                env: borrowing Span<Debuggee.Environment>,
                prefix: borrowing String? = nil) throws(Debuggee.Error) {
    var argv = Array<UInt8>()
    switch prefix {
    case .some(let prefix):
      try argv.argument(prefix)
    case .none:
      break
    }
    for index in 0 ..< arguments.count {
      try argv.argument(arguments[index])
    }
    var envp = Array<UInt8>()
    if env.isEmpty == false {
      let inherited = try UnixEnvironment.read()
      envp = try Array(env, inheriting: inherited)
      // The environment has a double-NUL terminator, not an empty final entry.
      if envp[0] == 0 {
        envp.removeAll()
      } else {
        envp.removeLast()
      }
    }
    self.argv = argv
    self.envp = envp
    inherited = env.isEmpty
  }

  internal consuming func spawn(_ body: UnixCommandBody) throws(Debuggee.Error)
      -> pid_t {
    try argv.pointers { arguments throws(Debuggee.Error) in
      if inherited, let environment = variables() {
        return try body(arguments, environment)
      }
      return try envp.pointers { environment throws(Debuggee.Error) in
        try body(arguments, environment)
      }
    }
  }
}

extension Array where Element == UInt8 {
  fileprivate mutating func argument(_ value: String) throws(Debuggee.Error) {
    for byte in value.utf8 {
      guard byte > 0 else {
        throw .process
      }
      append(byte)
    }
    append(0)
  }

  /// Pins a NUL-separated block and its pointer vector across spawn or fork.
  fileprivate mutating func pointers(_ body: UnixCommandAccess)
      throws(Debuggee.Error) -> pid_t {
    let capacity = reduce(1) { $0 + ($1 == 0 ? 1 : 0) }
    return try withUnsafeMutableBufferPointer { bytes throws(Debuggee.Error) in
      try bytes.withMemoryRebound(to: CChar.self,
                                  { bytes throws(Debuggee.Error) in
        try withUnsafeTemporaryAllocation(of: UnsafeMutablePointer<CChar>?.self,
                                          capacity: capacity,
                                          { pointers throws(Debuggee.Error) in
          var start = 0
          var count = 0
          for index in bytes.indices where bytes[index] == 0 {
            pointers.initializeElement(at: count,
                                       to: bytes.baseAddress! + start)
            count += 1
            start = index + 1
          }
          pointers.initializeElement(at: count, to: nil)
          return try body(pointers.baseAddress!)
        })
      })
    }
  }
}

#endif
