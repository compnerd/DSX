# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  Breakpoint/ActiveBreakpoint.swift
  Breakpoint/ActiveBreakpoints.swift
  Breakpoint/Breakpoint.swift
  Breakpoint/BreakpointTable.swift
  Breakpoint/DebugBreakpointHandle.swift
  Breakpoint/HardwareBreakpoint.swift
  Breakpoint/SoftwareBreakpoint.swift
  Debuggee+Continuation.swift
  Debuggee+Error.swift
  Debuggee+Event.swift
  Debuggee+Image.swift
  Debuggee+Launch.swift
  Debuggee+Loader.swift
  Debuggee+Memory.swift
  Debuggee+Model.swift
  Debuggee+Output.swift
  Debuggee+Process.swift
  Debuggee+Thread.swift
  Debuggee.swift
  Module/Debuggee+Module.swift
  Module/Debuggee.Module+ELF.swift
  Module/Debuggee.Module+MachO.swift
  Module/Debuggee.Module+PE.swift
  ProcessLookup.swift
  RegisterDescription.swift
  SavedRegisters.swift
  Session/DebugSession+Execution.swift
  Session/DebugSession+Lifecycle.swift
  Session/DebugSession+Memory.swift
  Session/DebugSession+Refresh.swift
  Session/DebugSession+Registers.swift
  Session/DebugSession+Search.swift
  Session/DebugSession.swift
  Session/FrameCursor.swift
  SignalSet.swift)
