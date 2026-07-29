// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Array {
  internal mutating func order(by before: (borrowing Element,
                                           borrowing Element) -> Bool) {
    guard count > 1 else {
      return
    }
    withUnsafeMutableBufferPointer { values in
      var root = values.count / 2
      while root > 0 {
        root -= 1
        values.sift(root: root, end: values.count, by: before)
      }
      var end = values.count
      while end > 1 {
        end -= 1
        values.swapAt(0, end)
        values.sift(root: 0, end: end, by: before)
      }
    }
  }
}

private typealias Order<Element> =
    (borrowing Element, borrowing Element) -> Bool

extension UnsafeMutableBufferPointer {
  @inline(never)
  fileprivate func sift(root: Int, end: Int, by before: Order<Element>) {
    var root = root
    while root * 2 + 1 < end {
      let left = root * 2 + 1
      let right = left + 1
      var next = left
      if right < end, before(self[left], self[right]) {
        next = right
      }
      guard before(self[root], self[next]) else {
        return
      }
      swapAt(root, next)
      root = next
    }
  }
}
