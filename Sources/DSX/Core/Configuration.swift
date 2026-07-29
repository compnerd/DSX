// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum Configuration {
  internal enum Process {
    internal static let Interval: UInt64 = 10
    internal static let Capacity = 1024
    internal static let Burst = 16
  }

  internal enum Darwin {
    internal enum Task {
      internal static let Delay: UInt32 = 10_000
      internal static let Retries = 9
    }
  }

  internal typealias ResumeActionStorage<Element> = InlineArray<64, Element>
  internal typealias ThreadStorage<Element> = InlineArray<64, Element>

  internal static let AttachWaitInterval: Int32 = 100
  internal static let FileTransferCapacity = 16_384
  internal static let OutputCapacity = 1024
  internal static let PacketCapacity = 131_072
  internal static let PacketLimit = 4_194_304
  internal static let PlatformPacketCapacity = PacketCapacity
  internal static let ResumeActionCapacity = 64
  internal static let DebuggeePollInterval: Int32 = 10
  internal static let ThreadCapacity = 64
}
