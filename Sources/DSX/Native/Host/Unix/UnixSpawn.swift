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

internal typealias UnixDescriptors = InlineArray<2, CInt>
internal typealias UnixSpawnStorage = Array<UnsafeMutablePointer<CChar>?>
internal typealias UnixSpawnPointer =
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
internal typealias UnixSpawnBody =
    (UnixSpawnPointer, UnixSpawnPointer) throws(Debuggee.Error) -> pid_t

internal enum UnixSpawn {
  internal static func pipe() throws(Debuggee.Error) -> UnixDescriptors {
    var descriptors: UnixDescriptors = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
#if os(anyAppleOS)
        Darwin.pipe(values)
#else
        DSX::pipe2(values, O_CLOEXEC)
#endif
      }
    }
    guard status == 0 else {
      throw UnixError.debuggee(errno, invalid: .process, support: true)
    }
    do {
      try isolate(&descriptors[0])
      try isolate(&descriptors[1])
      return descriptors
    } catch {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
      throw error
    }
  }

  internal static func isolate(_ descriptor: inout CInt,
                               minimum: CInt = STDERR_FILENO + 1)
      throws(Debuggee.Error) {
    if descriptor < minimum {
      let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, minimum)
      if replacement == -1 {
        throw UnixError.debuggee(errno, invalid: .process)
      }
      _ = DSX::close(descriptor)
      descriptor = replacement
    } else {
      if fcntl(descriptor, F_SETFD, FD_CLOEXEC) == -1 {
        throw UnixError.debuggee(errno, invalid: .process)
      }
    }
  }

  internal static func run(_ arguments: borrowing Span<String>,
                           env: borrowing Span<Debuggee.Environment>,
                           prefix: borrowing String? = nil,
                           _ body: UnixSpawnBody) throws(Debuggee.Error)
      -> pid_t {
    var argv = UnixSpawnStorage()
    var envp = UnixSpawnStorage()
    argv.reserveCapacity(arguments.count + (prefix == nil ? 1 : 2))
    envp.reserveCapacity(env.count + 1)
    defer {
      release(argv)
      release(envp)
    }
    switch prefix {
    case .some(let prefix):
      try append(prefix, to: &argv)
    case .none:
      break
    }
    for index in 0 ..< arguments.count {
      try append(arguments[index], to: &argv)
    }
    if env.isEmpty == false {
      let inherited = try UnixEnvironment.read()
      let block = try ProcessEnvironment.resolve(env, inheriting: inherited)
      var start = 0
      while start < block.count, block[start] != 0 {
        var end = start
        while end < block.count, block[end] != 0 {
          end += 1
        }
        try append(block.span.extracting(start ..< end), to: &envp)
        start = end + 1
      }
    }
    argv.append(nil)
    envp.append(nil)
    let inherited = env.isEmpty
    let result =
        try argv.withUnsafeMutableBufferPointer { argv throws(Debuggee.Error) in
      try envp.withUnsafeMutableBufferPointer { envp throws(Debuggee.Error) in
        guard let arguments = argv.baseAddress else {
          throw .system(ENOMEM)
        }
        let environment = inherited ? variables() : envp.baseAddress
        guard let environment else {
          throw .system(ENOMEM)
        }
        return try body(arguments, environment)
      }
    }
    return result
  }

  @inline(never)
  private static func append(_ value: String,
                             to storage: inout UnixSpawnStorage)
      throws(Debuggee.Error) {
    guard let value = strdup(value) else {
      throw .system(ENOMEM)
    }
    storage.append(value)
  }

  @inline(never)
  private static func append(_ value: borrowing Span<UInt8>,
                             to storage: inout UnixSpawnStorage)
      throws(Debuggee.Error) {
    let capacity = value.count + 1
    guard let allocation = malloc(capacity) else {
      throw .system(ENOMEM)
    }
    let output = allocation.assumingMemoryBound(to: CChar.self)
    for index in 0 ..< value.count {
      output[index] = CChar(bitPattern: value[index])
    }
    output[value.count] = 0
    storage.append(output)
  }
}

@inline(never)
private func release(_ storage: borrowing UnixSpawnStorage) {
  for index in 0 ..< storage.count {
    free(storage[index])
  }
}

#endif
