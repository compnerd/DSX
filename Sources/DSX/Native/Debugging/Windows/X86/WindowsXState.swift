// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

internal struct WindowsXState: ~Copyable {
  private let storage: UnsafeMutableRawPointer
  internal let context: UnsafeMutablePointer<CONTEXT>
  internal let vector: UnsafeMutablePointer<M128A>?

  internal static var available: Bool {
    GetEnabledXStateFeatures() & XSTATE_MASK_AVX > 0
  }

  internal init(_ handle: HANDLE) throws(Debuggee.Error) {
    let available = WindowsXState.available
    let flags = CONTEXT_ALL | (available ? CONTEXT_XSTATE : 0)
    var size: DWORD = 0
    _ = InitializeContext(nil, flags, nil, &size)
    guard GetLastError() == ERROR_INSUFFICIENT_BUFFER else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .register)
    }
    let storage =
        UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 64)
    var context: UnsafeMutablePointer<CONTEXT>?
    let initialized: (UnsafeMutablePointer<CONTEXT>,
                      UnsafeMutablePointer<M128A>?)
    do throws(Debuggee.Error) {
      guard InitializeContext(storage, flags, &context, &size),
          let context else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .register)
      }
      if available {
        guard SetXStateFeaturesMask(context, XSTATE_MASK_AVX) else {
          throw Debuggee.Error(windows: GetLastError(), invalid: .register)
        }
      }
      guard GetThreadContext(handle, context) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
      }
      var vector: UnsafeMutablePointer<M128A>?
      if available {
        var length: DWORD = 0
        var mask: DWORD64 = 0
        guard GetXStateFeaturesMask(context, &mask),
            let feature = LocateXStateFeature(context, XSTATE_AVX, &length),
            length >= 16 * RegisterConfiguration.vectors else {
          throw .register
        }
        vector = feature.assumingMemoryBound(to: M128A.self)
        if mask & XSTATE_MASK_AVX == 0 {
          // An absent state bit means architectural zero, not buffer contents.
          feature.initializeMemory(as: UInt8.self, repeating: 0,
                                   count: Int(length))
        }
        // Only AVX is requested on commit; leave other XSTATE components alone.
        guard SetXStateFeaturesMask(context, XSTATE_MASK_AVX) else {
          throw Debuggee.Error(windows: GetLastError(), invalid: .register)
        }
      }
      initialized = (context, vector)
    } catch {
      storage.deallocate()
      throw error
    }
    self.storage = storage
    self.context = initialized.0
    self.vector = initialized.1
  }

  deinit {
    storage.deallocate()
  }
}
#endif
