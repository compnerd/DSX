// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension String {
  internal func matches(architecture requested: String) -> Bool {
    if requested == self {
      return true
    }
    let canonical = switch requested {
    case "amd64": "x86_64"
    case "aarch64": "arm64"
    case "arm64": "aarch64"
    case "i486", "i586", "i686", "x86": "i386"
    default: requested.hasPrefix("armv") ? "arm" : requested
    }
    return self == canonical
  }
}
