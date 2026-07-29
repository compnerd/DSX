// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private typealias ProcessOutput = OutputSpan<ProcessIdentifier>

private final class PacketStorage: @unchecked Sendable {
  fileprivate var actions: Array<Debuggee.Continuation>
  fileprivate var sites: Array<BreakpointSite>
  fileprivate var interrupted: Bool
  fileprivate var terminated: ProcessIdentifier?
  fileprivate var saved: ProcessThreadIdentifier?
  fileprivate var restored: UInt64?

  fileprivate init() {
    actions = Array<Debuggee.Continuation>()
    sites = Array<BreakpointSite>()
    interrupted = false
    terminated = nil
    saved = nil
    restored = nil
  }
}

private struct PacketProcesses: Sendable {
  fileprivate let storage: PacketStorage

  fileprivate mutating func launch(_ configuration: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    ProcessIdentifier(rawValue: 1)
  }

  fileprivate mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {}

  fileprivate mutating func detach(_ process: ProcessIdentifier,
                                   stopped: Bool) throws(Debuggee.Error) {}

  fileprivate mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    storage.interrupted = true
  }

  fileprivate mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    storage.terminated = process
  }

  fileprivate mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    storage.actions.removeAll()
    for index in 0 ..< actions.count {
      storage.actions.append(actions[index])
    }
  }

  fileprivate mutating func event() throws(Debuggee.Error) -> Debuggee.Event {
    throw .state
  }
}

private struct PacketBreakpoints: Sendable {
  fileprivate let storage: PacketStorage

  fileprivate mutating func insert(_ process: ProcessIdentifier,
                                   breakpoint: BreakpointSite)
      throws(Debuggee.Error) -> BreakpointIdentifier {
    storage.sites.append(breakpoint)
    return BreakpointIdentifier(rawValue: UInt64(storage.sites.count))
  }

  fileprivate mutating func remove(_ process: ProcessIdentifier,
                                   breakpoint: BreakpointIdentifier)
      throws(Debuggee.Error) {
    guard breakpoint.rawValue > 0,
        breakpoint.rawValue <= storage.sites.count else {
      throw .breakpoint
    }
    storage.sites.remove(at: Int(breakpoint.rawValue - 1))
  }

  fileprivate func find(_ process: ProcessIdentifier,
                        breakpoint: BreakpointSite) -> BreakpointIdentifier? {
    guard let index = storage.sites.firstIndex(of: breakpoint) else {
      return nil
    }
    return BreakpointIdentifier(rawValue: UInt64(index + 1))
  }

