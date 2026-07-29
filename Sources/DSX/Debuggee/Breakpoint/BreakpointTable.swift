// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct BreakpointTable: ~Copyable, Sendable {
  private typealias Entry =
      (identifier: BreakpointIdentifier, process: ProcessIdentifier,
       site: BreakpointSite, handle: DebugBreakpointHandle, references: Int,
       active: Bool)

  private var entries: Array<Entry>
  private var next: UInt64

  internal init() {
    entries = []
    next = 1
  }

  internal mutating func insert(_ process: ProcessIdentifier,
                                _ site: BreakpointSite, capacity: Int? = nil)
      throws(Debuggee.Error) -> BreakpointIdentifier {
    if let index = entries.firstIndex(where: { entry in
      entry.process == process && entry.site == site
    }) {
      entries[index].references += 1
      return entries[index].identifier
    }

    let capacity: Int? = switch (capacity, site.kind) {
    case (.some(let capacity), _): capacity
    case (.none, .watchpoint): try HardwareBreakpoint.capacity
    default: nil
    }
    if let capacity {
      var count = 0
      for entry in entries {
        guard entry.process == process else {
          continue
        }
        guard case .watchpoint = entry.site.kind else {
          continue
        }
        count += 1
      }
      guard count < capacity else {
        throw .breakpoint
      }
    }

    let handle = try DebugBreakpointHandle(process, site)
    let identifier = BreakpointIdentifier(rawValue: next)
    next &+= 1
    entries.append((identifier: identifier, process: process, site: site,
                    handle: handle, references: 1, active: false))
    return identifier
  }

  internal mutating func insert(_ process: ProcessIdentifier,
                                _ site: BreakpointSite, capacity: Int? = nil,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) -> BreakpointIdentifier {
    let identifier = try insert(process, site, capacity: capacity)
    do {
      try enable(identifier, context: &context)
      return identifier
    } catch {
      try remove(process, identifier, context: &context)
      throw error
    }
  }

  internal mutating func remove(_ process: ProcessIdentifier,
                                _ identifier: BreakpointIdentifier,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    guard let index = entries.firstIndex(where: { entry in
      entry.process == process && entry.identifier == identifier
    }) else {
      throw .breakpoint
    }
    if entries[index].references > 1 {
      entries[index].references -= 1
      return
    }
    if entries[index].active {
      try entries[index].handle.disable(process, entries[index].site,
                                        thread: nil, context: &context)
      entries[index].active = false
    }
    entries.remove(at: index)
  }

  internal mutating func enable(_ identifier: BreakpointIdentifier,
                                thread: ProcessThreadIdentifier? = nil,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    guard let index = entries.firstIndex(where: { entry in
      entry.identifier == identifier
    }) else {
      throw .breakpoint
    }
    if entries[index].active, case .none = thread {
      return
    }
    try entries[index].handle.enable(entries[index].process,
                                     entries[index].site, thread: thread,
                                     context: &context)
    if case .none = thread {
      entries[index].active = true
    }
  }

  internal mutating func disable(_ identifier: BreakpointIdentifier,
                                 thread: ProcessThreadIdentifier? = nil,
                                 context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    guard let index = entries.firstIndex(where: { entry in
      entry.identifier == identifier
    }) else {
      throw .breakpoint
    }
    if case .none = thread {
      guard entries[index].active else {
        return
      }
    }
    try entries[index].handle.disable(entries[index].process,
                                      entries[index].site, thread: thread,
                                      context: &context)
    if case .none = thread {
      entries[index].active = false
    }
  }

  internal func site(_ identifier: BreakpointIdentifier) -> BreakpointSite? {
    entries.first { entry in
      entry.identifier == identifier
    }?.site
  }

  internal func advance(_ identifier: BreakpointIdentifier) -> Bool {
    guard let site = site(identifier) else {
      return false
    }
    return switch site.kind {
    case .software: true
    case .hardware, .watchpoint: HardwareBreakpoint.advance(site.kind)
    }
  }

  internal func find(_ process: ProcessIdentifier,
                     _ breakpoint: BreakpointSite) -> BreakpointIdentifier? {
    entries.first { entry in
      entry.process == process && entry.site == breakpoint
    }?.identifier
  }

  internal mutating func hit(_ stop: Debuggee.Stop,
                             context: inout NativeDebugControl)
      throws(Debuggee.Error) -> BreakpointIdentifier? {
    for entry in entries {
      guard entry.active, entry.process == stop.thread.process else {
        continue
      }
      if try entry.handle.hit(stop, entry.site, context: &context) {
        return entry.identifier
      }
    }
    return nil
  }

  internal mutating func classify(_ event: consuming Debuggee.Event,
                                  context: inout NativeDebugControl)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard case .stopped(let stop) = event else {
      return consume event
    }
    if case .some = stop.breakpoint {
      return consume event
    }
    guard let identifier = try hit(stop, context: &context) else {
      return consume event
    }
    guard let site = site(identifier) else {
      throw .breakpoint
    }
    let reason: Debuggee.StopReason = switch site.kind {
    case .hardware, .software:
      .breakpoint
    case .watchpoint(let access):
      .watchpoint(access, site.address)
    }
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: reason,
                                  core: stop.core, fault: stop.fault,
                                  breakpoint: identifier, child: stop.child,
                                  snapshot: stop.snapshot, chance: stop.chance))
  }

  internal mutating func clear(_ process: ProcessIdentifier,
                               context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    while let index = entries.firstIndex(where: { entry in
      entry.process == process
    }) {
      if entries[index].active {
        do throws(Debuggee.Error) {
          try entries[index].handle.disable(process, entries[index].site,
                                            thread: nil, context: &context)
        } catch .process {
        }
        entries[index].active = false
      }
      entries.remove(at: index)
    }
  }

  internal mutating func forget(_ process: ProcessIdentifier) {
    entries.removeAll { entry in
      entry.process == process
    }
  }

  internal mutating func prepare(_ process: ProcessIdentifier,
                                 context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    for index in entries.indices {
      switch (entries[index].process == process, entries[index].active) {
      case (true, false):
        try entries[index].handle.enable(process, entries[index].site,
                                         thread: nil, context: &context)
        entries[index].active = true
      default:
        break
      }
    }
  }

  internal mutating func complete(_ process: ProcessIdentifier,
                                  event: borrowing Debuggee.Event,
                                  context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    switch event {
    case .executed, .exited:
      return entries.removeAll { entry in
        entry.process == process
      }
    case .forked, .image, .output, .started, .stopped, .terminated:
      break
    }
    let hit: BreakpointIdentifier? = switch event {
    case .stopped(let stop):
      stop.breakpoint
    default:
      nil
    }
    var index = entries.count
    while index > 0 {
      index -= 1
      guard entries[index].process == process else {
        continue
      }
      let expires = switch entries[index].site.lifetime {
      case .permanent:
        false
      case .oneshot:
        true
      case .untilhit:
        entries[index].identifier == hit
      }
      if entries[index].active, entries[index].identifier == hit || expires {
        do throws(Debuggee.Error) {
          try entries[index].handle.disable(process, entries[index].site,
                                            thread: nil, context: &context)
        } catch .process {
        }
        entries[index].active = false
      }
      if expires {
        entries.remove(at: index)
      }
    }
  }

  internal mutating func recover(_ process: ProcessIdentifier,
                                 context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    try disable(process, context: &context)
  }

  internal mutating func inherit(_ fork: borrowing Debuggee.Fork) {
    let count = entries.count
    for index in 0 ..< count {
      let entry = entries[index]
      guard entry.process == fork.parent.process,
          entry.site.kind == .software else {
        continue
      }
      let active = if fork.vfork {
        false
      } else {
        entry.active
      }
      let identifier = BreakpointIdentifier(rawValue: next)
      next &+= 1
      entries.append((identifier: identifier, process: fork.child.process,
                      site: entry.site, handle: entry.handle,
                      references: entry.references, active: active))
    }
  }

  private mutating func disable(_ process: ProcessIdentifier,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    for index in entries.indices {
      if entries[index].process == process && entries[index].active {
        try entries[index].handle.disable(process, entries[index].site,
                                          thread: nil, context: &context)
        entries[index].active = false
      }
    }
  }

  internal func restore(_ process: ProcessIdentifier, address: Debuggee.Address,
                        start: Int, output: inout OutputSpan<UInt8>) {
    let lower = address.rawValue
    let count = output.count - start
    let (upper, overflow) = lower.addingReportingOverflow(UInt64(count))
    for entry in entries where entry.active && entry.process == process {
      guard case .software(let handle) = entry.handle else {
        continue
      }
      let breakpoint = entry.site.address.rawValue
      for offset in 0 ..< handle.size {
        let location = breakpoint + UInt64(offset)
        guard location >= lower, overflow || location < upper else {
          continue
        }
        output[start + Int(location - lower)] = handle.original[offset]
      }
    }
  }
}
