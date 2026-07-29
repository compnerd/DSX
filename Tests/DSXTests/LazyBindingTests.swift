// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Windows)
internal import WinSDK

private typealias NtContinueBinding = LazyBinding<FARPROC>

private let NtContinue: NtContinueBinding? = {
  guard let module =
      withUTF16CString("ntdll.dll", { GetModuleHandleW($0) }) else {
    return nil
  }
  return NtContinueBinding(module: module, "NtContinue")
}()
#else
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

private typealias getpidBinding = LazyBinding<@convention(c) () -> pid_t>

private let getpid = getpidBinding(module: RTLD_DEFAULT, "getpid")
private let kMissing =
    getpidBinding(module: RTLD_DEFAULT, "_DSX_missing_lazy_binding_test")
#endif

@Suite
internal struct LazyBindingTests {
  @Test(arguments: 0 ..< 16)
  internal func resolution(_: Int) throws {
#if os(Windows)
    let NtContinue = try #require(NtContinue)
    let handle = withUTF16CString("ntdll.dll") { GetModuleHandleW($0) }
    let module = try #require(handle)
    let function = try #require(GetProcAddress(module, "NtContinue"))
    #expect(NtContinue.module == UInt(bitPattern: module))
    #expect(NtContinue.address == unsafeBitCast(function, to: UInt.self))
    #expect(NtContinueBinding(module: module, "_DSX_missing_lazy_binding_test")
            == nil)
#else
    let getpid = try #require(getpid)
    let function = getpid.function
#if os(anyAppleOS)
    let process = Darwin.getpid()
#elseif os(Android)
    let process = Android.getpid()
#else
    let process = Glibc.getpid()
#endif
    for _ in 0 ..< 128 {
      #expect(function() == process)
      #expect(kMissing == nil)
    }
    #expect(MemoryLayout<getpidBinding>.size == MemoryLayout<UInt>.size)
    #expect(MemoryLayout<getpidBinding?>.size == MemoryLayout<UInt>.size)
#endif
  }
}
