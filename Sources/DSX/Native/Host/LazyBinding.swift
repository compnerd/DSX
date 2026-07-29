// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal struct LazyBinding<Function: Sendable>: Sendable {
  internal let function: Function
#if os(Windows)
  internal let module: UInt

  internal init?(module: HMODULE, _ name: StaticString) {
    let name =
        UnsafeRawPointer(name.utf8Start).assumingMemoryBound(to: CChar.self)
    guard let symbol = GetProcAddress(module, name) else {
      return nil
    }
    function = unsafeBitCast(symbol, to: Function.self)
    self.module = UInt(bitPattern: module)
  }
#else
  internal init?(module: UnsafeMutableRawPointer?, _ name: StaticString) {
    let name =
        UnsafeRawPointer(name.utf8Start).assumingMemoryBound(to: CChar.self)
    guard let symbol = dlsym(module, name) else {
      return nil
    }
    function = unsafeBitCast(symbol, to: Function.self)
  }
#endif

  internal var address: UInt {
    unsafeBitCast(function, to: UInt.self)
  }
}
