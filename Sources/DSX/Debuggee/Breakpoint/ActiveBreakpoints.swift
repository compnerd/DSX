// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension ActiveBreakpoints {
  internal mutating func update(_ site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?,
                                enabled: Bool) {
    if enabled {
      return append(ActiveBreakpoint(site: site, thread: thread))
    }
    for index in indices {
      let record = self[index]
      if record.site == site, record.thread == thread {
        remove(at: index)
        break
      }
    }
  }

  internal func nearest(_ address: UInt64,
                        thread: ProcessThreadIdentifier) -> Index? {
    var selected: Index?
    var distance = UInt64.max
    var ambiguous = false
    for index in indices {
      let record = self[index]
      guard case .watchpoint = record.site.kind,
          record.thread == nil || record.thread == thread else {
        continue
      }
      let candidate = record.site.distance(address)
      switch candidate {
      case ..<distance:
        selected = index
        distance = candidate
        ambiguous = false
      case distance:
        if let selected, self[selected].site != record.site {
          ambiguous = true
        }
      default:
        break
      }
    }
    if ambiguous {
      return nil
    }
    return selected
  }
}

extension BreakpointSite {
  internal func distance(_ address: UInt64) -> UInt64 {
    let start = self.address.rawValue
    guard size > 0 else {
      return UInt64.max
    }
    let (end, overflow) = start.addingReportingOverflow(UInt64(size))
    if address < start {
      return start - address
    }
    if overflow || address < end {
      return 0
    }
    return address - end + 1
  }
}