  fileprivate mutating func enable(_ breakpoint: BreakpointIdentifier,
                                   thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {}

  fileprivate mutating func disable(_ breakpoint: BreakpointIdentifier,
                                    thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {}

  fileprivate mutating func hit(_ stop: Debuggee.Stop) throws(Debuggee.Error)
      -> BreakpointIdentifier? {
    nil
  }
}

private final class AttachStorage: @unchecked Sendable {
  fileprivate var attached: ProcessIdentifier?
  fileprivate var existing: Bool?
  fileprivate var name: String?
}

private struct AttachPlatform: Sendable {
  fileprivate let process: ProcessIdentifier?

  fileprivate mutating func list(_ cursor: inout Int?,
                                 into output: inout ProcessOutput)
      throws(Debuggee.Error) {}

  fileprivate func info(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Debuggee.Process.Info {
    Debuggee.Process.Info(process: process, parent: nil, name: "inferior",
                          architecture: "test")
  }

  fileprivate mutating func next(_ cursor: inout Int?) throws(Debuggee.Error)
      -> ProcessIdentifier? {
    guard case .none = cursor else {
      return nil
    }
    cursor = 1
    return process
  }
}

private struct AttachProcesses: Sendable {
  fileprivate let storage: AttachStorage

  fileprivate mutating func launch(_ configuration: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    throw .unsupported
  }

  fileprivate mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    storage.attached = process
  }

  fileprivate mutating func detach(_ process: ProcessIdentifier,
                                   stopped: Bool) throws(Debuggee.Error) {}

  fileprivate mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {}

  fileprivate mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {}

  fileprivate mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {}

  fileprivate mutating func event() throws(Debuggee.Error) -> Debuggee.Event {
    throw .state
  }
}

private struct AttachSession: Sendable {
  fileprivate var platform: AttachPlatform
  fileprivate var processes: AttachProcesses
  fileprivate var debuggee = Debuggee()
  fileprivate let storage: AttachStorage

  fileprivate mutating func pending() {}

  fileprivate mutating func queue(_ name: String, existing: Bool)
      throws(Debuggee.Error) {
    storage.name = name
    storage.existing = existing
  }
}

private struct PacketSession: Sendable {
  fileprivate var launch: Debuggee.Launch
  fileprivate var processes: PacketProcesses
  fileprivate var breakpoints: PacketBreakpoints
  fileprivate var debuggee: Debuggee
  fileprivate let storage: PacketStorage

  fileprivate init(_ storage: PacketStorage) {
    launch = Debuggee.Launch()
    processes = PacketProcesses(storage: storage)
    breakpoints = PacketBreakpoints(storage: storage)
    self.storage = storage
    let process = ProcessIdentifier(rawValue: 1)
    let identifier =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, state: .stopped,
                           threads: [Debuggee.Thread(identifier: identifier)]),
        ])
  }

  fileprivate mutating func save(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    processes.storage.saved = thread
    return 1
  }

  fileprivate mutating func restore(_ identifier: UInt64,
                                    thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    processes.storage.restored = identifier
  }
}

private protocol PacketHandler: GDBPacketHandler
    where Context == PacketSession {}

extension PacketHandler {
  internal static var features: GDBRemoteFeatures {
    []
  }
}

private enum SignalStepPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let (signal, address) =
        try GDBExecution.signal(payload, compatibility: state.compatibility)
    let action =
        Debuggee.Continuation(selection: state.selection.resume,
                              operation: .step, signal: signal,
                              address: address)
    let actions: InlineArray<1, Debuggee.Continuation> = [action]
    do {
      try session.processes.resume(actions.span)
    } catch {
      throw .debuggee(error)
    }
    return .none
  }
}

private enum SignalResumePacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let (signal, address) =
        try GDBExecution.signal(payload, compatibility: state.compatibility)
    let action =
        Debuggee.Continuation(selection: state.selection.resume,
                              operation: .resume, signal: signal,
                              address: address)
    do {
      if case .thread(let thread) = state.selection.resume {
        let fallback =
            Debuggee.Continuation(selection: .process(thread.process),
                                  operation: .resume)
        let actions: InlineArray<2, Debuggee.Continuation> = [action, fallback]
        try session.processes.resume(actions.span)
      } else {
        let actions: InlineArray<1, Debuggee.Continuation> = [action]
        try session.processes.resume(actions.span)
      }
    } catch {
      throw .debuggee(error)
    }
    return .none
  }
}

private enum VContPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard payload.count == 1, payload[0] == UInt8(ascii: "?") else {
      throw .unsupported
    }
    try writer.append("vCont;c;C;s;S;t")
    return .reply
  }
}

private enum InterruptPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = state.selection.resume
    let process =
        try GDBPacketScope.process(selection, debuggee: session.debuggee)
    do {
      try session.processes.interrupt(process)
    } catch {
      throw .debuggee(error)
    }
    return .none
  }
}

private enum ThreadEventPacket: GDBPacketHandler {
  internal typealias Context = DebugSession

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBThreadEventPacket.handle(payload, state: &state, writer: &writer)
    return .reply
  }
}

private enum ThreadOptionPacket: GDBPacketHandler {
  internal typealias Context = DebugSession

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBThreadOptionPacket.handle(payload, session: session, state: &state,
                                     writer: &writer)
    return .reply
  }
}

