// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// This uncalled function checks the selected backend during every build.
// Keep it private and unreferenced so it introduces no runtime machinery.
// Only the shared interface belongs here, not platform-specific services.

private typealias Failure = Debuggee.Error

private func validate(_ control: inout NativeDebugControl,
                      process: ProcessIdentifier,
                      child: consuming NativeProcess,
                      file: borrowing NativeMappedFile,
                      images: inout NativeImageCursor,
                      processes: inout NativeProcessCursor,
                      buffer: UnsafeMutableBufferPointer<UInt8>,
                      launch: borrowing Debuggee.Launch,
                      actions: borrowing Debuggee.Continuations,
                      event: borrowing Debuggee.Event,
                      fork: borrowing Debuggee.Fork,
                      site: borrowing BreakpointSite,
                      bytes: borrowing Span<UInt8>,
                      output: inout OutputSpan<UInt8>) throws(Failure) {
  // MARK: - Memory

  let _: (ProcessIdentifier, Debuggee.Address, Int, Debuggee.MemoryRegion?,
          inout OutputSpan<UInt8>) throws(Failure) -> Void =
      NativeMemory.read(_:address:size:mapping:into:)
  // Writes report the committed prefix through count, including on failure.
  let _: (ProcessIdentifier, Debuggee.Address,
          borrowing Span<UInt8>, inout Int) throws(Failure) -> Void =
      NativeMemory.write(_:address:bytes:count:)
  let _: (ProcessIdentifier, ProcessThreadIdentifier?, Debuggee.Address,
          borrowing Span<UInt8>, inout Int) throws(Failure) -> Void =
      NativeMemory.patch(_:thread:address:bytes:count:)
  let _: (ProcessIdentifier,
          Debuggee.Address) throws(Failure) -> Debuggee.MemoryRegion =
      NativeMemory.region(_:address:)
  let _: (ProcessIdentifier, UInt64, Bool, Bool, Bool,
          inout NativeDebugControl) throws(Failure) -> Debuggee.Address =
      NativeMemory.allocate(_:size:readable:writable:executable:control:)
  let _: (ProcessIdentifier, Debuggee.Address, UInt64,
          inout NativeDebugControl) throws(Failure) -> Void =
      NativeMemory.deallocate(_:address:size:control:)

  // MARK: - Registers

  let _: (ProcessThreadIdentifier) throws(Failure) -> Void =
      NativeRegisterState.synchronize(_:)
  let thread = ProcessThreadIdentifier(process: process,
                                       thread: ThreadIdentifier(rawValue: 1))
  var registers = try NativeRegisterState(thread)
  let register = RegisterIdentifier(rawValue: 0)
  let description = RegisterDescription(registers.configuration)
  if let record = description.register(0) {
    let _: RegisterText = description.name(record, compatibility: .gdb)
  }
  try registers.read(register, into: &output)
  try registers.write(register, bytes: bytes)
  let _: UInt64 = try registers.pc
  let _: UInt64 = try registers.fp
  try registers.set(pc: 0)
  let _: Int = NativeRegisterState.checkpoint
  try registers.checkpoint(into: &output)
  try registers.checkpoint(bytes)
  try registers.commit(thread)

  // MARK: - Environment

  typealias Unit = NativeEnvironment.Unit

  let _: () throws(Failure) -> Array<Unit> = NativeEnvironment.read
  let _: (String, inout Array<Unit>) -> Void = NativeEnvironment.encode(_:into:)
  let _: (UnsafeBufferPointer<Unit>, Range<Int>, Range<Int>) -> CInt =
      NativeEnvironment.compare(_:lhs:rhs:)

  // MARK: - File System

  let _: UInt8 = NativeFileSystem.separator
  let _: (UInt8) -> Bool = NativeFileSystem.separates(_:)

  typealias FileHandle = NativeFileSystem.Handle
  typealias FileRoot = NativeFileSystem.Root

  let _: (String) throws(Failure) -> String = NativeFileSystem.canonical(_:)
  let _: (String, UInt32) throws(Failure) -> Void =
      NativeFileSystem.create(_:mode:)
  let _: (String, Bool) throws(Failure) -> Array<String> =
      NativeFileSystem.complete(_:directories:)
  let _: (String, String?) throws(Failure) -> String =
      NativeFileSystem.resolve(_:directory:)
  let _: (ProcessIdentifier) throws(Failure) -> FileRoot? =
      NativeFileSystem.root
  let _: (String, FileOptions, UInt32,
          borrowing FileRoot?) throws(Failure) -> FileHandle =
      NativeFileSystem.open(_:options:mode:root:)
  let _: (FileHandle) throws(Failure) -> Void = NativeFileSystem.close(_:)
  let _: (FileHandle, UInt64, Int,
          inout OutputSpan<UInt8>) throws(Failure) -> Void =
      NativeFileSystem.read(_:offset:size:into:)
  let _: (FileHandle, UInt64, borrowing Span<UInt8>) throws(Failure) -> Int =
      NativeFileSystem.write(_:offset:bytes:)
  let _: (String, borrowing FileRoot?) throws(Failure) -> Void =
      NativeFileSystem.remove(_:root:)
  let _: (String, String, borrowing FileRoot?) throws(Failure) -> Void =
      NativeFileSystem.link(_:at:root:)
  let _: (String, UInt32) throws(Failure) -> Void =
      NativeFileSystem.permissions(_:mode:)
  let _: (String, borrowing FileRoot?) throws(Failure) -> UInt64 =
      NativeFileSystem.size(_:root:)
  let _: (FileHandle) throws(Failure) -> UInt64 = NativeFileSystem.size(_:)
  let _: (String, Bool, borrowing FileRoot?) throws(Failure) -> FileStatus =
      NativeFileSystem.status(_:link:root:)
  let _: (FileHandle) throws(Failure) -> FileStatus =
      NativeFileSystem.status(_:)
  let _: (String, borrowing FileRoot?) throws(Failure) -> String =
      NativeFileSystem.destination(_:root:)
  let _: (borrowing Span<UInt8>, String, Bool) -> Bool =
      NativeFileSystem.matches(_:_:component:)

  // MARK: - Mapped Files

  let _: (String) throws(Failure) -> NativeMappedFile = NativeMappedFile.init
  let _: Span<UInt8> = file.span()

  // MARK: - Checksums

  var checksum = try MD5Checksum()
  let _: Void = try checksum.update(bytes)
  let _: InlineArray<16, UInt8> = try checksum.finish()

  // MARK: - Sockets

  typealias SocketHandle = NativeSocket.Handle

  let _: (SocketHandle, Bool) throws(TransportError) -> SocketHandle =
      NativeSocket.accept(_:network:)
  let _: (SocketHandle, String?) -> Void = NativeSocket.close(_:path:)
  let _: (NetworkEndpoint,
          Bool) throws(TransportError) -> (handle: SocketHandle, port: UInt16) =
      NativeSocket.open(_:listening:)
  let _: (UnixEndpoint, Bool) throws(TransportError) -> SocketHandle =
      NativeSocket.open(_:listening:)
  let _: (borrowing Span<UInt8>) throws(TransportError) -> Void =
      NativeSocket.output(_:)
  let _: (SocketHandle, Int32,
          borrowing Span<WaitHandle>) throws(TransportError) -> WaitResult =
      NativeSocket.wait(_:timeout:events:)
  let _: (SocketHandle, UnsafeMutableRawPointer,
          Int) throws(TransportError) -> Int =
      NativeSocket.receive(_:into:capacity:)
  let _: (SocketHandle, UnsafeRawPointer, Int) throws(TransportError) -> Int =
      NativeSocket.transmit(_:from:count:)

  // MARK: - Streams

  typealias StreamHandle = NativeStream.Handle

  let _: (StreamEndpoint) throws(TransportError) -> StreamHandle =
      NativeStream.open
  let _: (StreamHandle) -> Void = NativeStream.close
  let _: (StreamHandle, Int32,
          borrowing Span<WaitHandle>) throws(TransportError) -> WaitResult =
      NativeStream.wait(_:timeout:events:)
  let _: (StreamHandle, UnsafeMutableRawPointer,
          Int) throws(TransportError) -> Int =
      NativeStream.receive(_:into:capacity:)
  let _: (StreamHandle, UnsafeRawPointer, Int) throws(TransportError) -> Int =
      NativeStream.transmit(_:from:count:)

  // MARK: - Threads

  let _: Array<ProcessThreadIdentifier> = try process.threads

  // MARK: - Images

  let _: (ProcessIdentifier) throws(Failure) -> NativeImageCursor =
      NativeImageCursor.init(_:)
  var libraries = try NativeLibraryCursor(process)
  let _: Debuggee.Library? = try libraries.next()
  let _: Debuggee.Image? = try images.next()

  // MARK: - Processes

  let _: () throws(Failure) -> NativeProcessCursor = NativeProcessCursor.init
  let _: Debuggee.Process.Info? = try processes.next()

  // MARK: - Child Process

  let _: ProcessIdentifier = child.process
  let _: UInt8? = try child.byte(timeout: 0)
  let _: Debuggee.Exit? = try child.status(timeout: 0)
  let _: Void = try child.terminate()
  let _: Int = try child.read(buffer)
  let _: WaitHandle? = child.monitor()

  // MARK: - Debug Control

  let _: NativeDebugControl = NativeDebugControl()
  let _: DebugCapabilities = NativeDebugControl.capabilities
  let _: Int32? = NativeDebugControl.interval
  let _: Void = try control.ignore([])
  let _: Int = try control.watchpoints(process)
  let _: Void = control.libraries(false)
  let _: ProcessIdentifier = try control.launch(launch)
  let _: Void = try control.attach(process)
  let _: Void = try control.detach(process, stopped: false)
  let _: Void = try control.discard(fork)
  let _: Void = try control.interrupt(process)
  let _: Void = try control.terminate(process)
  let _: Void = try control.prepare(actions)
  let _: Void = try control.resume(actions)
  let _: Debuggee.Event? =
      try control.event(blocking: false, output: true, signals: SignalSet())
  let _: Void = try control.complete(event)
  let _: Debuggee.Event? = control.collect()
  let _: Void = try control.recover()
  let _: Void = try control.discard(event)
  let _: Void = try control.close()
  let _: Void =
      try control.breakpoint(process, site: site, thread: nil, enabled: false)
  let _: Void = try control.output(process, into: &output)
  let _: Void = try control.input(process, bytes: bytes)
  let _: Void = try control.syscalls(nil)

  // MARK: - Breakpoints

  let _: StaticString = HardwareBreakpoint.features
  let _: Int? = try HardwareBreakpoint.capacity
  let _: Bool = HardwareBreakpoint.supports(site.kind)
  let _: Bool = HardwareBreakpoint.advance(site.kind)
  let _: Int = ABI.SoftwareBreakpoint.capacity
  let _: BreakpointSite = ABI.breakpoint(site.address)
  let _: Int = try ABI.size(site.address, requested: site.size)
  let _: Void = try ABI.breakpoint(site.size, into: &output)

  // MARK: - Signals

  let _: (CInt) -> UInt8 = SignalCatalog.gdb
  let _: (UInt64) -> CInt? = SignalCatalog.native
}
