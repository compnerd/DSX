// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK
internal import DSXShims

private typealias NtContinueBinding = LazyBinding<DSXShims.NtContinue_t>

extension NtContinueBinding {
  fileprivate func callAsFunction(_ context: PCONTEXT?, _ alert: BOOLEAN)
      -> NTSTATUS {
    dsx_NtContinue(function, context, alert)
  }
}

private let NtContinue: NtContinueBinding? = {
  guard let module =
      withUTF16CString("ntdll.dll", { GetModuleHandleW($0) }) else {
    return nil
  }
  return NtContinueBinding(module: module, "NtContinue")
}()

extension WindowsDebugControl {
  internal mutating func checkpoint(_ process: ProcessIdentifier)
      throws(Debuggee.Error) -> BreakpointSite? {
    guard self.process == process else {
      throw .process
    }
    if restoration == nil {
      guard !breakpoints.isEmpty else {
        return nil
      }
      guard let NtContinue,
          let image = images.first(where: { image in
            let module = withUTF16CString(image.value) { GetModuleHandleW($0) }
            return UInt(bitPattern: module) == NtContinue.module
          }) else {
        throw .breakpoint
      }
      // Match the full path through the loader, then relocate the native
      // system image's export against its independently located target base.
      let offset = NtContinue.address - NtContinue.module
      restoration = Debuggee.Address(rawValue: image.key + UInt64(offset))
    }
    guard let restoration else {
      return nil
    }
    return BreakpointSite(address: restoration, size: 1, kind: .software)
  }

  internal func preserve(_ context: borrowing CONTEXT) throws(Debuggee.Error) {
#if arch(i386)
    // NtContinue's first argument follows the return address on x86.
    let stack = UnsafeMutableRawPointer(bitPattern: UInt(context.Esp) &+ 4)
    guard let handle, let stack else {
      throw .memory
    }
    var pointer: DWORD = 0
    guard ReadProcessMemory(handle, stack, &pointer,
                            SIZE_T(MemoryLayout<DWORD>.size), nil) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
    }
    let address = UnsafeMutableRawPointer(bitPattern: UInt(pointer))
    guard let address else {
      throw .memory
    }
#elseif arch(x86_64)
    let address = UnsafeMutableRawPointer(bitPattern: UInt(context.Rcx))
    guard let handle, let address else {
      throw .memory
    }
#else
    let address = UnsafeMutableRawPointer(bitPattern: UInt(context.X0))
    guard let handle, let address else {
      throw .memory
    }
#endif
    var flags: DWORD = 0
    let offset = MemoryLayout<CONTEXT>.offset(of: \CONTEXT.ContextFlags)!
    guard ReadProcessMemory(handle, address + offset, &flags,
                            SIZE_T(MemoryLayout<DWORD>.size), nil) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
    }
#if arch(arm64)
    if flags & CONTEXT_CONTROL == CONTEXT_CONTROL,
        context.Cpsr & SPSR.SS == SPSR.SS {
      // NtContinue begins with SVC on ARM64. Its replacement context must
      // retain the debugger's step, or stepping that instruction can run
      // indefinitely while the remaining threads are suspended.
      let offset = MemoryLayout<CONTEXT>.offset(of: \CONTEXT.Cpsr)!
      var status: DWORD = 0
      guard ReadProcessMemory(handle, address + offset, &status,
                              SIZE_T(MemoryLayout<DWORD>.size), nil) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
      }
      status |= SPSR.SS
      guard WriteProcessMemory(handle, address + offset, &status,
                               SIZE_T(MemoryLayout<DWORD>.size), nil) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
      }
    }
#endif
    guard flags & CONTEXT_DEBUG_REGISTERS == CONTEXT_DEBUG_REGISTERS else {
      return
    }
    // Debug registers belong to the debugger. Copying them here can restore
    // stale comparators if another thread stops before NtContinue consumes
    // this context and the client changes its breakpoints in the meantime.
#if arch(i386)
    flags &= ~(CONTEXT_DEBUG_REGISTERS ^ CONTEXT_i386)
#elseif arch(x86_64)
    flags &= ~(CONTEXT_DEBUG_REGISTERS ^ CONTEXT_AMD64)
#else
    flags &= ~(CONTEXT_DEBUG_REGISTERS ^ CONTEXT_ARM64)
#endif
    guard WriteProcessMemory(handle, address + offset, &flags,
                             SIZE_T(MemoryLayout<DWORD>.size), nil) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
    }
  }
}
#endif