private enum SelectThreadPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard payload.count > 1 else {
      throw .malformed
    }
    let identifier =
        try GDBThreadIdentifier.parse(payload.extracting(1...),
                                      debuggee: session.debuggee)
    switch payload[0] {
    case UInt8(ascii: "c"):
      state.selection.resume = identifier
    case UInt8(ascii: "g"):
      state.selection.general = identifier
    default:
      throw .malformed
    }
    try writer.append("OK")
    return .reply
  }
}

private enum InsertBreakpointPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let site = try GDBBreakpointPacket.parse(payload)
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    do {
      _ = try session.breakpoints.insert(process, breakpoint: site)
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
    return .reply
  }
}

private enum RemoveBreakpointPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let site = try GDBBreakpointPacket.parse(payload)
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    guard let identifier =
        session.breakpoints.find(process, breakpoint: site) else {
      throw .debuggee(.breakpoint)
    }
    do {
      try session.breakpoints.remove(process, breakpoint: identifier)
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
    return .reply
  }
}

private enum SaveRegisterStatePacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard payload.isEmpty else {
      throw .malformed
    }
    let thread =
        try GDBPacketScope.thread(nil, selection: state.selection.general,
                                  fallback: state.selection.stopped,
                                  debuggee: session.debuggee)
    let identifier: UInt64
    do {
      identifier = try session.save(thread)
    } catch {
      throw .debuggee(error)
    }
    try writer.decimal(identifier)
    return .reply
  }
}

private enum RestoreRegisterStatePacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    let identifier = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
    do {
      try session.restore(identifier, thread: nil)
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
    return .reply
  }
}

private enum KillProcessPacket: PacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty, session.debuggee.contains(process) else {
      throw .debuggee(.process)
    }
    do {
      try session.processes.terminate(process)
    } catch {
      throw .debuggee(error)
    }
    state.termination = .extended(process)
    return .none
  }
}

private enum WorkingDirectoryPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("QSetWorkingDir:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBWorkingDirectoryPacket.handle(payload, launch: &session.launch,
                                         writer: &writer)
    return .reply
  }
}

private enum EnvironmentPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("QEnvironmentHexEncoded:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBEnvironmentPacket.handle(payload, launch: &session.launch,
                                    writer: &writer)
    return .reply
  }
}

private enum EnvironmentResetPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("QEnvironmentReset")
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBEnvironmentPacket.reset(payload, launch: &session.launch,
                                   writer: &writer)
    return .reply
  }
}

private enum EnvironmentUnsetPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("QEnvironmentUnset:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBEnvironmentPacket.unset(payload, launch: &session.launch,
                                   writer: &writer)
    return .reply
  }
}

private enum ArgumentsPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("A", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBArgumentsPacket.handle(payload, launch: &session.launch,
                                  writer: &writer)
    return .reply
  }
}

private enum RunPacket: GDBPacketHandler {
  internal typealias Context = PacketSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("vRun", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout PacketSession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBRunPacket.configure(payload, launch: &session.launch)
    try writer.append("OK")
    return .reply
  }
}

private enum AttachWaitPacket: GDBPacketHandler {
  internal typealias Context = AttachSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("vAttachWait;", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout AttachSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try attach(payload, policy: .future, session: &session, state: &state)
  }
}

private enum AttachOrWaitPacket: GDBPacketHandler {
  internal typealias Context = AttachSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("vAttachOrWait;", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout AttachSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try attach(payload, policy: .either, session: &session, state: &state)
  }
}

private func attach(_ payload: borrowing Span<UInt8>, policy: GDBAttachPolicy,
                    session: inout AttachSession,
                    state: inout GDBRemoteSessionState) throws(GDBHandlerError)
    -> GDBPacketDisposition {
  let name = try GDBNamedAttach.name(payload)
  let plan = try plan(name, policy: policy, session: &session)
  switch plan {
  case .attach(let process):
    do {
      try session.processes.attach(process)
    } catch {
      throw .debuggee(error)
    }
    session.debuggee.insert(Debuggee.Process(identifier: process))
    session.pending()
  case .queue(let name, let existing):
    do {
      try session.queue(name, existing: existing)
    } catch {
      throw .debuggee(error)
    }
  }
  return .none
}

