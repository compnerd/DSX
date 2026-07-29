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
      try GDBLegacyControlPacket.acknowledge(payload, writer: &writer)
    case .baud:
      try GDBLegacyControlPacket.baud(payload, writer: &writer)
    case .breakpoint:
      try GDBLegacyBreakpointPacket.handle(payload, session: &self,
                                           state: state, writer: &writer)
    case .input:
      try GDBInferiorInputPacket.handle(payload, session: &self, state: state,
                                        writer: &writer)
    case .stop:
      return try GDBStopPacket.handle(payload, session: &self, state: &state,
                                      writer: &writer)
    case .arguments:
      try GDBArgumentsPacket.launch(payload, session: &self, writer: &writer)
    case .C:
      return try GDBSignalResumePacket.handle(payload, session: &self,
                                              state: &state, writer: &writer)
    case .detach:
      try GDBExecution.detach(payload, session: &self, state: &state,
                              writer: &writer)
    case .G:
      try GDBRegisterPacket.write(payload, session: self, state: state,
                                  writer: &writer)
    case .H:
      try GDBSelectThreadPacket.handle(payload, session: &self, state: &state,
                                       writer: &writer)
    case .M:
      try GDBMemoryPacket.write(payload, debuggee: debuggee, state: &state,
                                writer: &writer)
    case .MultiMemRead:
      try GDBMemoryPacket.ranges(payload, session: self, state: state,
                                 writer: &writer)
    case .P:
      try GDBRegisterPacket.write(payload, number: (), session: self,
                                  state: state, writer: &writer)
    case .raw:
      try GDBEnvironmentPacket.raw(payload, launch: &launch, writer: &writer)
    case .QListThreadsInStopReply:
      return try GDBNegotiationPacket.threads(payload, state: &state,
                                              writer: &writer)
    case .QNonStop:
      return try GDBNonStopPacket.handle(payload, session: &self, state: &state,
                                         writer: &writer)
    case .QCatchSyscalls:
      try GDBSyscallPacket.handle(payload, session: &self, writer: &writer)
    case .QPassSignals:
      try GDBSignalControlPacket.pass(payload, signals: &signals, state: state,
                                      writer: &writer)
    case .QProgramSignals:
      try GDBSignalControlPacket.program(payload, state: &state,
                                         writer: &writer)
    case .QSetIgnoredExceptions:
      try GDBIgnoredExceptionPacket.handle(payload, session: &self,
                                           writer: &writer)
    case .QRestoreRegisterState:
      try GDBRegisterStatePacket.restore(payload, session: &self, state: &state,
                                         writer: &writer)
    case .QSaveRegisterState:
      try GDBRegisterStatePacket.save(payload, session: &self, state: &state,
                                      writer: &writer)
    case .QSyncThreadState:
      try GDBRegisterStatePacket.sync(payload, session: &self, state: &state,
                                      writer: &writer)
    case .QThreadSuffixSupported:
      return try GDBNegotiationPacket.suffix(payload, state: &state,
                                             writer: &writer)
    case .QThreadEvents:
      try GDBThreadEventPacket.handle(payload, state: &state, writer: &writer)
    case .QThreadOptions:
      try GDBThreadOptionPacket.handle(payload, session: self, state: &state,
                                       writer: &writer)
    case .S:
      return try GDBSignalStepPacket.handle(payload, session: &self,
                                            state: &state, writer: &writer)
    case .alive:
      try GDBAlivePacket.handle(payload, session: &self, state: &state,
                                writer: &writer)
    case .X:
      try GDBBinaryMemoryPacket.write(payload, debuggee: debuggee,
                                      state: &state, writer: &writer)
    case .Z:
      try GDBBreakpointPacket.insert(payload, session: &self, state: &state,
                                     writer: &writer)
    case .interrupt:
      return try GDBExecution.interrupt(payload, session: &self, state: &state,
                                        writer: &writer)
    case .allocate:
      try GDBAllocationPacket.allocate(payload, session: &self, state: &state,
                                       writer: &writer)
    case .deallocate:
      try GDBAllocationPacket.deallocate(payload, session: &self, state: &state,
                                         writer: &writer)
    case .resume:
      return try GDBExecution.resume(payload, session: &self, state: &state,
                                     writer: &writer)
    case .g:
      try GDBRegisterPacket.read(payload, session: self, state: state,
                                 writer: &writer)
    case .loader:
      try GDBLoaderPacket.handle(payload, session: self, state: state,
                                 writer: &writer)
    case .threads:
      return try GDBThreadsInfoPacket.handle(payload, session: &self,
                                             state: &state, writer: &writer)
    case .context:
      try GDBThreadContextPacket.handle(payload, session: self, writer: &writer)
    case .jMultiBreakpoint:
      return try GDBMultiBreakpointPacket.handle(payload, session: &self,
                                                 state: &state, writer: &writer)
    case .libraries:
      try GDBLibrariesPacket.handle(payload, session: &self, state: &state,
                                    writer: &writer)
    case .cache:
      try GDBSharedCachePacket.handle(payload, session: self, state: state,
                                      writer: &writer)
    case .kill:
      return try GDBExecution.kill(payload, session: &self, state: &state,
                                   writer: &writer)
    case .m:
      try GDBMemoryPacket.read(payload, session: self, state: &state,
                               writer: &writer)
    case .x:
      try GDBBinaryMemoryPacket.read(payload, session: self, state: &state,
                                     writer: &writer)
    case .p:
      try GDBRegisterPacket.read(payload, number: (), session: self,
                                 state: state, writer: &writer)
    case .attached:
      return try GDBAttachedPacket.handle(payload, session: &self,
                                          state: &state, writer: &writer)
    case .qC:
      try GDBCurrentThreadPacket.handle(payload, session: &self, state: &state,
                                        writer: &writer)
    case .qEcho:
      try GDBEchoPacket.handle(payload, writer: &writer)
    case .qFileLoadAddress:
      try GDBFileLoadAddressPacket.handle(payload, session: &self,
                                          state: &state, writer: &writer)
    case .qGetPid:
      try GDBPIDPacket.handle(payload, session: self, state: state,
                              writer: &writer)
    case .qLaunchSuccess:
      try GDBLaunchSuccessPacket.handle(session: self, writer: &writer)
    case .qMemoryRegionInfoSupported, .qStepPacketSupported,
         .qSyncThreadStateSupported, .qVAttachOrWaitSupported:
      try GDBCapabilityPacket.handle(writer: &writer)
    case .qMemoryRegionInfo:
      try GDBMemoryPacket.region(payload, debuggee: debuggee, state: &state,
                                 writer: &writer)
    case .qOffsets:
      try GDBOffsetsPacket.handle(payload, session: &self, state: state,
                                  writer: &writer)
    case .qProcessInfo:
      try GDBCurrentProcessInfoPacket.handle(payload, session: &self,
                                             state: &state, writer: &writer)
    case .qRegisterInfo:
      let registers = RegisterDescription()
      try GDBRegisterPacket.info(payload, registers: registers, state: &state,
                                 writer: &writer)
    case .qLLDBSaveCore:
      try GDBSaveCorePacket.handle(payload, session: self, writer: &writer)
    case .qRcmd:
      try GDBRemoteCommandPacket.handle(payload, writer: &writer)
      return .close
    case .qSearch:
      try GDBMemoryPacket.search(payload, debuggee: debuggee, state: state,
                                 writer: &writer)
    case .qShlibInfoAddr:
      try GDBSharedLibraryPacket.handle(payload, session: self, state: state,
                                        writer: &writer)
    case .qThreadExtraInfo:
      try GDBThreadExtraInfoPacket.handle(payload, session: &self,
                                          state: &state, writer: &writer)
    case .qSpeedTest:
      try GDBSpeedPacket.handle(payload, writer: &writer)
    case .qSupportsDetachAndStayStopped:
      try GDBDetachSupportPacket.handle(payload, writer: &writer)
    case .qThreadStopInfo:
      return try GDBThreadStopInfoPacket.handle(payload, session: &self,
                                                state: &state, writer: &writer)
    case .qWatchpointSupportInfo:
      try GDBWatchpointPacket.handle(payload, session: &self, state: state,
                                     writer: &writer)
    case .transfer(let object):
      return try GDBTransferPacket.handle(object, payload: payload,
                                          session: &self, state: &state,
                                          writer: &writer)
    case .qfThreadInfo:
      try GDBThreadEnumerationPacket.first(debuggee: debuggee, state: &state,
                                           writer: &writer)
    case .qsThreadInfo:
      try GDBThreadEnumerationPacket.next(debuggee: debuggee, state: &state,
                                          writer: &writer)
    case .step:
      return try GDBExecution.step(payload, session: &self, state: &state,
                                   writer: &writer)
    case .attach:
      return try GDBExecution.attach(payload, session: &self, state: &state,
                                     writer: &writer)
    case .vAttachName:
      try GDBAttachNamePacket.handle(payload, session: &self, state: &state,
                                     writer: &writer)
      return .none
    case .vAttachOrWait:
      try GDBAttachOrWaitPacket.handle(payload, session: &self, state: &state,
                                       writer: &writer)
      return .none
    case .vAttachWait:
      try GDBAttachWaitPacket.handle(payload, session: &self, state: &state,
                                     writer: &writer)
      return .none
    case .vCont:
      return try GDBExecution.vcont(payload, session: &self, state: &state,
                                    writer: &writer)
    case .vCtrlC:
      try GDBNonStopPacket.interrupt(payload, session: &self, state: &state,
                                     writer: &writer)
    case .vKill:
      try GDBKillProcessPacket.handle(payload, session: &self, state: &state,
                                      writer: &writer)
      return .none
    case .vStdio:
      try GDBNonStopPacket.stdio(payload, state: &state, writer: &writer)
    case .vStopped:
      try GDBNonStopPacket.status(payload, state: &state, writer: &writer)
    case .run:
      try GDBRunPacket.handle(payload, session: &self, state: &state,
                              writer: &writer)
      return .none
    case .z:
      try GDBBreakpointPacket.remove(payload, session: &self, state: &state,
                                     writer: &writer)
    case .tls:
      try GDBAddressPacket.tls(payload, session: &self, state: &state,
                               writer: &writer)
    case .tib:
      try GDBAddressPacket.tib(payload, session: &self, writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }
}
