// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(x86_64)
internal import WinSDK

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
      let module = withUTF16CString("ntdll.dll") { GetModuleHandleW($0) }
      guard let module, let function = GetProcAddress(module, "NtContinue"),
          let image = images.first(where: { image in
            withUTF16CString(image.value, { GetModuleHandleW($0) }) == module
          }) else {
        throw .breakpoint
      }
      // Match the full path through the loader, then relocate the native
      // system image's export against its independently located target base.
      let symbol = unsafeBitCast(function, to: UInt.self)
      let offset = symbol - UInt(bitPattern: module)
      restoration = Debuggee.Address(rawValue: image.key + UInt64(offset))
    }
    guard let restoration else {
      return nil
    }
    return BreakpointSite(address: restoration, size: 1, kind: .software)
  }

  internal func preserve(_ context: borrowing CONTEXT) throws(Debuggee.Error) {
    let address = UnsafeMutableRawPointer(bitPattern: UInt(context.Rcx))
    guard let handle, let address else {
      throw .memory
    }
    var flags: DWORD = 0
    let offset = MemoryLayout<CONTEXT>.offset(of: \CONTEXT.ContextFlags)!
    guard ReadProcessMemory(handle, address + offset, &flags,
                             SIZE_T(MemoryLayout<DWORD>.size), nil) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
    }
    guard flags & CONTEXT_DEBUG_REGISTERS == CONTEXT_DEBUG_REGISTERS else {
      return
    }
    // Debug registers belong to the debugger. Copying them here can restore
    // stale comparators if another thread stops before NtContinue consumes
    // this context and the client changes its breakpoints in the meantime.
    flags &= ~(CONTEXT_DEBUG_REGISTERS ^ CONTEXT_AMD64)
    guard WriteProcessMemory(handle, address + offset, &flags,
                              SIZE_T(MemoryLayout<DWORD>.size), nil) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .memory)
    }
  }
}
#endif
