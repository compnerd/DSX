// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT
internal import WinSDK

internal enum WindowsStreamHandle {
  case descriptor(CInt)
  case native(HANDLE)
  case standard(HANDLE)
}

internal enum WindowsStream {
  internal typealias Handle = WindowsStreamHandle

  internal static func output(_ buffer: UnsafeRawPointer,
                              count: Int) throws(TransportError) -> Int {
    let result = _write(STDERR_FILENO, buffer, UInt32(clamping: count))
    guard result > 0 else {
      throw .output(result == 0 ? EIO : errno)
    }
    return Int(result)
  }

  internal static func close(_ handle: WindowsStreamHandle) {
    if case let .native(handle) = handle {
      _ = CloseHandle(handle)
    }
  }

  internal static func open(_ endpoint: StreamEndpoint) throws(TransportError)
      -> WindowsStreamHandle {
    try WindowsStreamHandle(endpoint)
  }

  internal static func wait(_ handle: WindowsStreamHandle, timeout: Duration?,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    let native = try handle.value
    let polling = Tuning.Process.polling
    let timeout = events.isEmpty ? timeout : min(timeout ?? polling, polling)
    let deadline = timeout.map {
      Deadline($0, now: .milliseconds(GetTickCount64()))
    }
    if GetFileType(native) == FILE_TYPE_PIPE {
      while true {
        var available: DWORD = 0
        guard PeekNamedPipe(native, nil, 0, nil, &available, nil) else {
          let code = GetLastError()
          if code == ERROR_BROKEN_PIPE {
            return .channel
          }
          throw .read(CInt(bitPattern: code))
        }
        if available > 0 {
          return .channel
        }
        let remaining =
            deadline?.remaining(at: .milliseconds(GetTickCount64())) ?? polling
        if remaining == .zero {
          return .timeout
        }
        Sleep(DWORD(min(remaining, polling).rounded(to: .milliseconds(1),
                                                    rule: .up)))
      }
    }
    var remaining = timeout
    while true {
      let milliseconds = remaining.map {
        DWORD(min($0.rounded(to: .milliseconds(1),
                             rule: .up), UInt64(INFINITE - 1)))
      } ?? INFINITE
      let status = WaitForSingleObject(native, milliseconds)
      switch status {
      case WAIT_OBJECT_0: return .channel
      case WAIT_TIMEOUT:
        if let deadline {
          let rest = deadline.remaining(at: .milliseconds(GetTickCount64()))
          if rest > .zero {
            remaining = rest
            continue
          }
        }
        return .timeout
      default: throw .read(CInt(GetLastError()))
      }
    }
  }

  internal static func receive(_ handle: WindowsStreamHandle,
                               into buffer: UnsafeMutableRawPointer,
                               capacity: Int) throws(TransportError) -> Int {
    switch handle {
    case let .descriptor(descriptor):
      let result = _read(descriptor, buffer, UInt32(clamping: capacity))
      guard result >= 0 else {
        throw .read(errno)
      }
      return Int(result)
    case let .native(handle), let .standard(handle):
      var result: DWORD = 0
      let status =
          ReadFile(handle, buffer, DWORD(clamping: capacity), &result, nil)
      guard status else {
        let code = GetLastError()
        if code == ERROR_BROKEN_PIPE {
          return 0
        }
        throw .read(CInt(bitPattern: code))
      }
      return Int(result)
    }
  }

  internal static func transmit(_ handle: WindowsStreamHandle,
                                from buffer: UnsafeRawPointer,
                                count: Int) throws(TransportError) -> Int {
    switch handle {
    case let .descriptor(descriptor):
      let result = _write(descriptor, buffer, UInt32(clamping: count))
      guard result >= 0 else {
        throw .write(errno)
      }
      return Int(result)
    case let .native(handle), let .standard(handle):
      var result: DWORD = 0
      let status =
          WriteFile(handle, buffer, DWORD(clamping: count), &result, nil)
      guard status else {
        throw .write(CInt(GetLastError()))
      }
      return Int(result)
    }
  }
}

extension WindowsStreamHandle {
  internal init(_ endpoint: StreamEndpoint) throws(TransportError) {
    self = switch endpoint {
    case let .descriptor(handle): try WindowsStreamHandle(descriptor: handle)
    case let .device(path): try WindowsStreamHandle(path: path)
    case let .notification(path):
      try WindowsStreamHandle(path: WindowsStreamHandle.pipe(path),
                              access: GENERIC_WRITE)
    case let .pipe(path):
      try WindowsStreamHandle(path: WindowsStreamHandle.pipe(path))
    }
  }

  private init(path: String, access: DWORD = GENERIC_READ | GENERIC_WRITE)
      throws(TransportError) {
    let handle = withUTF16CString(path) {
      CreateFileW($0, access, FILE_SHARE_READ | FILE_SHARE_WRITE, nil,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let handle else {
      throw .open(CInt(GetLastError()))
    }
    if handle == INVALID_HANDLE_VALUE {
      throw .open(CInt(GetLastError()))
    }
    self = .native(handle)
  }

  private init(descriptor: CInt) throws(TransportError) {
    if let standard = WindowsStreamHandle.standard(descriptor) {
      self = .standard(standard)
      return
    }
    _ = try WindowsStreamHandle.handle(for: descriptor)
    self = .descriptor(descriptor)
  }

  internal var value: HANDLE? {
    get throws(TransportError) {
      switch self {
      case let .descriptor(descriptor):
        try WindowsStreamHandle.handle(for: descriptor)
      case let .native(handle), let .standard(handle):
        handle
      }
    }
  }

  private static func standard(_ descriptor: CInt) -> HANDLE? {
    let identifier: DWORD? = switch descriptor {
    case STDIN_FILENO: STD_INPUT_HANDLE
    case STDOUT_FILENO: STD_OUTPUT_HANDLE
    case STDERR_FILENO: STD_ERROR_HANDLE
    default: nil
    }
    guard let identifier else {
      return nil
    }
    let handle = GetStdHandle(identifier)
    guard let handle else {
      return nil
    }
    if handle == INVALID_HANDLE_VALUE {
      return nil
    }
    return handle
  }

  private static func handle(for descriptor: CInt) throws(TransportError)
      -> HANDLE? {
    let previous =
        _set_thread_local_invalid_parameter_handler { _, _, _, _, _ in }
    defer {
      _ = _set_thread_local_invalid_parameter_handler(previous)
    }
    let value = _get_osfhandle(descriptor)
    if value == -1 {
      throw .descriptor(errno)
    }
    return HANDLE(bitPattern: value)
  }

  private static func pipe(_ path: String) -> String {
    let prefix = #"\\.\pipe\"#
    return path.hasPrefix(prefix) ? path : prefix + path
  }
}
#endif
