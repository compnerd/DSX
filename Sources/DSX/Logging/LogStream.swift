// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private import Synchronization

internal struct LogStream: ~Copyable, Sendable {
  private let state: Mutex<LogState>
  private let threshold: Atomic<UInt8>
  private let channels: Atomic<UInt64>
  private let failed: Atomic<Bool>

  internal init(descriptor: CInt, level: LogLevel = .info,
                channels: UInt64 = LogChannel.all, colour: LogColour = .auto,
                close: Bool = false) {
    let enabled = switch colour {
    case .auto: NativeLog.terminal(descriptor)
    case .always: true
    case .never: false
    }
    state = Mutex(LogState(descriptor: descriptor, owned: close,
                           colour: enabled))
    threshold = Atomic(level.rawValue)
    self.channels = Atomic(channels)
    failed = Atomic(false)
  }

  internal init(path: String, append: Bool = true, level: LogLevel = .info,
                channels: UInt64 = LogChannel.all,
                colour: LogColour = .never) throws(LogError) {
    let descriptor = try NativeLog.open(path, append: append)
    self.init(descriptor: descriptor, level: level, channels: channels,
              colour: colour, close: true)
  }

  internal init(level: LogLevel = .info, channels: UInt64 = LogChannel.all,
                colour: LogColour = .auto) {
    self.init(descriptor: NativeLog.error, level: level, channels: channels,
              colour: colour)
  }

  deinit {
    state.withLock { state in
      if state.owned {
        NativeLog.close(state.descriptor)
      }
    }
  }

  internal func enabled(_ level: LogLevel, channel: LogChannel) -> Bool {
    if failed.load(ordering: .relaxed) {
      return false
    }
    let threshold = threshold.load(ordering: .relaxed)
    guard threshold < LogLevel.off.rawValue, level.rawValue >= threshold else {
      return false
    }
    let channels = channels.load(ordering: .relaxed)
    return channels & channel.bit > 0
  }

  internal func level(_ level: LogLevel) {
    threshold.store(level.rawValue, ordering: .relaxed)
  }

  internal func select(_ channels: UInt64) {
    self.channels.store(channels, ordering: .relaxed)
  }

  internal func redirect(_ descriptor: CInt, close: Bool, colour: LogColour) {
    let enabled = switch colour {
    case .auto: NativeLog.terminal(descriptor)
    case .always: true
    case .never: false
    }
    state.withLock { state in
      if state.owned {
        NativeLog.close(state.descriptor)
      }
      state.descriptor = descriptor
      state.owned = close
      state.colour = enabled
    }
    failed.store(false, ordering: .relaxed)
  }

  internal func callAsFunction(_ level: LogLevel, channel: LogChannel,
                               _ message: @autoclosure () -> String) {
    guard enabled(level, channel: channel) else {
      return
    }
    let message = message()
    let written = state.withLock { state in
      if failed.load(ordering: .relaxed) {
        return true
      }
      return state.emit(level, channel, message)
    }
    record(written)
  }

  internal func bytes(_ bytes: borrowing Span<UInt8>, level: LogLevel = .trace,
                      channel: LogChannel = .packet, direction: LogDirection) {
    guard enabled(level, channel: channel) else {
      return
    }
    let written = state.withLock { state in
      if failed.load(ordering: .relaxed) {
        return true
      }
      return state.emit(level, channel, direction, bytes)
    }
    record(written)
  }

  private func record(_ written: Bool) {
    if written {
      return
    }
    failed.store(true, ordering: .relaxed)
  }
}
