// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !((os(Android) || os(Linux)) && arch(arm64))
internal struct RegisterConfiguration: Sendable {
#if arch(i386) || arch(x86_64)
#if os(Windows)
  internal var vector: Bool { WindowsXState.available }
#else
  internal var vector = false
#endif
  internal static var vectors: Int {
#if arch(i386)
    8
#else
    16
#endif
  }
#endif
  internal func feature(_ identifier: RegisterFeatureIdentifier)
      -> RegisterFeatureIdentifier {
    identifier
  }

  internal func count(_ count: Int) -> Int {
#if arch(i386)
    count - (vector ? 0 : 8)
#elseif arch(x86_64)
    count - (vector ? 0 : 16)
#else
    count
#endif
  }

  internal func count(_ type: RegisterTypeRecord) -> Int? { type.count }

  internal func index(_ index: Int, count: Int) -> Int { index }

#if os(Windows) && arch(x86_64)
  @inline(never)
#endif
  internal func layout(_ storage: RegisterStorage) -> RegisterStorage? {
#if arch(i386) || arch(x86_64)
    if storage.feature.rawValue == 3 {
      guard vector else {
        return nil
      }
#if arch(x86_64) && !(os(Android) || os(Linux))
      return storage.layout(bits: Int(storage.bits),
                            offset: Int(storage.offset) - 16, bias: 2)
#endif
    }
#endif
    return storage
  }
}
#endif

extension RegisterDescription {
  /// Fixed layouts do not need a selected thread or a native register read.
  internal init<E: Error>(_ resolve: () throws(E) -> NativeRegisterState)
      throws(E) {
    self.init()
#if (os(Android) || os(Linux)) && (arch(arm64) || arch(i386) || arch(x86_64))
    configuration = try resolve().configuration
#elseif os(anyAppleOS) && arch(x86_64)
    configuration = try resolve().configuration
#endif
  }
}

#if !((os(Android) || os(Linux)) && arch(arm64))
#if !((arch(i386) || arch(x86_64)) && (os(Linux) || os(Android)))
#if !(os(anyAppleOS) && arch(x86_64))
extension NativeRegisterState {
  internal var configuration: RegisterConfiguration {
    RegisterConfiguration()
  }
}
#endif
#endif
#endif
