// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
// Packed profile offset of VG with the two 64-bit PAC masks present.
private let kScalableOffset = 816
private let kAuthenticationSize = 16

internal struct RegisterConfiguration: Sendable {
  internal var vector = 0
  internal var authentication = false

  internal func feature(_ identifier: RegisterFeatureIdentifier)
      -> RegisterFeatureIdentifier {
    vector > 0 && identifier.rawValue == 1
        ? RegisterFeatureIdentifier(rawValue: 4) : identifier
  }

  internal func count(_ count: Int) -> Int {
    count - (authentication ? 0 : 2) - (vector > 0 ? 0 : 50)
  }

  internal func count(_ type: RegisterTypeRecord) -> Int? {
    guard let count = type.count else {
      return nil
    }
    return type.feature.rawValue == 4 ? count * vector / 16 : count
  }

  internal func index(_ index: Int, count: Int) -> Int {
    index >= count - 52 && authentication == false ? index + 2 : index
  }

  internal func layout(_ storage: RegisterStorage) -> RegisterStorage? {
    let identifier = storage.identifier.rawValue
    let granules = ARM64Register.vg.rawValue
    let vectors = ARM64Register.z0.rawValue
    let predicates = ARM64Register.p0.rawValue
    if (granules ... ARM64Register.ffr.rawValue).contains(identifier) {
      guard vector > 0 else {
        return nil
      }
      let base = kScalableOffset - (authentication ? 0 : kAuthenticationSize)
      let offset = base + 8 + 32 * vector
      let predicate = (Int(identifier) - Int(predicates)) * vector / 8
      let location = switch identifier {
      case granules: (64, base)
      case vectors ..< predicates:
        (vector * 8, base + 8 + Int(identifier - vectors) * vector)
      default:
        (vector, offset + predicate)
      }
      return storage.layout(bits: location.0, offset: location.1,
                            bias: authentication ? 0 : 2)
    }
    return switch identifier {
    case ARM64Register.data_mask.rawValue, ARM64Register.code_mask.rawValue:
      authentication ? storage : nil
    default: storage
    }
  }
}

extension LinuxRegisterState {
  internal var configuration: RegisterConfiguration {
    RegisterConfiguration(vector: scalable?.length ?? 0,
                          authentication: masks != nil)
  }
}
#endif
