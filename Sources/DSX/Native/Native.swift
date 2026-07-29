// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// Native implementation selection.
#if os(Android) || os(Linux)
internal typealias NativeLibraryCursor = LinuxLibraryCursor
#else
internal typealias NativeLibraryCursor = UnsupportedLibraryCursor
#endif

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
internal typealias NativeSocket = WindowsSocket
internal typealias NativeStream = WindowsStream
internal typealias NativeMemory = WindowsMemory
internal typealias NativeDebugControl = WindowsDebugControl
internal typealias NativeRegisterState = WindowsRegisterState
internal typealias NativeImageCursor = WindowsImageCursor
internal typealias NativeProcessCursor = WindowsProcessCursor
#else
internal typealias NativeProcess = UnixProcess
internal typealias NativeEnvironment = UnixEnvironment
internal typealias NativeFileSystem = UnixFileSystem
internal typealias NativeMappedFile = UnixMappedFile
internal typealias NativeSocket = BSDSocket
internal typealias NativeStream = UnixStream
#if os(anyAppleOS)
internal typealias NativeMemory = DarwinMemory
internal typealias NativeDebugControl = DarwinDebugControl
internal typealias NativeImageCursor = SnapshotImageCursor
internal typealias NativeProcessCursor = BSDProcessCursor
#if arch(arm64)
internal typealias NativeRegisterState = DarwinARM64RegisterState
#else
internal typealias NativeRegisterState = DarwinX86RegisterState
#endif
#elseif os(Android) || os(Linux)
internal typealias NativeMemory = LinuxMemory
internal typealias NativeDebugControl = LinuxDebugControl
internal typealias NativeImageCursor = SnapshotImageCursor
internal typealias NativeProcessCursor = LinuxProcessCursor
internal typealias NativeRegisterState = LinuxRegisterState
#elseif os(FreeBSD) || os(OpenBSD)
internal typealias NativeMemory = BSDMemory
internal typealias NativeDebugControl = BSDDebugControl
internal typealias NativeImageCursor = BSDImageCursor
internal typealias NativeProcessCursor = BSDProcessCursor
internal typealias NativeRegisterState = BSDRegisterState
#endif
#endif
