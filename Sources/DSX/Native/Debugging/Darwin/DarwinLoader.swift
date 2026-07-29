// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

private typealias DyldProcess = UnsafeMutableRawPointer
private typealias DyldStatus = UnsafeMutablePointer<kern_return_t>
private typealias DyldCreate =
    @convention(c) (mach_port_t, UInt64, DyldStatus) -> DyldProcess?
private typealias DyldQuery =
    @convention(c) (DyldProcess, UnsafeMutableRawPointer) -> Void
private typealias DyldRelease = @convention(c) (DyldProcess) -> Void

private struct DyldProcessState {
  internal var timestamp: UInt64 = 0
  internal var images: UInt32 = 0
  internal var initial: UInt32 = 0
  internal var state: UInt8 = 0
}

extension ProcessIdentifier {
  internal var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      return try DSX::loader(task.handle)
    }
  }
}

private func loader(_ task: mach_port_name_t) throws(Debuggee.Error)
    -> Debuggee.Loader {
  guard let create = dlsym(kRTLDDefault, "_dyld_process_info_create"),
      let query = dlsym(kRTLDDefault, "_dyld_process_info_get_state"),
      let release = dlsym(kRTLDDefault, "_dyld_process_info_release") else {
    throw .unsupported
  }
  let creation = unsafeBitCast(create, to: DyldCreate.self)
  let request = unsafeBitCast(query, to: DyldQuery.self)
  let disposal = unsafeBitCast(release, to: DyldRelease.self)
  var status = kern_return_t(KERN_FAILURE)
  let result = creation(task, 0, &status)
  guard status == KERN_SUCCESS, let result else {
    if let result {
      disposal(result)
    }
    throw DarwinError.debuggee(status, invalid: .process)
  }
  defer {
    disposal(result)
  }
  var state = DyldProcessState()
  withUnsafeMutablePointer(to: &state) { state in
    request(result, UnsafeMutableRawPointer(state))
  }
  return Debuggee.Loader(value: state.state)
}
#endif
