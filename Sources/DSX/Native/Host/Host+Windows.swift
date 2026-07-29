// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT
internal import DSXShims
internal import WinSDK

internal enum HostError: Error, Equatable, Sendable {
  case output(CInt)
  case winsock(CInt)
}

extension Host {
  internal static var interrupt: UInt8 {
    2
  }

  internal static var kernel: String? {
    "Windows NT"
  }

  internal static var daemonization: DaemonizationOrder {
    .before
  }

  internal static var system: StaticString {
    "windows"
  }

  internal static var version: String? {
    var info = OSVERSIONINFOW()
    guard dsx_RtlGetVersion(&info) == 0 else {
      return nil
    }
    return "\(info.dwMajorVersion).\(info.dwMinorVersion).\(info.dwBuildNumber)"
  }

  internal static var metadata: HostMetadata {
    HostMetadata()
  }

  internal static func equivalent(_ lhs: UInt8, _ rhs: UInt8) -> Bool {
    if separates(lhs), separates(rhs) {
      return true
    }
    return lowercase(lhs) == lowercase(rhs)
  }

  internal static func initialize() -> String? {
    do throws(HostError) {
      try startup()
      return nil
    } catch {
      return String(describing: error)
    }
  }

  internal static func isolate() throws(SessionIsolationError) {
    throw .unsupported
  }

  internal static func daemonize() throws(DaemonizationError) -> Bool {
    let key: StaticString = "DSX_DAEMONIZED"
    let name = InlineArray<15, WCHAR> { index in
      index < key.utf8CodeUnitCount ? WCHAR(key.utf8Start[index]) : 0
    }
    if marked(name.span) {
      _ = name.span.withUnsafeBufferPointer { name in
        SetEnvironmentVariableW(name.baseAddress, nil)
      }
      return true
    }

    let set = withUTF16CString("1") { value in
      name.span.withUnsafeBufferPointer { name in
        SetEnvironmentVariableW(name.baseAddress, value)
      }
    }
    guard set else {
      throw failure()
    }
    defer {
      _ = name.span.withUnsafeBufferPointer { name in
        SetEnvironmentVariableW(name.baseAddress, nil)
      }
    }

    guard let source = GetCommandLineW() else {
      throw failure()
    }
    let text = String(decodingCString: source, as: UTF16.self)
    var command = Array(text.utf16) + [0]
    var security = SECURITY_ATTRIBUTES()
    security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
    security.bInheritHandle = true
    let null = withUTF16CString("NUL") { path in
      CreateFileW(path, GENERIC_READ | GENERIC_WRITE,
                  FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING,
                  FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let null else {
      throw failure()
    }
    if null == INVALID_HANDLE_VALUE {
      throw failure()
    }
    defer {
      _ = CloseHandle(null)
    }
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startup.dwFlags = STARTF_USESTDHANDLES
    startup.hStdInput = null
    startup.hStdOutput = null
    startup.hStdError = null
    var information = PROCESS_INFORMATION()
    let flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
              | CREATE_UNICODE_ENVIRONMENT
    let created = command.withUnsafeMutableBufferPointer { command in
      CreateProcessW(nil, command.baseAddress, nil, nil, true, flags, nil, nil,
                     &startup, &information)
    }
    guard created else {
      throw failure()
    }
    _ = CloseHandle(information.hThread)
    _ = CloseHandle(information.hProcess)
    return false
  }
}

extension Debuggee.Process.Info {
  internal func matches(_ candidate: String) -> Bool {
    let name = name.utf8Span.span
    let candidate = candidate.utf8Span.span
    guard name.count == candidate.count else {
      return false
    }
    for index in name.indices {
      if Host.equivalent(name[index], candidate[index]) == false {
        return false
      }
    }
    return true
  }
}

private func marked(_ name: borrowing Span<WCHAR>) -> Bool {
  var storage = InlineArray<5, WCHAR> { _ in 0 }
  var value = storage.mutableSpan
  let count = name.withUnsafeBufferPointer { name in
    value.withUnsafeMutableBufferPointer { value in
      GetEnvironmentVariableW(name.baseAddress, value.baseAddress,
                              DWORD(value.count))
    }
  }
  guard count > 0, count < value.count else {
    return false
  }
  let text = value.withUnsafeBufferPointer { value in
    String(decoding: value.prefix(Int(count)), as: UTF16.self)
  }
  return Daemonization.enabled(text)
}

private func startup() throws(HostError) {
  guard setvbuf(stdout, nil, _IONBF, 0) == 0 else {
    throw .output(errno)
  }
  var data = WSADATA()
  let status = WSAStartup(WORD(0x0202), &data)
  guard status == 0 else {
    throw .winsock(status)
  }
}

private func failure() -> DaemonizationError {
  .system(CInt(bitPattern: GetLastError()))
}

private func lowercase(_ byte: UInt8) -> UInt8 {
  byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
      ? byte + UInt8(ascii: "a") - UInt8(ascii: "A") : byte
}

private func separates(_ byte: UInt8) -> Bool {
  byte == UInt8(ascii: "/") || byte == UInt8(ascii: "\\")
}
#endif
