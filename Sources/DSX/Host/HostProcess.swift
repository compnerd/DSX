// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct HostProcessRecord: Sendable {
  internal let information: HostProcess.Information
  internal var monitor: WaitHandle?

  internal func close() {
    monitor?.close()
  }
}

internal struct HostProcess: ~Copyable, Sendable {
  internal struct Information: Sendable {
    internal let process: ProcessIdentifier
    internal let port: UInt16
  }

  private var record: HostProcessRecord

  internal var information: Information {
    record.information
  }

  internal init(process: ProcessIdentifier, port: UInt16,
                monitor: WaitHandle? = nil) {
    let information = Information(process: process, port: port)
    record = HostProcessRecord(information: information, monitor: monitor)
  }

  deinit {
    record.close()
  }

  internal consuming func take() -> HostProcessRecord {
    let result = record
    record.monitor = nil
    return result
  }
}
