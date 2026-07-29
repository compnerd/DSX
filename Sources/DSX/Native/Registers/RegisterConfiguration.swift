// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !((os(Android) || os(Linux)) && arch(arm64))
internal struct RegisterConfiguration: Sendable {
  internal func feature(_ identifier: RegisterFeatureIdentifier)
      -> RegisterFeatureIdentifier {
    identifier
  }

  internal func count(_ count: Int) -> Int { count }

  internal func count(_ type: RegisterTypeRecord) -> Int? { type.count }

  internal func index(_ index: Int, count: Int) -> Int { index }

  internal func layout(_ storage: RegisterStorage) -> RegisterStorage? {
    storage
  }
}
#endif

extension RegisterDescription {
  /// Fixed layouts do not need a selected thread or a native register read.
  internal init<E: Error>(_ resolve: () throws(E) -> NativeRegisterState)
      throws(E) {
    self.init()
#if (os(Android) || os(Linux)) && arch(arm64)
    configuration = try resolve().configuration
#endif
  }
}

#if !((os(Android) || os(Linux)) && arch(arm64))
extension NativeRegisterState {
  internal var configuration: RegisterConfiguration {
    RegisterConfiguration()
  }
}
#endif
