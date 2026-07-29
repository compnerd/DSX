// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Image: Sendable {
    internal enum Style: Sendable {
      case address
      case name
      case identifier
      case full

      internal var described: Bool {
        self == .identifier || self == .full
      }
    }

    internal let path: String
    internal let base: Address
    internal var sections: Array<Address>
    internal let main: Bool
    internal let system: String?
    internal let description: ImageDescription?
    internal let link: Address?
    internal let dynamic: Address?

    internal init(path: consuming String, base: Address,
                  sections: consuming Array<Address> = [], main: Bool = false,
                  system: consuming String? = nil,
                  description: consuming ImageDescription? = nil,
                  link: Address? = nil, dynamic: Address? = nil) {
      self.path = consume path
      self.base = base
      self.sections = consume sections
      self.main = main
      self.system = consume system
      self.description = consume description
      self.link = link
      self.dynamic = dynamic
    }
  }

  internal struct ImageDescription: Sendable {
    internal let header: ImageHeader
    internal let segments: Array<ImageSegment>
    internal let identifier: String
  }

  internal struct SharedCache: Sendable {
    internal let base: Address
    internal let identifier: String
    internal let absent: Bool
    internal let isolated: Bool
    internal let path: String?
  }

  internal struct ImageHeader: Sendable {
    internal let magic: UInt32
    internal let cpu: UInt32
    internal let subtype: UInt32
    internal let file: UInt32
    internal let flags: UInt32
    internal let size: UInt32
  }

  internal struct ImageSegment: Sendable {
    internal let name: String
    internal let address: UInt64
    internal let size: UInt64
    internal let offset: UInt64
    internal let bytes: UInt64
    internal let protection: UInt32
  }

  internal enum ImageOffsets: Sendable {
    case sections(text: UInt64, data: UInt64)
    case segments(text: Address, data: Address?)
  }

  internal struct Module: Sendable {
    internal enum Identity: Sendable {
      case digest(String)
      case unique(String)

      internal var value: String {
        switch self {
        case .digest(let value), .unique(let value): value
        }
      }
    }

    internal let path: String
    internal let identity: Identity?
    internal let architecture: String?
    internal let base: Address
    internal let size: UInt64

    internal init(path: consuming String, identity: consuming Identity? = nil,
                  architecture: consuming String? = nil, base: Address,
                  size: UInt64) {
      self.path = consume path
      self.identity = consume identity
      self.architecture = consume architecture
      self.base = base
      self.size = size
    }
  }
}
