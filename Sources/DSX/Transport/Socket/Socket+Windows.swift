// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT
internal import WinSDK

internal enum WinSockSystem {
  private typealias Failure = TransportError

  internal typealias Handle = SOCKET

  internal static func accept(_ handle: SOCKET) throws(TransportError)
      -> SOCKET {
    let peer = WinSDK.accept(handle, nil, nil)
    if peer == INVALID_SOCKET {
      throw .accept(code())
    }
    return peer
  }

  internal static func close(_ handle: SOCKET, path: String?) {
    _ = closesocket(handle)
    if let path {
      _ = withUTF16CString(path) {
        DeleteFileW($0)
      }
    }
  }

  internal static func open(_ endpoint: NetworkEndpoint, listening: Bool)
      throws(TransportError) -> (handle: SOCKET, port: UInt16) {
    var hints = ADDRINFOW()
    if listening, case .none = endpoint.host {
      hints.ai_flags = AI_PASSIVE
    }
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP

    var addresses: PADDRINFOW?
    let service = String(endpoint.port)
    let status = withUTF16CString(service) { service in
      if let host = endpoint.host {
        return withUTF16CString(host) { host in
          GetAddrInfoW(host, service, &hints, &addresses)
        }
      }
      return GetAddrInfoW(nil, service, &hints, &addresses)
    }
    guard status == 0 else {
      throw .address(CInt(status))
    }
    defer {
      if let addresses {
        FreeAddrInfoW(addresses)
      }
    }

    var failure = TransportError.create(0)
    var address = addresses
    while let info = address?.pointee {
      let handle =
          WinSDK.socket(info.ai_family, info.ai_socktype, info.ai_protocol)
      if handle == INVALID_SOCKET {
        failure = .create(code())
        address = info.ai_next
        continue
      }

      guard listening else {
        guard WinSDK.connect(handle, info.ai_addr,
                             CInt(info.ai_addrlen)) == 0 else {
          failure = .connect(code())
          close(handle, path: nil)
          address = info.ai_next
          continue
        }
        return (handle: handle, port: endpoint.port)
      }

      do {
        try configure(handle, family: info.ai_family)
      } catch {
        failure = error
        close(handle, path: nil)
        address = info.ai_next
        continue
      }
      guard WinSDK.bind(handle, info.ai_addr, CInt(info.ai_addrlen)) == 0 else {
        failure = .bind(code())
        close(handle, path: nil)
        address = info.ai_next
        continue
      }
      guard WinSDK.listen(handle, SOMAXCONN) == 0 else {
        failure = .listen(code())
        close(handle, path: nil)
        address = info.ai_next
        continue
      }
      do {
        return try (handle: handle, port: port(handle))
      } catch {
        close(handle, path: nil)
        throw error
      }
    }
    throw failure
  }

  internal static func open(_ endpoint: UnixEndpoint, listening: Bool)
      throws(TransportError) -> SOCKET {
    let handle = WinSDK.socket(AF_UNIX, SOCK_STREAM, 0)
    if handle == INVALID_SOCKET {
      throw .create(code())
    }

    var status: CInt = SOCKET_ERROR
    do {
      try address(endpoint.path) { address, length in
        status = if listening {
          WinSDK.bind(handle, address, length)
        } else {
          WinSDK.connect(handle, address, length)
        }
      }
    } catch {
      close(handle, path: nil)
      throw error
    }
    guard status == 0 else {
      let failure = code()
      close(handle, path: nil)
      if listening {
        throw .bind(failure)
      }
      throw .connect(failure)
    }

    guard listening else {
      return handle
    }
    guard WinSDK.listen(handle, SOMAXCONN) == 0 else {
      let failure = code()
      close(handle, path: endpoint.path)
      throw .listen(failure)
    }
    return handle
  }

  internal static func output(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) {
    try bytes.withUnsafeBytes { bytes throws(TransportError) in
      var offset = 0
      while offset < bytes.count {
        let count =
            _write(STDERR_FILENO, bytes.baseAddress!.advanced(by: offset),
                   UInt32(bytes.count - offset))
        guard count > 0 else {
          throw .output(errno)
        }
        offset += Int(count)
      }
    }
  }

