// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

private typealias DyldProcess = UnsafeMutableRawPointer
private typealias DyldStatus = UnsafeMutablePointer<kern_return_t>
private typealias DyldState = UnsafeMutablePointer<dyld_process_state_info>
private typealias DyldCreate =
    @convention(c) (mach_port_t, UInt64, DyldStatus) -> DyldProcess?
private typealias DyldQuery = @convention(c) (DyldProcess, DyldState) -> Void
private typealias DyldRelease = @convention(c) (DyldProcess) -> Void

extension ProcessIdentifier {
  internal var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      let task = try DarwinTask(self)
      return try task.loader
    }
  }
}

extension DarwinTask {
  fileprivate var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      guard let create = dlsym(RTLD_DEFAULT, "_dyld_process_info_create"),
          let query = dlsym(RTLD_DEFAULT, "_dyld_process_info_get_state"),
          let release = dlsym(RTLD_DEFAULT, "_dyld_process_info_release") else {
        throw .unsupported
      }
      let creation = unsafeBitCast(create, to: DyldCreate.self)
      let request = unsafeBitCast(query, to: DyldQuery.self)
      let disposal = unsafeBitCast(release, to: DyldRelease.self)
      var status = kern_return_t(KERN_FAILURE)
      let result = creation(handle, 0, &status)
      guard status == KERN_SUCCESS, let result else {
        if let result {
          disposal(result)
        }
        throw Debuggee.Error(mach: status, invalid: .process)
      }
      defer {
        disposal(result)
      }
      var state = dyld_process_state_info()
      request(result, &state)
      return Debuggee.Loader(value: state.dyldState)
    }
  }
}
#endif