private func plan(_ name: String, policy: GDBAttachPolicy,
                  session: inout AttachSession) throws(GDBHandlerError)
    -> GDBNamedAttachPlan {
  if policy == .future {
    return .queue(name, existing: true)
  }
  var cursor: Int?
  var process: ProcessIdentifier?
  do {
    while let candidate = try session.platform.next(&cursor) {
      let info = try session.platform.info(candidate)
      if info.name == name {
        process = candidate
        break
      }
    }
  } catch {
    throw .debuggee(error)
  }
  if let process {
    return .attach(process)
  }
  guard policy == .either else {
    throw .debuggee(.process)
  }
  return .queue(name, existing: false)
}

@Suite
internal struct GDBProcessPacketTests {
  private typealias Failure = GDBHandlerError

  @Test
  internal func nonstop() throws {
    var session = DebugSession()
    var state = GDBRemoteSessionState(compatibility: .gdb)
    let enabled =
        try response(GDBNonStopPacket.self, packet: "QNonStop:1",
                     session: &session, state: &state)
    #expect(enabled == Array("OK".utf8))
    let nonstop = state.nonstop
    #expect(nonstop)

    let pending = Array("W00".utf8)
    state.stops.record(pending.span)
    let repeated =
        try response(GDBNonStopPacket.self, packet: "QNonStop:1",
                     session: &session, state: &state)
    #expect(repeated == Array("OK".utf8))
    let retained = state.stops.first
    #expect(retained == pending)

    let disabled =
        try response(GDBNonStopPacket.self, packet: "QNonStop:0",
                     session: &session, state: &state)
    #expect(disabled == Array("OK".utf8))
    #expect(state.nonstop == false)
    let empty = state.stops.first == nil
    #expect(empty)
  }

  @Test
  internal func threads() throws {
    let storage = PacketStorage()
    let packet = PacketSession(storage)
    var session = DebugSession(debuggee: packet.debuggee)
    var state =
        GDBRemoteSessionState(compatibility: .gdb,
                              features: [.events, .options])
    let enabled = try response(ThreadEventPacket.self,
                               packet: "QThreadEvents:1", session: &session,
                               state: &state)
    #expect(enabled == Array("OK".utf8))
    let events = state.events
    #expect(events)

    let configured = try response(ThreadOptionPacket.self,
                                  packet: "QThreadOptions;2:p1.2",
                                  session: &session, state: &state)
    #expect(configured == Array("OK".utf8))
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    #expect(state.options.contains(thread, option: 0x02))
  }

  @Test
  internal func execution() throws {
    let storage = PacketStorage()
    var session = PacketSession(storage)
    let stepped =
        try response(SignalStepPacket.self, packet: "S0b;1234",
                     session: &session)
    #expect(stepped.isEmpty)
    let action = try #require(storage.actions.first)
    #expect(action.operation == .step)
    #expect(action.signal == 0x0b)
    #expect(action.address == Debuggee.Address(rawValue: 0x1234))

    let query =
        try response(VContPacket.self, packet: "vCont?", session: &session)
    #expect(query == Array("vCont;c;C;s;S;t".utf8))

    let interrupt =
        try response(InterruptPacket.self, packet: "\u{3}", session: &session)
    #expect(interrupt.isEmpty)
    #expect(storage.interrupted)
  }

