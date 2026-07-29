// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct UnixHostTests {
  @Test
  internal func accounts() async throws {
    let user = UInt64(getuid())
    let group = UInt64(getgid())
    let name = try Host.user(user)
    let membership = try Host.group(group)
    try await withThrowingTaskGroup(of: Void.self) { tasks in
      for _ in 0 ..< 32 {
        tasks.addTask {
          let account = try Host.user(user)
          let affiliation = try Host.group(group)
          #expect(account == name)
          #expect(affiliation == membership)
        }
      }
      try await tasks.waitForAll()
    }
  }
}
#endif