  internal static func wait(_ handle: SOCKET, timeout: Int32,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    let interval = Int32(Configuration.Process.Interval)
    let timeout = if events.isEmpty {
      timeout
    } else {
      timeout < 0 ? interval : min(timeout, interval)
    }
    var descriptor =
        WSAPOLLFD(fd: handle, events: SHORT(POLLRDNORM), revents: 0)
    let status = WSAPoll(&descriptor, 1, timeout)
    guard status >= 0 else {
      throw .read(code())
    }
    return status > 0 ? .channel : .timeout
  }

  internal static func receive(_ handle: SOCKET,
                               _ buffer: UnsafeMutableRawPointer,
                               _ count: Int) throws(TransportError) -> Int {
    let result = WinSDK.recv(handle, buffer, CInt(min(count, Int(CInt.max))), 0)
    guard result >= 0 else {
      throw .read(code())
    }
    return Int(result)
  }

  internal static func transmit(_ handle: SOCKET, _ buffer: UnsafeRawPointer,
                                _ count: Int) throws(TransportError) -> Int {
    let result = WinSDK.send(handle, buffer, CInt(min(count, Int(CInt.max))), 0)
    guard result >= 0 else {
      throw .write(code())
    }
    return Int(result)
  }

  private static func configure(_ handle: SOCKET, family: CInt)
      throws(TransportError) {
    var enabled: CInt = 1
    let reuse = withUnsafePointer(to: &enabled) { enabled in
      enabled.withMemoryRebound(to: CChar.self, capacity: 1) {
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, $0,
                   CInt(MemoryLayout<CInt>.size))
      }
    }
    guard reuse == 0 else {
      throw .option(code())
    }

    if family == AF_INET6 {
      var disabled: CInt = 0
      let dual = withUnsafePointer(to: &disabled) { disabled in
        disabled.withMemoryRebound(to: CChar.self, capacity: 1) {
          setsockopt(handle, IPPROTO_IPV6, IPV6_V6ONLY, $0,
                     CInt(MemoryLayout<CInt>.size))
        }
      }
      guard dual == 0 else {
        throw .option(code())
      }
    }
  }

  private static func address(_ path: String,
                              _ body: (UnsafePointer<SOCKADDR>, CInt) -> Void)
      throws(TransportError) {
    let count = path.utf8.count
    guard count < 108 else {
      throw .path
    }
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 110) { buffer in
      buffer.initialize(repeating: 0)
      let family = UInt16(AF_UNIX)
      buffer[0] = UInt8(truncatingIfNeeded: family)
      buffer[1] = UInt8(truncatingIfNeeded: family >> 8)
      path.withCString { path in
        UnsafeMutableRawPointer(buffer.baseAddress!.advanced(by: 2))
          .copyMemory(from: path, byteCount: count + 1)
      }
      buffer.baseAddress!.withMemoryRebound(to: SOCKADDR.self, capacity: 1) {
        body($0, CInt(buffer.count))
      }
    }
  }

  private static func port(_ handle: SOCKET) throws(TransportError) -> UInt16 {
    var address = SOCKADDR_STORAGE()
    var length = CInt(MemoryLayout<SOCKADDR_STORAGE>.size)
    let status = withUnsafeMutablePointer(to: &address) { address in
      address.withMemoryRebound(to: SOCKADDR.self, capacity: 1) {
        getsockname(handle, $0, &length)
      }
    }
    guard status == 0 else {
      throw .name(code())
    }

    return switch CInt(address.ss_family) {
    case AF_INET:
      withUnsafePointer(to: address) { address in
        address.withMemoryRebound(to: SOCKADDR_IN.self, capacity: 1) {
          UInt16(bigEndian: $0.pointee.sin_port)
        }
      }
    case AF_INET6:
      withUnsafePointer(to: address) { address in
        address.withMemoryRebound(to: SOCKADDR_IN6.self, capacity: 1) {
          UInt16(bigEndian: $0.pointee.sin6_port)
        }
      }
    default:
      throw .name(CInt(WSAEAFNOSUPPORT))
    }
  }

  private static func code() -> CInt {
    CInt(WSAGetLastError())
  }
}
#endif
