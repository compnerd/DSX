// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// Native implementation selection.
#if os(anyAppleOS) && (arch(arm64) || arch(x86_64))
#elseif os(Windows) && (arch(arm64) || arch(i386) || arch(x86_64))
#elseif os(Android) && (arch(arm) || arch(arm64) || arch(i386) || arch(x86_64))
#elseif os(Linux) && (arch(arm) || arch(arm64) || arch(i386) || arch(x86_64))
// Experimental hosts.
#elseif os(FreeBSD) && arch(x86_64)
#elseif os(OpenBSD) && arch(x86_64)
#else
#error("unsupported host platform and architecture")
#endif

#if os(Windows)
internal typealias NativeProcess = WindowsProcess
internal typealias NativeEnvironment = WindowsEnvironment
internal typealias NativeFileSystem = WindowsFileSystem
internal typealias NativeMappedFile = WindowsMappedFile
internal typealias NativeSocketSystem = WinSockSystem
internal typealias NativeStreamSystem = WindowsStreamSystem
internal typealias NativeMemory = WindowsMemory
internal typealias NativeDebugControl = WindowsDebugControl
internal typealias NativeRegisters = WindowsRegisters
internal typealias NativeImageCursor = WindowsImageCursor
internal typealias NativeProcessCursor = WindowsProcessCursor
internal typealias NativeThread = WindowsThread
#else
internal typealias NativeProcess = UnixProcess
internal typealias NativeEnvironment = UnixEnvironment
internal typealias NativeFileSystem = UnixFileSystem
internal typealias NativeMappedFile = UnixMappedFile
internal typealias NativeSocketSystem = BSDSocketSystem
internal typealias NativeStreamSystem = UnixStreamSystem
internal typealias NativeThread = UnixThread
#if os(anyAppleOS)
internal typealias NativeMemory = DarwinMemory
internal typealias NativeDebugControl = DarwinDebugControl
internal typealias NativeImageCursor = DarwinImageCursor
internal typealias NativeProcessCursor = BSDProcessCursor
#if arch(arm64)
internal typealias NativeRegisters = DarwinARM64Registers
#else
internal typealias NativeRegisters = DarwinX86Registers
#endif
#elseif os(Android) || os(Linux)
internal typealias NativeMemory = LinuxMemory
internal typealias NativeDebugControl = LinuxDebugControl
internal typealias NativeImageCursor = LinuxImageCursor
internal typealias NativeProcessCursor = LinuxProcessCursor
internal typealias NativeRegisters = LinuxRegisters
#elseif os(FreeBSD) || os(OpenBSD)
internal typealias NativeMemory = BSDMemory
internal typealias NativeDebugControl = BSDDebugControl
internal typealias NativeImageCursor = BSDImageCursor
internal typealias NativeProcessCursor = BSDProcessCursor
internal typealias NativeRegisters = BSDRegisters
#endif
#endif