  @Test
  internal func signal() throws {
    #expect(GDBStopPacket.signal(.exception(0x91)) == 0x91)
    #expect(GDBStopPacket.signal(.exception(0x90)) == 0x05)
#if os(Android) || os(Linux)
    #expect(GDBSignal.protocol(10, compatibility: .gdb) == 30)
    #expect(GDBSignal.native(30, compatibility: .gdb) == 10)
    #expect(GDBSignal.protocol(12, compatibility: .gdb) == 31)
    #expect(GDBSignal.native(31, compatibility: .gdb) == 12)
#else
    #expect(GDBSignal.protocol(29, compatibility: .gdb) == 142)
    #expect(GDBSignal.native(142, compatibility: .gdb) == 29)
#endif
    #expect(GDBSignal.protocol(10, compatibility: .lldb) == 10)
    #expect(GDBSignal.native(10, compatibility: .lldb) == 10)

    let storage = PacketStorage()
    var session = PacketSession(storage)
    var state = GDBRemoteSessionState(compatibility: .gdb)
    let selected =
        try response(SelectThreadPacket.self, packet: "Hc2", session: &session,
                     state: &state)
    #expect(selected == Array("OK".utf8))
    let resumed =
        try response(SignalResumePacket.self, packet: "C1e", session: &session,
                     state: &state)
    #expect(resumed.isEmpty)
    let action = try #require(storage.actions.first)
    #expect(storage.actions.count == 2)
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    #expect(action.selection == .thread(thread))
    #expect(action.operation == .resume)
#if os(Android) || os(Linux)
    #expect(action.signal == 10)
#else
    #expect(action.signal == 30)
#endif
    #expect(storage.actions[1].selection == .process(thread.process))
    #expect(storage.actions[1].operation == .resume)
    #expect(storage.actions[1].signal == nil)
  }

  @Test
  internal func breakpoint() throws {
    let storage = PacketStorage()
    var session = PacketSession(storage)
    let inserted =
        try response(InsertBreakpointPacket.self, packet: "Z4,2000,8",
                     session: &session)
    #expect(inserted == Array("OK".utf8))
    #expect(storage.sites.first?.kind == .watchpoint(.readwrite))

    let removed =
        try response(RemoveBreakpointPacket.self, packet: "z4,2000,8",
                     session: &session)
    #expect(removed == Array("OK".utf8))
    #expect(storage.sites.isEmpty)
  }

  @Test
  internal func batching() throws {
    var session = DebugSession()
    let empty =
        try response(GDBMultiBreakpointPacket.self,
                     packet: #" {"breakpoint_requests":[]}"#, session: &session)
    #expect(empty == Array(#"{"results":[]}"#.utf8))
    #expect(throws: GDBHandlerError.self) {
      try response(GDBMultiBreakpointPacket.self, packet: "[]",
                   session: &session)
    }
  }

  @Test
  internal func watchpoint() throws {
    let storage = PacketStorage()
    var session = DebugSession(debuggee: PacketSession(storage).debuggee)
    let identifier =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let address = Debuggee.Address(rawValue: 0x2000)
    let data = Debuggee.ExceptionData(count: 2) { index in
      index == 0 ? 0x102 : address.rawValue & ~0x7
    }
    let fault =
        Debuggee.Fault(address: address, code: 6, data: data, domain: .mach)
    let stop = Debuggee.Stop(thread: identifier,
                             reason: .watchpoint(.write, address), fault: fault)
    session.debuggee.observe(.stopped(stop))
    var state = GDBRemoteSessionState(compatibility: .lldb)
    let reply =
        try response(GDBStopPacket.self, packet: "?", session: &session,
                     state: &state)
    let expected =
        Array("T05thread:2;reason:watchpoint;description:38313932;".utf8)
    #expect(reply == expected)
    let threads =
        try response(GDBThreadsInfoPacket.self, packet: "jThreadsInfo",
                     session: &session, state: &state)
    let listing = "[{\"tid\":2,\"reason\":\"watchpoint\"," +
        "\"description\":\"8192\"}]"
    #expect(threads == Array(listing.utf8))
  }

