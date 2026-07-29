// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

extension Host {
  private static var cpu: UInt64 {
    var value: cpu_type_t = 0
    var size = MemoryLayout<cpu_type_t>.size
    if sysctlbyname("hw.cputype", &value, &size, nil, 0) == 0, value != 0 {
      return UInt64(UInt32(bitPattern: value))
    }
#if arch(arm64)
    return UInt64(UInt32(bitPattern: CPU_TYPE_ARM64))
#elseif arch(x86_64)
    return UInt64(UInt32(bitPattern: CPU_TYPE_X86_64))
#endif
  }

  private static var subtype: UInt64 {
    var value: cpu_subtype_t = 0
    var size = MemoryLayout<cpu_subtype_t>.size
    if sysctlbyname("hw.cpusubtype", &value, &size, nil, 0) == 0 {
      return UInt64(UInt32(bitPattern: value))
    }
#if arch(arm64)
    return UInt64(UInt32(bitPattern: CPU_SUBTYPE_ARM64_ALL))
#elseif arch(x86_64)
    return UInt64(UInt32(bitPattern: CPU_SUBTYPE_X86_64_ALL))
#endif
  }

  private static var addressing: UInt64? {
    var bits: UInt32 = 0
    var size = MemoryLayout<UInt32>.size
    guard sysctlbyname("machdep.virtual_address_size", &bits, &size, nil,
                       0) == 0, bits > 0 else {
      return nil
    }
    return UInt64(bits)
  }

  internal static var system: StaticString {
    "darwin"
  }

  internal static var version: String? {
    var size = 0
    guard sysctlbyname("kern.osproductversion", nil, &size, nil, 0) == 0,
        size > 1 else {
      return nil
    }
    return withUnsafeTemporaryAllocation(of: CChar.self,
                                         capacity: size) { buffer in
      guard let address = buffer.baseAddress,
          sysctlbyname("kern.osproductversion", address, &size, nil,
                       0) == 0 else {
        return nil
      }
      return String(cString: address)
    }
  }

  internal static var metadata: HostMetadata {
    HostMetadata(cpu: cpu, subtype: subtype, vendor: "apple", system: "macosx",
                 addressing: addressing)
  }
}
#endif
