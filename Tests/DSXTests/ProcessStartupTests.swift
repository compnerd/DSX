// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Windows)
internal import WinSDK
#endif

@Suite
internal struct ProcessStartupTests {
  @Test(arguments: [false, true])
  internal func timeout(_ partial: Bool) throws {
#if os(Windows)
    let executable = try WindowsEnvironment["COMSPEC"]
    let prefix = partial ? "<nul set /p =123 & " : ""
    let arguments = ["/d", "/c", prefix + "ping -n 4 127.0.0.1 >nul"]
    let command = String(command: executable, arguments: arguments.span)
    let child = try WindowsProcess(executable, command: command, directory: nil,
                                   errors: false, flags: CREATE_NO_WINDOW)
#else
    let command = partial ? "printf '123'; exec sleep 3" : "exec sleep 3"
    let arguments = ["-c", command]
    let child =
        try UnixProcess(Host.shell, arguments: arguments.span, errors: false)
#endif
    defer { try? child.terminate() }
    let start = try Host.time
    #expect(throws: Debuggee.Error.state) {
      try child.notification(timeout: 200)
    }
    #expect(try Host.time - start < 2_000)
  }
}
