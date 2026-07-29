// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
internal import Testing
@testable internal import DSX

@Suite
internal struct UnixCommandTests {
  @Test
  internal func arguments() throws {
    let arguments = ["", "two words", "λ"]
    let command = try UnixCommand(arguments.span,
                                  env: Span<Debuggee.Environment>(),
                                  prefix: "program")
    let result = try command.spawn { argv, envp throws(Debuggee.Error) in
      #expect(String(cString: argv[0]!) == "program")
      #expect(String(cString: argv[1]!) == "")
      #expect(String(cString: argv[2]!) == "two words")
      #expect(String(cString: argv[3]!) == "λ")
      #expect(argv[4] == nil)
      #expect(envp == variables())
      return 42
    }
    #expect(result == 42)
  }

  @Test
  internal func invalid() throws {
    let arguments = ["embedded\0nul"]
    #expect(throws: Debuggee.Error.process) {
      _ = try UnixCommand(arguments.span, env: Span<Debuggee.Environment>())
    }
  }

  @Test
  internal func environment() throws {
    let changes = [Debuggee.Environment(name: "DSX_COMMAND_TEST", value: "λ")]
    let command = try UnixCommand(Span<String>(), env: changes.span)
    _ = try command.spawn { argv, envp throws(Debuggee.Error) in
      #expect(argv[0] == nil)
      var cursor = envp
      var found = false
      while let entry = cursor.pointee {
        let value = String(cString: entry)
        #expect(value.isEmpty == false)
        if value == "DSX_COMMAND_TEST=λ" {
          found = true
        }
        cursor += 1
      }
      #expect(found)
      return 0
    }
  }
}
#endif
