// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

package struct ArgumentOption {
  package let name: Substring
  package let value: Substring?
}

package struct Arguments {
  private var values: Array<String>
  private var index: Int

  package init(_ values: consuming Array<String>) {
    self.values = values
    index = values.startIndex
  }

  package mutating func next() -> String? {
    guard index < values.endIndex else {
      return nil
    }
    defer { index += 1 }
    return values[index]
  }

  package func option(_ argument: String) -> ArgumentOption {
    if argument.hasPrefix("--") {
      guard let separator = argument.firstIndex(of: "=") else {
        return ArgumentOption(name: argument[...], value: nil)
      }
      let name = argument[..<separator]
      let start = argument.index(after: separator)
      return ArgumentOption(name: name, value: argument[start...])
    }
    if argument.hasPrefix("-"), argument.count > 2 {
      let end = argument.index(argument.startIndex, offsetBy: 2)
      let value = argument[end...]
      return ArgumentOption(name: argument[..<end],
                            value: value.first == "=" ? value.dropFirst()
                                                      : value)
    }
    return ArgumentOption(name: argument[...], value: nil)
  }

  package mutating func value(_ option: borrowing ArgumentOption)
      throws(ArgumentError) -> String {
    if let value = option.value {
      return String(value)
    }
    guard let value = next() else {
      throw .failure("Missing value for '\(option.name)'")
    }
    return value
  }

  package func flag(_ option: borrowing ArgumentOption) throws(ArgumentError) {
    guard option.value == nil else {
      throw .failure("The option '\(option.name)' does not take a value")
    }
  }

  package consuming func remaining() -> Array<String> {
    values.removeFirst(index)
    return values
  }

  package consuming func remainder() -> Array<String> {
    values.removeFirst(index - 1)
    if let separator = values.firstIndex(of: "--") {
      values.remove(at: separator)
    }
    return values
  }
}
