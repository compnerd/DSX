// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct BreakpointTable: ~Copyable, Sendable {
  private typealias Failure = Debuggee.Error
  private typealias Entry =
      (identifier: BreakpointIdentifier, process: ProcessIdentifier,
       site: BreakpointSite, handle: DebugBreakpointHandle, active: Bool,
       uncertain: Bool)

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
      return entries[index].identifier
    }

    let installation = site.installation
    let existing = entries.first { entry in
      entry.process == process && entry.site.installation == installation
    }
    let capacity: Int? = switch (capacity, site.kind) {
    case (.some(let capacity), _): capacity
    case (.none, .watchpoint): try HardwareBreakpoint.capacity
    default: nil
    }
    if let capacity, existing == nil {
      var count = 0
      for index in entries.indices {
        let entry = entries[index]
        guard entry.process == process else {
          continue
        }
        guard case .watchpoint = entry.site.kind else {
          continue
        }
        let installation = entry.site.installation
        if entries[..<index].contains(where: { previous in
          previous.process == process &&
              previous.site.installation == installation
        }) == false {
          count += 1
        }
      }
      guard count < capacity else {
        throw .breakpoint
      }
    }

    let handle = if let existing {
      existing.handle
    } else {
      try DebugBreakpointHandle(process, site)
    }
    let identifier = BreakpointIdentifier(rawValue: next)
    next &+= 1
    entries.append((identifier: identifier, process: process, site: site,
                    handle: handle, active: false, uncertain: false))
    return identifier
  }

  internal mutating func insert(_ process: ProcessIdentifier,
                                _ site: BreakpointSite, capacity: Int? = nil,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) -> BreakpointIdentifier {
    if let identifier = find(process, site) {
      try enable(identifier, context: &context)
      return identifier
    }
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
    try configure(index, enabled: false, context: &context)
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
    try configure(index, enabled: true, thread: thread, context: &context)
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
    try configure(index, enabled: false, thread: thread, context: &context)
  }

  private mutating func configure(_ index: Int, enabled: Bool,
                                  thread: ProcessThreadIdentifier? = nil,
                                  context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    let entry = entries[index]
    let installation = entry.site.installation
    if thread == nil {
      if entry.uncertain == false, entry.active == enabled {
        return
      }
      if entries.contains(where: { candidate in
        candidate.identifier != entry.identifier &&
            candidate.active && candidate.uncertain == false &&
            candidate.process == entry.process &&
            candidate.site.installation == installation
      }) {
        entries[index].active = enabled
        entries[index].uncertain = false
        return
      }
    }
    entries[index].active = true
    entries[index].uncertain = true
    if enabled {
      try entry.handle.enable(entry.process, installation, thread: thread,
                              context: &context)
    } else {
      try entry.handle.disable(entry.process, installation, thread: thread,
                               context: &context)
    }
    entries[index].active = thread == nil ? enabled : entry.active
    entries[index].uncertain = thread == nil ? false : entry.uncertain
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
          try configure(index, enabled: false, context: &context)
        } catch .process {
        }
        entries[index].active = false
        entries[index].uncertain = false
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
      if entries[index].process == process,
          entries[index].active == false || entries[index].uncertain {
        try configure(index, enabled: true, context: &context)
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
    let stop: Debuggee.Stop? = switch event {
    case .stopped(let stop):
      stop
    default:
      nil
    }
    let hit = stop?.breakpoint.flatMap { site($0)?.installation }
    var index = entries.count
    while index > 0 {
      index -= 1
      guard entries[index].process == process else {
        continue
      }
      let stopped = entries[index].site.installation == hit
      let expires = switch entries[index].site.lifetime {
      case .permanent:
        false
      case .oneshot:
        true
      case .untilhit:
        stopped
      }
      if entries[index].active, stopped || expires {
        let thread: ProcessThreadIdentifier? = switch entries[index].site.kind {
        case .software:
          stop?.thread
        case .hardware, .watchpoint:
          nil
        }
        do throws(Debuggee.Error) {
          try configure(index, enabled: false, thread: thread,
                        context: &context)
        } catch .process {
        }
        entries[index].active = false
        entries[index].uncertain = false
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
      let active = fork.vfork ? false : entry.active
      let uncertain = fork.vfork ? false : entry.uncertain
      let identifier = BreakpointIdentifier(rawValue: next)
      next &+= 1
      entries.append((identifier: identifier, process: fork.child.process,
                      site: entry.site, handle: entry.handle, active: active,
                      uncertain: uncertain))
    }
  }

  private mutating func disable(_ process: ProcessIdentifier,
                                context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    for index in entries.indices {
      if entries[index].process == process, entries[index].active {
        try configure(index, enabled: false, context: &context)
      }
    }
  }

  internal func restore(_ process: ProcessIdentifier, address: Debuggee.Address,
                        start: Int, output: inout OutputSpan<UInt8>) {
    let count = output.count - start
    for entry in entries where entry.active && entry.process == process {
      guard case .software(let handle) = entry.handle,
          let range = handle.overlap(address, count: count,
                                     at: entry.site.address) else {
        continue
      }
      for offset in 0 ..< range.count {
        output[start + range.buffer + offset] =
            handle.original[range.original + offset]
      }
    }
  }

  @inline(never)
  internal mutating func write(_ process: ProcessIdentifier,
                               address: Debuggee.Address,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    if bytes.isEmpty {
      return 0
    }
    guard UInt64(bytes.count - 1) <= UInt64.max - address.rawValue else {
      throw .memory
    }
    let type = UInt8.self
    let capacity = ABI.SoftwareBreakpoint.capacity
    var count = 0
    defer {
      for index in entries.indices where entries[index].process == process {
        guard case .software(var handle) = entries[index].handle,
            let range = handle.overlap(address, count: count,
                                       at: entries[index].site.address) else {
          continue
        }
        for offset in 0 ..< range.count {
          handle.original[range.original + offset] =
              bytes[range.buffer + offset]
        }
        entries[index].handle = .software(handle)
      }
    }
    try withUnsafeTemporaryAllocation(of: type, capacity: bytes.count,
                                      { buffer throws(Failure) in
      for index in bytes.indices {
        buffer[index] = bytes[index]
      }
      for entry in entries where entry.active && entry.process == process {
        guard case .software(let handle) = entry.handle,
            let range = handle.overlap(address, count: bytes.count,
                                       at: entry.site.address) else {
          continue
        }
        try withUnsafeTemporaryAllocation(of: type, capacity: capacity,
                                          { trap throws(Failure) in
          var output = OutputSpan(buffer: trap, initializedCount: 0)
          try ABI.breakpoint(handle.size, into: &output)
          for offset in 0 ..< range.count {
            buffer[range.buffer + offset] = output[range.original + offset]
          }
        })
      }
      try NativeMemory.write(process, address: address, bytes: buffer.span,
                             count: &count)
    })
    return count
  }
}
