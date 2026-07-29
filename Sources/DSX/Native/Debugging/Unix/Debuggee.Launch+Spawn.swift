// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(FreeBSD) || os(Linux) || os(OpenBSD)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

private typealias Vector = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>

#if os(Android) || os(Linux)
/// Query the current execution domain without changing it.
private let kPersonalityQuery: CUnsignedLong = 0xffff_ffff
#endif

extension Debuggee.Launch {
  private typealias Failure = Debuggee.Error

  internal func spawn(descriptors: borrowing UnixDescriptors)
      throws(Debuggee.Error) -> pid_t {
    try validate()
    guard let executable else {
      throw .process
    }
    var reporter = try UnixDescriptors()
    let application = try copy(required: executable)
    defer { free(application) }
    let directory = try copy(directory)
    defer { free(directory) }
    let input = try copy(self.input)
    defer { free(input) }
    let output = try copy(self.output)
    defer { free(output) }
    let error = try copy(self.error)
    defer { free(error) }
    let aslr = self.aslr
    let descriptors = (reader: descriptors.reader, writer: descriptors.writer)
    let command = try UnixCommand(arguments.span, env: environment.span,
                                  prefix: executable)
    return try command.spawn { argv, envp throws(Failure) in
#if os(Android)
      let process = Android.fork()
#else
      let process = Glibc.fork()
#endif
      if process == 0 {
        child(application, arguments: argv, environment: envp,
              directory: directory, input: input, output: output, error: error,
              aslr: aslr, descriptors: descriptors,
              reporter: (reader: reporter.reader, writer: reporter.writer))
      }
      guard process >= 0 else {
        throw Debuggee.Error(unix: errno)
      }
      _ = DSX::close(reporter.writer)
      reporter.writer = -1
      try report(process, from: reporter.reader)
      return process
    }
  }
}

private func child(_ executable: UnsafeMutablePointer<CChar>, arguments: Vector,
                   environment: Vector, directory: UnsafeMutablePointer<CChar>?,
                   input: UnsafeMutablePointer<CChar>?,
                   output: UnsafeMutablePointer<CChar>?,
                   error: UnsafeMutablePointer<CChar>?, aslr: Bool,
                   descriptors: (reader: CInt, writer: CInt),
                   reporter: (reader: CInt, writer: CInt)) -> Never {
  _ = DSX::close(reporter.reader)
  guard setpgid(0, 0) == 0 else {
    fail(errno, reporter: reporter.writer)
  }
  guard trace() == 0 else {
    fail(errno, reporter: reporter.writer)
  }
  if let directory {
    guard chdir(directory) == 0 else {
      fail(errno, reporter: reporter.writer)
    }
  }
  redirect(input, descriptor: STDIN_FILENO, fallback: descriptors.writer,
           flags: O_RDONLY, reporter: reporter.writer)
  redirect(output, descriptor: STDOUT_FILENO, fallback: descriptors.writer,
           flags: O_WRONLY | O_CREAT | O_TRUNC, reporter: reporter.writer)
  redirect(error, descriptor: STDERR_FILENO, fallback: descriptors.writer,
           flags: O_WRONLY | O_CREAT | O_TRUNC, reporter: reporter.writer)
  if descriptors.reader >= 0 {
    _ = DSX::close(descriptors.reader)
  }
  if descriptors.writer >= 0 {
    _ = DSX::close(descriptors.writer)
  }
#if os(Android) || os(Linux)
  switch aslr {
  case true:
    break
  case false:
    let persona = personality(kPersonalityQuery)
    guard persona >= 0 else {
      fail(errno, reporter: reporter.writer)
    }
    let value = CUnsignedLong(UInt32(bitPattern: persona)) | ADDR_NO_RANDOMIZE
    guard personality(value) >= 0 else {
      fail(errno, reporter: reporter.writer)
    }
  }
#else
  _ = aslr
#endif
  _ = execve(executable, arguments, environment)
  fail(errno, reporter: reporter.writer)
}

private func trace() -> CInt {
#if os(Android) || os(Linux)
  CInt(ptrace(PTRACE_TRACEME, 0, nil, nil))
#else
  ptrace(PT_TRACE_ME, 0, nil, 0)
#endif
}

private func redirect(_ path: UnsafeMutablePointer<CChar>?, descriptor: CInt,
                      fallback: CInt, flags: CInt, reporter: CInt) {
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

private func source(_ path: UnsafeMutablePointer<CChar>?, fallback: CInt,
                    flags: CInt, reporter: CInt) -> CInt {
  guard let path else {
    return fallback
  }
  let source = dsx_open(path, flags, mode_t(0o666))
  guard source >= 0 else {
    fail(errno, reporter: reporter)
  }
  return source
}

private func copy(required value: String) throws(Debuggee.Error)
    -> UnsafeMutablePointer<CChar> {
  guard let pointer = strdup(value) else {
    throw .system(ENOMEM)
  }
  return pointer
}

private func copy(_ value: String?) throws(Debuggee.Error)
    -> UnsafeMutablePointer<CChar>? {
  guard let value else {
    return nil
  }
  return try copy(required: value)
}

private func report(_ process: pid_t, from reporter: CInt)
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
    throw Debuggee.Error(unix: failure)
  }
  guard count == MemoryLayout<CInt>.size else {
    throw .state
  }
  throw .launch(code)
}

private func fail(_ code: CInt, reporter: CInt) -> Never {
  var code = code
  withUnsafeBytes(of: &code) { bytes in
    // This fixed-size pipe record is atomic; an interrupted write transfers
    // no bytes. Stay allocation-free between fork and exec.
    while DSX::write(reporter, bytes.baseAddress, bytes.count) == -1 &&
        errno == EINTR {
    }
  }
#if os(Android)
  Android._exit(code)
#else
  Glibc._exit(code)
#endif
}
#endif
