// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct MD5ChecksumTests {
  @Test(arguments: [
    (0, "d41d8cd98f00b204e9800998ecf8427e"),
    (1, "93b885adfe0da089cdf634904fd59f71"),
    (55, "6912ee65fff2d9f9ce2508cddf8bcda0"),
    (56, "51fdd1acda72405dfdfa03fcb85896d7"),
    (63, "48a6295221902e8e0938f773a7185e72"),
    (64, "b2d3f56bc197fd985d5965079b5e7148"),
    (65, "8bd7053801c768420faf816fadba971c"),
    (127, "8402b21e7bc7906493bae0dac017f1f9"),
    (128, "37eff01866ba3f538421b30b7cbefcac"),
    (129, "46f986692847558fc38b0cece591c20f"),
    (4097, "e4df5b23488e51a7998f218196a6ef6d"),
  ])
  internal func boundaries(_ count: Int, _ expected: String) throws {
    let bytes = (0 ..< count).map { UInt8($0 % 251) }
    for chunk in [1, 7, 64, 4096] {
      var checksum = try MD5Checksum()
      try checksum.update(Span())
      for offset in stride(from: 0, to: count, by: chunk) {
        let end = min(offset + chunk, count)
        try checksum.update(bytes.span.extracting(offset ..< end))
      }
      let digest = try checksum.finish()
      let actual = (0 ..< digest.count).map {
        let value = String(digest[$0], radix: 16)
        return value.count == 1 ? "0" + value : value
      }.joined()
      #expect(actual == expected)
    }
  }
}
