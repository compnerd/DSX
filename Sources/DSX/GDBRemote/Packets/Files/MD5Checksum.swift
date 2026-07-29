// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct MD5Checksum {
  private static let kShift: InlineArray<64, UInt8> = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ]
  private static let kConstant: InlineArray<64, UInt32> = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ]

  private var state: InlineArray<4, UInt32>
  private var buffer: InlineArray<64, UInt8>
  private var buffered: Int
  private var length: UInt64

  internal init() {
    state = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476]
    buffer = InlineArray<64, UInt8> { _ in 0 }
    buffered = 0
    length = 0
  }

  internal mutating func update(_ bytes: borrowing Span<UInt8>) {
    length &+= UInt64(bytes.count)
    var index = 0
    while index < bytes.count {
      let count = min(64 - buffered, bytes.count - index)
      for offset in 0 ..< count {
        buffer[buffered + offset] = bytes[index + offset]
      }
      buffered += count
      index += count
      if buffered == 64 {
        transform()
        buffered = 0
      }
    }
  }

  internal mutating func finish() -> InlineArray<16, UInt8> {
    let bits = length &* 8
    buffer[buffered] = 0x80
    buffered += 1
    if buffered > 56 {
      for index in buffered ..< 64 {
        buffer[index] = 0
      }
      transform()
      buffered = 0
    }
    for index in buffered ..< 56 {
      buffer[index] = 0
    }
    for index in 0 ..< 8 {
      buffer[56 + index] = UInt8(truncatingIfNeeded: bits >> (index * 8))
    }
    transform()
    return InlineArray<16, UInt8> { index in
      let word = state[index / 4]
      return UInt8(truncatingIfNeeded: word >> ((index % 4) * 8))
    }
  }

  private mutating func transform() {
    let words = InlineArray<16, UInt32> { index in
      let offset = index * 4
      let first = UInt32(buffer[offset])
      let second = UInt32(buffer[offset + 1]) << 8
      let third = UInt32(buffer[offset + 2]) << 16
      let fourth = UInt32(buffer[offset + 3]) << 24
      return first | second | third | fourth
    }
    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    for index in 0 ..< 64 {
      let result: (value: UInt32, word: Int) = switch index {
      case 0 ..< 16:
        (b & c | ~b & d, index)
      case 16 ..< 32:
        (d & b | ~d & c, (5 * index + 1) % 16)
      case 32 ..< 48:
        (b ^ c ^ d, (3 * index + 5) % 16)
      default:
        (c ^ (b | ~d), 7 * index % 16)
      }
      let constant = MD5Checksum.kConstant[index]
      let sum = a &+ result.value &+ constant &+ words[result.word]
      let shift = UInt32(MD5Checksum.kShift[index])
      let rotated = sum << shift | sum >> (32 - shift)
      a = d
      d = c
      c = b
      b &+= rotated
    }
    state[0] &+= a
    state[1] &+= b
    state[2] &+= c
    state[3] &+= d
  }
}
