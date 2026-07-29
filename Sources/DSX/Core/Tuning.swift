// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum Tuning {
  internal enum Packet {
    internal static let capacity = 131_072
  }

  internal enum Output {
    internal static let capacity = 1024
  }

  internal enum Transfer {
    internal static let capacity = 16_384
  }

  internal enum Process {
    internal static let polling = Duration.milliseconds(10)
    internal static let capacity = 1024
    internal static let burst = 16
  }

  internal enum Debuggee {
    internal static let backoff = Duration.milliseconds(1)
    internal static let polling = Duration.milliseconds(10)
  }
}