  @Test
  internal func fork() throws {
    let storage = PacketStorage()
    var session = DebugSession(debuggee: PacketSession(storage).debuggee)
    let parent =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let child =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 3),
                                thread: ThreadIdentifier(rawValue: 4))
    let event = Debuggee.Event.forked(Debuggee.Fork(parent: parent,
                                                    child: child, vfork: false))
    session.debuggee.observe(event)
    var state =
        GDBRemoteSessionState(compatibility: .lldb, features: [.multiprocess])
    state.negotiation.enable(.multiprocess)
    state.observe(event)
    let reply =
        try response(GDBStopPacket.self, packet: "?", session: &session,
                     state: &state)
    let expected = Array("T05thread:p1.2;reason:fork;fork:p3.4;".utf8)
    #expect(reply == expected)
  }

  @Test
  internal func fault() throws {
    let storage = PacketStorage()
    var session = DebugSession(debuggee: PacketSession(storage).debuggee)
    let identifier =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let address = Debuggee.Address(rawValue: 0xdeadbeef)
    let fault = Debuggee.Fault(address: address, code: 1, domain: .posix)
    let stop =
        Debuggee.Stop(thread: identifier, reason: .signal(11), fault: fault)
    session.debuggee.observe(.stopped(stop))
    var state = GDBRemoteSessionState(compatibility: .lldb)
    let reply =
        try response(GDBStopPacket.self, packet: "?", session: &session,
                     state: &state)
    let expected = "T0bthread:2;reason:signal;description:" +
        "7369676e616c20534947534547563a2061646472657373206e6f74206d617070" +
        "656420746f206f626a65637420286661756c7420616464726573733d30786465" +
        "61646265656629;"
    #expect(reply == Array(expected.utf8))
    let threads =
        try response(GDBThreadsInfoPacket.self, packet: "jThreadsInfo",
                     session: &session, state: &state)
    let listing = "[{\"tid\":2,\"reason\":\"signal\",\"signal\":11," +
        "\"description\":\"signal SIGSEGV: address not mapped to object " +
        "(fault address=0xdeadbeef)\"}]"
    #expect(threads == Array(listing.utf8))

    do {
      let data = Debuggee.ExceptionData(count: 2) { index in
        index == 0 ? 1 : 0xdeadbeef
      }
      let exception = Debuggee.Fault(address: address, code: 0xc0000005,
                                     data: data, domain: .windows)
      let crashed = Debuggee.Stop(thread: identifier,
                                  reason: .exception(0xc0000005),
                                  fault: exception, chance: .second)
      session.debuggee.observe(.stopped(crashed))
      let reply =
          try response(GDBStopPacket.self, packet: "?", session: &session,
                       state: &state)
      let expected = "T05thread:2;reason:exception;description:" +
          "457863657074696f6e203078633030303030303520656e636f756e7465726564" +
          "20617420616464726573732030786465616462656566;"
      #expect(reply == Array(expected.utf8))
      let threads =
          try response(GDBThreadsInfoPacket.self, packet: "jThreadsInfo",
                       session: &session, state: &state)
      let listing = "[{\"tid\":2,\"reason\":\"exception\"," +
          "\"description\":\"Exception 0xc0000005 encountered at address " +
          "0xdeadbeef\",\"signal\":5}]"
      #expect(threads == Array(listing.utf8))
    }
  }

  @Test
  internal func launch() throws {
    let storage = PacketStorage()
    var session = PacketSession(storage)
    let working = try response(WorkingDirectoryPacket.self,
                               packet: "QSetWorkingDir:2f746d70",
                               session: &session)
    #expect(working == Array("OK".utf8))
    #expect(session.launch.working == "/tmp")

    let environment = try response(EnvironmentPacket.self,
                                   packet: "QEnvironmentHexEncoded:413d42",
                                   session: &session)
    #expect(environment == Array("OK".utf8))
    let expected = [Debuggee.Environment(name: "A", value: "B")]
    #expect(session.launch.environment == expected)

    let unset = try response(EnvironmentUnsetPacket.self,
                             packet: "QEnvironmentUnset:41", session: &session)
    #expect(unset == Array("OK".utf8))
    let removed = [Debuggee.Environment(name: "A", value: nil)]
    #expect(session.launch.environment == removed)

    _ = try response(EnvironmentPacket.self,
                     packet: "QEnvironmentHexEncoded:413d42", session: &session)
    let reset = try response(EnvironmentResetPacket.self,
                             packet: "QEnvironmentReset", session: &session)
    #expect(reset == Array("OK".utf8))
    #expect(session.launch.environment.isEmpty)

    let arguments = try response(ArgumentsPacket.self,
                                 packet: "A12,0,2f62696e2f78",
                                 session: &session)
    #expect(arguments == Array("OK".utf8))
    #expect(session.launch.executable == "/bin/x")

    let run = try response(RunPacket.self,
                           packet: "vRun;2f62696e2f78;2f746d702f6f7574",
                           session: &session)
    #expect(run == Array("OK".utf8))
    #expect(session.launch.executable == "/bin/x")
    #expect(session.launch.arguments == ["/tmp/out"])

    #expect(throws: GDBHandlerError.unsupported) {
      try response(ArgumentsPacket.self, packet: "Aunknown", session: &session)
    }
  }

  @Test
  internal func compatibility() throws {
    let storage = PacketStorage()
    var packet = PacketSession(storage)
    var session = DebugSession(debuggee: packet.debuggee)
    let identifier =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let record = Debuggee.Stop(thread: identifier, reason: .breakpoint)
    session.debuggee.observe(.stopped(record))
    let other =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 0xdead))
    session.debuggee.observe(.stopped(Debuggee.Stop(thread: other,
                                                    reason: .interrupt)))
    var state =
        GDBRemoteSessionState(compatibility: .lldb, features: [
                                .libraries, .stopthreads, .threads,
                                .threadsuffix,
                              ])
    state.negotiation.advertise()
    let initial =
        try response(GDBStopPacket.self, packet: "?", session: &session,
                     state: &state)
    let expected = Array("T05thread:2;reason:breakpoint;library:1;".utf8)
    #expect(initial == expected)
    let repeated =
        try response(GDBStopPacket.self, packet: "?", session: &session,
                     state: &state)
    #expect(repeated == expected)

    let threads =
        try response(GDBThreadsInfoPacket.self, packet: "jThreadsInfo",
                     session: &session, state: &state)
    let listing =
        "[{\"tid\":2,\"reason\":\"breakpoint\"}," +
        "{\"tid\":57005,\"reason\":\"signal\",\"signal\":" +
        "\(Host.interrupt)}]"
    #expect(threads == Array(listing.utf8))

    let transfer =
        try response(GDBTransferPacket.self,
                     packet: "qXfer:threads:read::0,1000", session: &session,
                     state: &state)
    let xml =
        "l<?xml version=\"1.0\"?><threads>" +
        "<thread id=\"p1.2\"/><thread id=\"p1.dead\"/></threads>"
    #expect(transfer == Array(xml.utf8))

    let suffix =
        try response(TestThreadSuffixPacket.self,
                     packet: "QThreadSuffixSupported", session: &session,
                     state: &state)
    #expect(suffix == Array("OK".utf8))
    #expect(state.negotiation.enabled.contains(.threadsuffix))

    let stops =
        try response(TestListThreadsPacket.self,
                     packet: "QListThreadsInStopReply", session: &session,
                     state: &state)
    #expect(stops == Array("OK".utf8))
    state.selection.general = .thread(identifier)
    let saved =
        try response(SaveRegisterStatePacket.self, packet: "QSaveRegisterState",
                     session: &packet, state: &state)
    #expect(saved == Array("1".utf8))
    #expect(storage.saved == identifier)
    let restored =
        try response(RestoreRegisterStatePacket.self,
                     packet: "QRestoreRegisterState:1", session: &packet,
                     state: &state)
    #expect(restored == Array("OK".utf8))
    #expect(storage.restored == 1)
    let stop =
        try response(GDBThreadStopInfoPacket.self, packet: "qThreadStopInfo2",
                     session: &session, state: &state)
    let report = Array("T05thread:2;reason:breakpoint;threads:2,dead;".utf8)
    #expect(stop == report)

    session.state = .stopped(.attached)
    let attached =
        try response(GDBAttachedPacket.self, packet: "qAttached:1",
                     session: &session, state: &state)
    #expect(attached == Array("1".utf8))

    let killed =
        try response(KillProcessPacket.self, packet: "vKill;1",
                     session: &packet, state: &state)
    #expect(killed.isEmpty)
    #expect(storage.terminated == ProcessIdentifier(rawValue: 1))
    if case .extended(let process) = state.termination {
      #expect(process == ProcessIdentifier(rawValue: 1))
    } else {
      Issue.record("termination was not extended")
    }
  }

  @Test
  internal func namedattach() throws {
    let process = ProcessIdentifier(rawValue: 42)
    let storage = AttachStorage()
    var session =
        AttachSession(platform: AttachPlatform(process: process),
                      processes: AttachProcesses(storage: storage),
                      storage: storage)
    let name = "696e666572696f72"
    let future = try response(AttachWaitPacket.self,
                              packet: "vAttachWait;\(name)", session: &session)
    #expect(future.isEmpty)
    #expect(storage.attached == nil)
    #expect(storage.name == "inferior")
    #expect(storage.existing == true)

    storage.name = nil
    storage.existing = nil
    let immediate = try response(AttachOrWaitPacket.self,
                                 packet: "vAttachOrWait;\(name)",
                                 session: &session)
    #expect(immediate.isEmpty)
    #expect(storage.attached == process)
    #expect(storage.name == nil)

    let absent = AttachStorage()
    var waiting =
        AttachSession(platform: AttachPlatform(process: nil),
                      processes: AttachProcesses(storage: absent),
                      storage: absent)
    let deferred = try response(AttachOrWaitPacket.self,
                                packet: "vAttachOrWait;\(name)",
                                session: &waiting)
    #expect(deferred.isEmpty)
    #expect(absent.attached == nil)
    #expect(absent.name == "inferior")
    #expect(absent.existing == false)
  }
}

