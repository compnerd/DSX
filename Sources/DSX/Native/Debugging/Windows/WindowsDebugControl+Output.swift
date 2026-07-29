// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  internal mutating func output(_ information: OUTPUT_DEBUG_STRING_INFO) {
    do throws(Debuggee.Error) {
      output = try Debuggee.Output(information, handle: handle)
    } catch {
      DSX.log("failed to read Windows debug output: \(error)", level: .warning,
              channel: .process)
      output = Debuggee.Output()
    }
  }
}

extension Debuggee.Output {
  @inline(__always)
  internal init(_ information: OUTPUT_DEBUG_STRING_INFO, handle: HANDLE?)
      throws(Debuggee.Error) {
    guard let handle, let address = information.lpDebugStringData else {
      throw .state
    }
    let count = Int(information.nDebugStringLength)
    guard count > 0 else {
      self.init()
      return
    }
    if information.fUnicode > 0 {
      // One lookahead unit keeps a truncated prefix on a scalar boundary.
      let capacity = min(count, Configuration.OutputCapacity + 1)
      self = try withUnsafeTemporaryAllocation(of: WCHAR.self,
                                               capacity: capacity,
                                               { input throws(Debuggee.Error) in
        var bytes: SIZE_T = 0
        let requested = SIZE_T(capacity * MemoryLayout<WCHAR>.stride)
        guard ReadProcessMemory(handle, address, input.baseAddress, requested,
                                &bytes) else {
          throw Debuggee.Error(process: GetLastError())
        }
        var count = Int(bytes) / MemoryLayout<WCHAR>.stride
        if count > 0, input[count - 1] == 0 {
          count -= 1
        }
        let text = UnsafeBufferPointer(start: input.baseAddress, count: count)
        return try Debuggee.Output(utf16: text)
      })
    } else {
      self.init()
      let requested = min(count, Configuration.OutputCapacity)
      self.count = try withUnsafeMutableBytes(of: &bytes,
                                              { bytes throws(Debuggee.Error) in
        var count: SIZE_T = 0
        guard ReadProcessMemory(handle, address, bytes.baseAddress,
                                SIZE_T(requested), &count) else {
          throw Debuggee.Error(process: GetLastError())
        }
        return Int(count)
      })
      if self.count > 0, bytes[self.count - 1] == 0 {
        self.count -= 1
      }
    }
  }

  @inline(__always)
  internal init(utf16 input: UnsafeBufferPointer<WCHAR>)
      throws(Debuggee.Error) {
    self.init()
    let fitted = input.fit(capacity: Configuration.OutputCapacity)
    let written = withUnsafeMutableBytes(of: &bytes) { output in
      let base = output.baseAddress?.assumingMemoryBound(to: CChar.self)
      return WideCharToMultiByte(CP_UTF8, 0, input.baseAddress, CInt(fitted),
                                 base, CInt(output.count), nil, nil)
    }
    guard written > 0 || fitted == 0 else {
      throw Debuggee.Error(process: GetLastError())
    }
    count = Int(written)
  }
}

extension UnsafeBufferPointer where Element == WCHAR {
  fileprivate func fit(capacity: Int) -> Int {
    var lower = 0
    var upper = count
    while lower < upper {
      let middle = lower + (upper - lower + 1) / 2
      let required = WideCharToMultiByte(CP_UTF8, 0, baseAddress, CInt(middle),
                                         nil, 0, nil, nil)
      if required <= capacity {
        lower = middle
      } else {
        upper = middle - 1
      }
    }
    if lower > 0, lower < count, self[lower - 1] & 0xfc00 == 0xd800,
        self[lower] & 0xfc00 == 0xdc00 {
      lower -= 1
    }
    return lower
  }
}
#endif
