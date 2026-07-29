// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Environment: Equatable, Sendable {
    internal let name: String
    internal let value: String?

    internal init(name: consuming String, value: consuming String?) {
      self.name = consume name
      self.value = consume value
    }

    internal var valid: Bool {
      @inline(never)
      get {
        let name = name.utf8Span.span
        guard !name.isEmpty else {
          return false
        }
        for index in 0 ..< name.count {
          if name[index] == 0 || name[index] == 61 {
            return false
          }
        }
        if let value {
          let bytes = value.utf8Span.span
          for index in 0 ..< bytes.count where bytes[index] == 0 {
            return false
          }
        }
        return true
      }
    }
  }

  internal struct Launch: Sendable {
    internal var executable: String?
    internal var arguments: Array<String>
    internal var environment: Array<Environment>
    internal var working: String?
    internal var input: String?
    internal var output: String?
    internal var error: String?
    internal var aslr: Bool
    internal var detach: Bool
    internal var terminal: TerminalSize?

    internal init(executable: consuming String? = nil,
                  arguments: consuming Array<String> = [],
                  environment: consuming Array<Environment> = [],
                  working: consuming String? = nil,
                  input: consuming String? = nil,
                  output: consuming String? = nil,
                  error: consuming String? = nil, aslr: Bool = true,
                  detach: Bool = false, terminal: TerminalSize? = nil) {
      self.executable = consume executable
      self.arguments = consume arguments
      self.environment = consume environment
      self.working = consume working
      self.input = consume input
      self.output = consume output
      self.error = consume error
      self.aslr = aslr
      self.detach = detach
      self.terminal = terminal
    }
  }

  internal struct TerminalSize: Equatable, Sendable {
    internal let columns: UInt16
    internal let rows: UInt16

    internal init(columns: UInt16, rows: UInt16) {
      self.columns = columns
      self.rows = rows
    }
  }
}
