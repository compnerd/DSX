// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(FreeBSD) || os(Linux) || os(OpenBSD)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal enum UnixDebugSpawn {
  private typealias Failure = Debuggee.Error
  private typealias Vector = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>

  internal static func run(_ executable: String,
                           arguments args: borrowing Span<String>,
                           environment: borrowing Span<Debuggee.Environment>,
                           config: borrowing Debuggee.Launch,
                           descriptors: borrowing UnixDescriptors)
      throws(Debuggee.Error) -> pid_t {
    var reporter = try UnixSpawn.pipe()
    defer {
      for index in 0 ..< reporter.count where reporter[index] >= 0 {
        _ = DSX::close(reporter[index])
      }
    }
    let application = try copy(executable)
    defer { free(application) }
    let working = try copy(config.working)
    defer { free(working) }
    let input = try copy(config.input)
    defer { free(input) }
    let output = try copy(config.output)
    defer { free(output) }
    let error = try copy(config.error)
    defer { free(error) }
    let aslr = config.aslr
    let descriptors = copy descriptors
    return try UnixSpawn
      .run(args, env: environment,
           prefix: executable) { argv, envp throws(Failure) in
#if os(Android)
      let process = Android.fork()
#else
      let process = Glibc.fork()
#endif
      if process == 0 {
        child(application, arguments: argv, environment: envp,
              directory: working, input: input, output: output, error: error,
              aslr: aslr, descriptors: descriptors, reporter: reporter)
      }
      guard process >= 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      _ = DSX::close(reporter[1])
      reporter[1] = -1
      try report(process, from: reporter[0])
      return process
    }
  }

  private static func child(_ executable: UnsafeMutablePointer<CChar>,
                            arguments: Vector, environment: Vector,
                            directory working: UnsafeMutablePointer<CChar>?,
                            input: UnsafeMutablePointer<CChar>?,
                            output: UnsafeMutablePointer<CChar>?,
                            error: UnsafeMutablePointer<CChar>?, aslr: Bool,
                            descriptors: borrowing UnixDescriptors,
                            reporter: borrowing UnixDescriptors) -> Never {
    _ = DSX::close(reporter[0])
    guard setpgid(0, 0) == 0 else {
      fail(errno, reporter: reporter[1])
    }
    guard trace() == 0 else {
      fail(errno, reporter: reporter[1])
    }
    if let working {
      guard chdir(working) == 0 else {
        fail(errno, reporter: reporter[1])
      }
    }
    redirect(input, descriptor: STDIN_FILENO, fallback: descriptors[1],
             flags: O_RDONLY, reporter: reporter[1])
    redirect(output, descriptor: STDOUT_FILENO, fallback: descriptors[1],
             flags: O_WRONLY | O_CREAT | O_TRUNC, reporter: reporter[1])
    redirect(error, descriptor: STDERR_FILENO, fallback: descriptors[1],
             flags: O_WRONLY | O_CREAT | O_TRUNC, reporter: reporter[1])
    for index in 0 ..< descriptors.count where descriptors[index] >= 0 {
      _ = DSX::close(descriptors[index])
    }
#if os(Android) || os(Linux)
    switch aslr {
    case true:
      break
    case false:
      let persona = personality(kPersonalityQuery)
      guard persona >= 0 else {
        fail(errno, reporter: reporter[1])
      }
      let value =
          CUnsignedLong(UInt32(bitPattern: persona)) | kAddressNoRandomize
      guard personality(value) >= 0 else {
        fail(errno, reporter: reporter[1])
      }
    }
#else
    _ = aslr
#endif
    _ = execve(executable, arguments, environment)
    fail(errno, reporter: reporter[1])
  }

  private static func trace() -> CInt {
#if os(Android) || os(Linux)
    CInt(ptrace(PTRACE_TRACEME, 0, nil, nil))
#else
    ptrace(PT_TRACE_ME, 0, nil, 0)
#endif
  }

  private static func redirect(_ path: UnsafeMutablePointer<CChar>?,
                               descriptor: CInt, fallback: CInt, flags: CInt,
                               reporter: CInt) {
    let source =
        source(path, fallback: fallback, flags: flags, reporter: reporter)
    guard source >= 0 else {
      return
    }
    if source == descriptor {
      return
    }
    guard dup2(source, descriptor) >= 0 else {
      fail(errno, reporter: reporter)
    }
    if case .some = path {
      _ = DSX::close(source)
    }
  }

  private static func source(_ path: UnsafeMutablePointer<CChar>?,
                             fallback: CInt, flags: CInt,
                             reporter: CInt) -> CInt {
    guard let path else {
      return fallback
    }
    let source = dsx_open(path, flags, mode_t(0o666))
    guard source >= 0 else {
      fail(errno, reporter: reporter)
    }
    return source
  }

  private static func copy(_ value: String) throws(Debuggee.Error)
      -> UnsafeMutablePointer<CChar> {
    guard let pointer = strdup(value) else {
      throw .system(ENOMEM)
    }
    return pointer
  }

  private static func copy(_ value: String?) throws(Debuggee.Error)
      -> UnsafeMutablePointer<CChar>? {
    guard let value else {
      return nil
    }
    return try copy(value)
  }

  private static func report(_ process: pid_t, from reporter: CInt)
      throws(Debuggee.Error) {
    var code: CInt = 0
    var count: Int
    repeat {
      count = withUnsafeMutableBytes(of: &code) { bytes in
        DSX::read(reporter, bytes.baseAddress, bytes.count)
      }
    } while count == -1 && errno == EINTR
    if count == 0 {
      return
    }
    let failure = errno
    _ = DSX::kill(process, SIGKILL)
    while waitpid(process, nil, 0) == -1 && errno == EINTR {
    }
    if count == -1 {
      throw UnixDebugProcess.failure(failure)
    }
    guard count == MemoryLayout<CInt>.size else {
      throw .state
    }
    throw .launch(code)
  }

  private static func fail(_ code: CInt, reporter: CInt) -> Never {
    var code = code
    withUnsafeBytes(of: &code) { bytes in
      _ = DSX::write(reporter, bytes.baseAddress, bytes.count)
    }
#if os(Android)
    Android._exit(code)
#else
    Glibc._exit(code)
#endif
  }
}
#endif
