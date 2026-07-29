// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(i386) || arch(x86_64)
internal struct X86BreakpointControl: Sendable {
#if arch(i386)
  internal typealias Word = UInt
#else
  internal typealias Word = UInt64
#endif

  internal let control: Word

  private static let kExecute: Word = 0
  private static let kWrite: Word = 1
  private static let kReadWrite: Word = 3
  private static let kLength1: Word = 0
  private static let kLength2: Word = 1
  private static let kLength4: Word = 3
#if arch(x86_64)
  private static let kLength8: Word = 2
#endif

  internal init(_ site: borrowing BreakpointSite) throws(Debuggee.Error) {
    let access = try X86BreakpointControl.access(site)
    let length: Word = switch site.size {
    case 1: X86BreakpointControl.kLength1
    case 2: X86BreakpointControl.kLength2
    case 4: X86BreakpointControl.kLength4
#if arch(x86_64)
    case 8: X86BreakpointControl.kLength8
#endif
    default: throw .breakpoint
    }
    guard site.address.rawValue % UInt64(site.size) == 0 else {
      throw .breakpoint
    }
    control = access | length << 2
  }

  @_transparent
  internal static func acknowledge(_ status: Word, slot: Int) -> Word {
    status & ~(Word(1) << slot)
  }

  @_transparent
  internal static func active(_ control: Word, slot: Int) -> Bool {
    control & (Word(0x3) << (slot * 2)) != 0
  }

  @_transparent
  internal func enable(_ slot: Int, control: inout Word) {
    let shift = 16 + slot * 4
    control &= ~(Word(0x0f) << shift)
    control |= self.control << shift
    control |= Word(1) << (slot * 2)
  }

  internal func matches(_ value: Word, slot: Int) -> Bool {
    X86BreakpointControl.active(value, slot: slot) &&
        (value >> (16 + slot * 4)) & 0x0f == control
  }

  @_transparent
  internal static func disable(_ slot: Int, control: inout Word) {
    control &= ~(Word(0x3) << (slot * 2))
    control &= ~(Word(0x0f) << (16 + slot * 4))
  }

  private static func access(_ site: borrowing BreakpointSite)
      throws(Debuggee.Error) -> Word {
    switch site.kind {
    case .hardware:
      guard site.size == 1 else {
        throw .breakpoint
      }
      return kExecute
    case .watchpoint(let kind):
      return switch kind {
      case .write: kWrite
      case .read, .readwrite: kReadWrite
      case .execute: throw .breakpoint
      }
    case .software:
      throw .breakpoint
    }
  }
}
#endif
