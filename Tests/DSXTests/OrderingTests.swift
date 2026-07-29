// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct OrderingTests {
  @Test
  internal func integers() {
    var values = [3, 1, 4, 1, 5, 9, 2, 6]
    values.order(by: <)
    #expect(values == [1, 1, 2, 3, 4, 5, 6, 9])

    var empty = Array<Int>()
    empty.order(by: <)
    #expect(empty.isEmpty)

    var singleton = [1]
    singleton.order(by: <)
    #expect(singleton == [1])
  }

  @Test
  internal func strings() {
    var values = ["gamma", "alpha", "beta"]
    values.order(by: <)
    #expect(values == ["alpha", "beta", "gamma"])
  }
}
