// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

private typealias DyldProcess = UnsafeMutableRawPointer
private typealias DyldStatus = UnsafeMutablePointer<kern_return_t>
private typealias DyldState = UnsafeMutablePointer<dyld_process_state_info>
private typealias _dyld_process_info_createBinding =
    LazyBinding<@convention(c) (mach_port_t, UInt64,
                                DyldStatus) -> DyldProcess?>
private typealias _dyld_process_info_get_stateBinding =
    LazyBinding<@convention(c) (DyldProcess, DyldState) -> Void>
private typealias _dyld_process_info_releaseBinding =
    LazyBinding<@convention(c) (DyldProcess) -> Void>

extension _dyld_process_info_createBinding {
  fileprivate func callAsFunction(_ task: mach_port_t, _ timestamp: UInt64,
                                  _ status: DyldStatus) -> DyldProcess? {
    function(task, timestamp, status)
  }
}

extension _dyld_process_info_get_stateBinding {
  fileprivate func callAsFunction(_ process: DyldProcess, _ state: DyldState) {
    function(process, state)
  }
}

extension _dyld_process_info_releaseBinding {
  fileprivate func callAsFunction(_ process: DyldProcess) {
    function(process)
  }
}

// These system images remain loaded. Cache absence as well as success, and
// publish the complete group through Swift's once-only initialization.
private let kDyld: (_dyld_process_info_createBinding,
                    _dyld_process_info_get_stateBinding,
                    _dyld_process_info_releaseBinding)? = {
  guard let _dyld_process_info_create =
      _dyld_process_info_createBinding(module: RTLD_DEFAULT,
                                       "_dyld_process_info_create"),
      let _dyld_process_info_get_state =
          _dyld_process_info_get_stateBinding(module: RTLD_DEFAULT,
                                              "_dyld_process_info_get_state"),
      let _dyld_process_info_release =
          _dyld_process_info_releaseBinding(module: RTLD_DEFAULT,
                                            "_dyld_process_info_release") else {
    return nil
  }
  return (_dyld_process_info_create, _dyld_process_info_get_state,
          _dyld_process_info_release)
}()

extension ProcessIdentifier {
  internal var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      try loader(control: DarwinDebugControl())
    }
  }

  internal func loader(control: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.Loader {
    let task = try control.task(self)
    return try task.loader
  }
}

extension DarwinTask {
  fileprivate var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      guard let (_dyld_process_info_create, _dyld_process_info_get_state,
                 _dyld_process_info_release) = kDyld else {
        throw .unsupported
      }
      var status = kern_return_t(KERN_FAILURE)
      let result = _dyld_process_info_create(handle, 0, &status)
      guard status == KERN_SUCCESS, let result else {
        if let result {
          _dyld_process_info_release(result)
        }
        throw Debuggee.Error(mach: status, invalid: .process)
      }
      defer {
        _dyld_process_info_release(result)
      }
      var state = dyld_process_state_info()
      _dyld_process_info_get_state(result, &state)
      return Debuggee.Loader(value: state.dyldState)
    }
  }
}
#endif