private func response<Handler>(_ handler: Handler.Type, packet: String,
                               session: inout PacketSession) throws
    -> Array<UInt8>
    where Handler: GDBPacketHandler<PacketSession> & ~Copyable {
  var state = GDBRemoteSessionState(compatibility: .gdb)
  return try response(handler, packet: packet, session: &session, state: &state)
}

private func response<Handler>(_ handler: Handler.Type, packet: String,
                               session: inout PacketSession,
                               state: inout GDBRemoteSessionState) throws
    -> Array<UInt8>
    where Handler: GDBPacketHandler<PacketSession> & ~Copyable {
  try perform(handler, packet: packet, session: &session, state: &state)
}

private func response<Context, Handler>(_ handler: Handler.Type, packet: String,
                                        session: inout Context) throws
    -> Array<UInt8>
    where Context: ~Copyable, Handler: GDBPacketHandler<Context> & ~Copyable {
  var state = GDBRemoteSessionState(compatibility: .gdb)
  return try response(handler, packet: packet, session: &session, state: &state)
}

private func response<Context, Handler>(_ handler: Handler.Type, packet: String,
                                        session: inout Context,
                                        state: inout GDBRemoteSessionState)
    throws -> Array<UInt8>
    where Context: ~Copyable, Handler: GDBPacketHandler<Context> & ~Copyable {
  try perform(handler, packet: packet, session: &session, state: &state)
}

private func perform<Context, Handler>(_ handler: Handler.Type, packet: String,
                                       session: inout Context,
                                       state: inout GDBRemoteSessionState)
    throws -> Array<UInt8>
    where Context: ~Copyable, Handler: GDBPacketHandler<Context> & ~Copyable {
  let bytes = Array(packet.utf8)
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(output)
    let result: Result<GDBPacketDisposition, any Error>
    do {
      let match = GDBPacketClassifier.classify(bytes.span)
      let payload = bytes.span.extracting(match.payload...)
      let disposition =
          try GDBPacketDispatch.handle(handler, payload: payload,
                                       session: &session, state: &state,
                                       writer: &writer)
      result = .success(disposition)
    } catch {
      result = .failure(error)
    }
    output = writer.finish()
    switch result {
    case .success:
      break
    case .failure(let error):
      guard let error = error as? GDBHandlerError else {
        throw .unexpected
      }
      throw error
    }
  }
  return response
}
