// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal enum BSDSocketSystem {
  private typealias Failure = TransportError

  internal typealias Handle = CInt

  internal static func accept(_ handle: CInt) throws(TransportError) -> CInt {
    while true {
      let peer = DSX::accept(handle)
      if peer >= 0 {
        do {
          try cloexec(peer)
          return peer
        } catch {
          close(peer, path: nil)
          throw error
        }
      }
      guard errno == EINTR else {
        throw .accept(errno)
      }
    }
  }

  internal static func close(_ handle: CInt, path: String?) {
    _ = DSX::close(handle)
    if let path {
      path.withCString {
        _ = unlink($0)
      }
    }
  }

  internal static func open(_ endpoint: NetworkEndpoint, listening: Bool)
      throws(TransportError) -> (handle: CInt, port: UInt16) {
    var hints = addrinfo()
    if listening, case .none = endpoint.host {
      hints.ai_flags = AI_PASSIVE
    }
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = BSDSocketAPI.stream
    hints.ai_protocol = BSDSocketAPI.tcp

    var addresses: UnsafeMutablePointer<addrinfo>?
    let service = String(endpoint.port)
    let status = service.withCString { service in
      if let host = endpoint.host {
        return host.withCString { host in
          getaddrinfo(host, service, &hints, &addresses)
        }
      }
      return getaddrinfo(nil, service, &hints, &addresses)
    }
    guard status == 0 else {
      throw .address(CInt(status))
    }
    defer {
      if let addresses {
        freeaddrinfo(addresses)
      }
    }

    var failure = TransportError.create(0)
    var address = addresses
    while let info = address?.pointee {
      let handle = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
      guard handle >= 0 else {
        failure = .create(errno)
        address = info.ai_next
        continue
      }
      do {
        try cloexec(handle)
      } catch {
        failure = error
        close(handle, path: nil)
        address = info.ai_next
        continue
      }

      guard listening else {
        guard DSX::connect(handle, info.ai_addr,
                           socklen_t(info.ai_addrlen)) == 0 else {
          failure = .connect(errno)
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
      guard bind(handle, info.ai_addr, socklen_t(info.ai_addrlen)) == 0 else {
        failure = .bind(errno)
        close(handle, path: nil)
        address = info.ai_next
        continue
      }
      guard DSX::listen(handle, SOMAXCONN) == 0 else {
        failure = .listen(errno)
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
      throws(TransportError) -> CInt {
    let handle = socket(AF_UNIX, BSDSocketAPI.stream, 0)
    guard handle >= 0 else {
      throw .create(errno)
    }
    do {
      try cloexec(handle)
    } catch {
      close(handle, path: nil)
      throw error
    }

    var address = sockaddr_un()
    do {
      try assign(endpoint.path, to: &address)
    } catch {
      close(handle, path: nil)
      throw error
    }
    let status = withUnsafePointer(to: &address) { address in
      address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        if listening {
          return bind(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
        return DSX::connect(handle, $0,
                            socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard status == 0 else {
      let code = errno
      close(handle, path: nil)
      if listening {
        throw .bind(code)
      }
      throw .connect(code)
    }

    guard listening else {
      return handle
    }
    guard DSX::listen(handle, SOMAXCONN) == 0 else {
      let code = errno
      close(handle, path: endpoint.path)
      throw .listen(code)
    }
    return handle
  }

  internal static func output(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) {
    try bytes.withUnsafeBytes { bytes throws(TransportError) in
      var offset = 0
      while offset < bytes.count {
        let base = bytes.baseAddress!.advanced(by: offset)
        let count = DSX::write(STDERR_FILENO, base, bytes.count - offset)
        if count > 0 {
          offset += Int(count)
          continue
        }
        guard errno == EINTR else {
          throw .output(errno)
        }
      }
    }
  }

  internal static func wait(_ handle: CInt, timeout: Int32,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try WaitSystem.wait(handle, timeout: timeout, events: events)
  }

  internal static func receive(_ handle: CInt,
                               _ buffer: UnsafeMutableRawPointer,
                               _ count: Int) throws(TransportError) -> Int {
    while true {
      let result = recv(handle, buffer, count, 0)
      if result >= 0 {
        return result
      }
      guard errno == EINTR else {
        throw .read(errno)
      }
    }
  }

  internal static func transmit(_ handle: CInt, _ buffer: UnsafeRawPointer,
                                _ count: Int) throws(TransportError) -> Int {
    while true {
      let result = send(handle, buffer, count, BSDSocketAPI.flags)
      if result >= 0 {
        return result
      }
      guard errno == EINTR else {
        throw .write(errno)
      }
    }
  }

  private static func configure(_ handle: CInt, family: CInt)
      throws(TransportError) {
    var enabled: CInt = 1
    let reuse = withUnsafePointer(to: &enabled) { enabled in
      setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, enabled,
                 socklen_t(MemoryLayout<CInt>.size))
    }
    guard reuse == 0 else {
      throw .option(errno)
    }

    if family == AF_INET6 {
      var disabled: CInt = 0
      let dual = withUnsafePointer(to: &disabled) { disabled in
        setsockopt(handle, BSDSocketAPI.ipv6, IPV6_V6ONLY, disabled,
                   socklen_t(MemoryLayout<CInt>.size))
      }
      guard dual == 0 else {
        throw .option(errno)
      }
    }
  }

  private static func cloexec(_ handle: CInt) throws(TransportError) {
    let flags = fcntl(handle, F_GETFD)
    guard flags >= 0 else {
      throw .option(errno)
    }
    guard fcntl(handle, F_SETFD, flags | FD_CLOEXEC) == 0 else {
      throw .option(errno)
    }
  }

  private static func assign(_ path: String, to address: inout sockaddr_un)
      throws(TransportError) {
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let count = path.utf8.count
    guard count < capacity else {
      throw .path
    }
    BSDSocketAPI.prepare(&address)
    path.withCString { source in
      withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: UnsafeRawBufferPointer(start: source,
                                                           count: count + 1))
      }
    }
  }

  private static func port(_ handle: CInt) throws(TransportError) -> UInt16 {
    var address = sockaddr_storage()
    var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
    let status = withUnsafeMutablePointer(to: &address) { address in
      address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(handle, $0, &length)
      }
    }
    guard status == 0 else {
      throw .name(errno)
    }

    return switch CInt(address.ss_family) {
    case AF_INET:
      withUnsafePointer(to: address) { address in
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          UInt16(bigEndian: $0.pointee.sin_port)
        }
      }
    case AF_INET6:
      withUnsafePointer(to: address) { address in
        address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
          UInt16(bigEndian: $0.pointee.sin6_port)
        }
      }
    default:
      throw .name(EAFNOSUPPORT)
    }
  }
}
#endif
