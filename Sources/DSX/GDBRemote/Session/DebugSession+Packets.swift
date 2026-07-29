// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func handle(_ packet: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch packet {
    case .extended, .debug, .QLaunchArch:
      try writer.append("OK")
    case .baud:
      try writer.baud(payload)
    case .breakpoint:
      try breakpoint(payload, state: state, writer: &writer)
    case .input:
      try input(payload, state: state, writer: &writer)
    case .stop:
      return try status(payload, state: &state, writer: &writer)
    case .arguments:
      try arguments(payload, writer: &writer)
    case .C:
      return try resume(payload, operation: .resume, signal: true, state: state,
                        writer: &writer)
    case .detach:
      try detach(payload, state: &state, writer: &writer)
    case .G:
      try write(registers: payload, state: state, writer: &writer)
    case .H:
      try select(payload, state: &state, writer: &writer)
    case .M:
      try write(memory: payload, state: state, writer: &writer)
    case .MultiMemRead:
      try ranges(payload, state: state, writer: &writer)
    case .P:
      try write(register: payload, state: state, writer: &writer)
    case .raw:
      try launch.environment(raw: payload, writer: &writer)
    case .QListThreadsInStopReply:
      return try state.negotiation.threads(writer: &writer)
    case .QNonStop:
      return try nonstop(payload, state: &state, writer: &writer)
    case .QCatchSyscalls:
      try syscalls(payload, writer: &writer)
    case .QPassSignals:
      try signals.pass(payload, compatibility: state.compatibility,
                       writer: &writer)
    case .QProgramSignals:
      try state.program(payload, writer: &writer)
    case .QSetIgnoredExceptions:
      try ignore(payload, writer: &writer)
    case .QRestoreRegisterState:
      try restore(payload, state: state, writer: &writer)
    case .QSaveRegisterState:
      try save(payload, state: state, writer: &writer)
    case .QSyncThreadState:
      try sync(payload, writer: &writer)
    case .QThreadSuffixSupported:
      return try state.negotiation.suffix(writer: &writer)
    case .QThreadEvents:
      try state.events(payload, writer: &writer)
    case .QThreadOptions:
      try state.options(payload, session: self, writer: &writer)
    case .S:
      return try resume(payload, operation: .step, signal: true, state: state,
                        writer: &writer)
    case .alive:
      try debuggee.alive(payload, writer: &writer)
    case .X:
      try write(binary: payload, state: state, writer: &writer)
    case .Z:
      try insert(payload, state: state, writer: &writer)
    case .interrupt:
      return try interrupt(payload, state: &state, writer: &writer)
    case .allocate:
      try allocate(payload, state: state, writer: &writer)
    case .deallocate:
      try deallocate(payload, state: state, writer: &writer)
    case .resume:
      return try resume(payload, operation: .resume, state: state,
                        writer: &writer)
    case .g:
      try read(registers: payload, state: state, writer: &writer)
    case .loader:
      try debuggee.loader(payload, state: state, writer: &writer)
    case .threads:
      return try threads(payload, state: state, writer: &writer)
    case .context:
      try context(payload, writer: &writer)
    case .jMultiBreakpoint:
      return try breakpoints(payload, state: state, writer: &writer)
    case .libraries:
      try libraries(payload, state: &state, writer: &writer)
    case .cache:
      try debuggee.cache(payload, state: state, writer: &writer)
    case .kill:
      return try kill(payload, state: &state, writer: &writer)
    case .m:
      try read(memory: payload, state: state, writer: &writer)
    case .x:
      try read(binary: payload, state: state, writer: &writer)
    case .p:
      try read(register: payload, state: state, writer: &writer)
    case .attached:
      return try attached(payload, writer: &writer)
    case .qC:
      try debuggee.current(payload, state: state, writer: &writer)
    case .qEcho:
      try writer.append(payload)
    case .qFileLoadAddress:
      try debuggee.load(payload, state: state, writer: &writer)
    case .qGetPid:
      try pid(payload, state: state, writer: &writer)
    case .qLaunchSuccess:
      try success(writer: &writer)
    case .qMemoryRegionInfoSupported, .qStepPacketSupported,
         .qSyncThreadStateSupported, .qVAttachOrWaitSupported:
      try writer.append("OK")
    case .qMemoryRegionInfo:
      try debuggee.region(payload, state: state, writer: &writer)
    case .qOffsets:
      try offsets(payload, state: state, writer: &writer)
    case .qProcessInfo:
      try info(payload, state: state, writer: &writer)
    case .qRegisterInfo:
      let registers = try description(state)
      try registers.info(payload, state: state, writer: &writer)
    case .qLLDBSaveCore:
      try core(payload, writer: &writer)
    case .qRcmd:
      try writer.command(payload)
      return .close
    case .qSearch:
      try search(payload, state: state, writer: &writer)
    case .qShlibInfoAddr:
      try debuggee.library(payload, state: state, writer: &writer)
    case .qThreadExtraInfo:
      try debuggee.thread(payload, writer: &writer)
    case .qSpeedTest:
      try writer.speed(payload)
    case .qSupportsDetachAndStayStopped:
      try writer.detachment(payload)
    case .qThreadStopInfo:
      return try stopped(payload, state: state, writer: &writer)
    case .qWatchpointSupportInfo:
      try watchpoints(payload, state: state, writer: &writer)
    case .transfer(let object):
      return try transfer(object, payload: payload, state: &state,
                          writer: &writer)
    case .qfThreadInfo:
      try state.restart(threads: debuggee, writer: &writer)
    case .qsThreadInfo:
      try state.threads(debuggee, writer: &writer)
    case .step:
      return try resume(payload, operation: .step, state: state,
                        writer: &writer)
    case .attach:
      return try attach(payload, state: &state, writer: &writer)
    case .vAttachName:
      try attach(payload, policy: .now)
      return .none
    case .vAttachOrWait:
      try attach(payload, policy: .either)
      return .none
    case .vAttachWait:
      try attach(payload, policy: .future)
      return .none
    case .vCont:
      return try vcont(payload, state: &state, writer: &writer)
    case .vCtrlC:
      try interrupt(state: state, writer: &writer)
    case .vKill:
      try terminate(payload, state: &state, writer: &writer)
      return .none
    case .vStdio:
      try state.stdio(writer: &writer)
    case .vStopped:
      try state.stopped(writer: &writer)
    case .run:
      try launch.run(payload)
      _ = try translate(spawn())
      return .none
    case .z:
      try remove(payload, state: state, writer: &writer)
    case .tls:
      throw .unsupported
    case .tib:
      try debuggee.tib(payload, writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }
}
