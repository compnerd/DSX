// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBJSONTests {
  @Test(arguments: [#"{ "fetch_all_solibs": true }"#,
                    "{\n\"fetch_all_solibs\" : true\n}",
  ])
  internal func libraries(_ value: String) throws(GDBHandlerError) {
    let bytes = Array(value.utf8)
    let request = try GDBLibrariesRequest(bytes.span)
    #expect(request.all)
  }

  @Test(arguments: ["[]", " \t[\r\n ] \r\n"])
  internal func empty(_ value: String) throws(GDBHandlerError) {
    let bytes = Array(value.utf8)
    var reader = try GDBModulesReader(bytes.span)
    #expect(try reader.next() == nil)
  }

  @Test
  internal func modules() throws(GDBHandlerError) {
    let value = """
        [ { "file" : "a", "triple" : "x86_64" },
          { "file" : "b", "triple" : "arm64" } ]
        """
    let bytes = Array(value.utf8)
    var reader = try GDBModulesReader(bytes.span)
    let first = try reader.next()
    #expect(first?.path == "a")
    #expect(first?.triple == "x86_64")
    let second = try reader.next()
    #expect(second?.path == "b")
    #expect(second?.triple == "arm64")
    #expect(try reader.next() == nil)
  }

  @Test
  internal func escaping() throws(GDBHandlerError) {
    let bytes = Array(#""a\n\t\\\"b""#.utf8)
    var reader = GDBPacketReader(bytes.span)
    let range = try reader.quoted()
    #expect(try reader.json(range) == "a\n\t\\\"b")
    let empty = reader.empty
    #expect(empty)
  }

  @Test(arguments: [(#"caf\u00e9.so"#, "café.so"),
                    (#"\uD83E\uDDF5"#, "🧵"),
                    (#"\u0001\u007f"#, "\u{1}\u{7f}"),
                    (#"\u0800\uffff"#, "\u{800}\u{ffff}"),
                    (#"a\/b\\c"#, "a/b\\c"),
  ])
  internal func unicode(_ escaped: String, _ expected: String)
      throws(GDBHandlerError) {
    let bytes = Array(("\"" + escaped + "\"").utf8)
    var reader = GDBPacketReader(bytes.span)
    let range = try reader.quoted()
    #expect(try reader.json(range) == expected)
    let empty = reader.empty
    #expect(empty)
  }

  @Test(arguments: [#"\u"#, #"\u123"#, #"\u12xz"#, #"\ud800"#,
                    #"\udc00"#, #"\ud800\u1234"#, #"\ud800\ud800"#,
  ])
  internal func escapes(_ value: String) {
    let bytes = Array(("\"" + value + "\"").utf8)
    #expect(throws: GDBHandlerError.malformed) {
      var reader = GDBPacketReader(bytes.span)
      _ = try reader.quoted()
    }
  }

  @Test(arguments: ["[", "[{}", "[{},]", "[]x",
                    #"[{"file":"\x","triple":"a"}]"#,
                    #"[{"file":"a\u0000b","triple":"a"}]"#,
                    #"[{"file":"a","triple":"a\u0000b"}]"#,
                    #"[{"file":"a","triple":"a",}]"#,
  ])
  internal func malformed(_ value: String) {
    let bytes = Array(value.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      var reader = try GDBModulesReader(bytes.span)
      while let _ = try reader.next() {
      }
    }
  }
}
