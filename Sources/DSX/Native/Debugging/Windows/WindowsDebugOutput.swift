// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  internal mutating func output(_ information: OUTPUT_DEBUG_STRING_INFO) {
    do throws(Debuggee.Error) {
      output = try capture(handle, information: information)
    } catch {
      DSX.log("failed to read Windows debug output: \(error)", level: .warning,
              channel: .process)
      output = Debuggee.Output()
    }
  }
}

private func capture(_ handle: HANDLE?, information: OUTPUT_DEBUG_STRING_INFO)
    throws(Debuggee.Error) -> Debuggee.Output {
  guard let handle, let address = information.lpDebugStringData else {
    throw .state
  }
  let count = Int(information.nDebugStringLength)
  guard count > 0 else {
    return Debuggee.Output()
  }
  if information.fUnicode > 0 {
    return try unicode(handle, address: address, count: count)
  }
  return try narrow(handle, address: address, count: count)
}

private func narrow(_ handle: HANDLE, address: UnsafeMutableRawPointer,
                    count: Int) throws(Debuggee.Error) -> Debuggee.Output {
  var output = Debuggee.Output()
  let requested = min(count, Configuration.OutputCapacity)
  let read = try withUnsafeMutableBytes(of: &output.bytes,
                                        { bytes throws(Debuggee.Error) in
    var count: SIZE_T = 0
    guard ReadProcessMemory(handle, address, bytes.baseAddress,
                            SIZE_T(requested), &count) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    return Int(count)
  })
  output.count = read
  if output.count > 0, output.bytes[output.count - 1] == 0 {
    output.count -= 1
  }
  return output
}

private func unicode(_ handle: HANDLE, address: UnsafeMutableRawPointer,
                     count: Int) throws(Debuggee.Error) -> Debuggee.Output {
  let capacity = min(count, Configuration.OutputCapacity)
  return try withUnsafeTemporaryAllocation(of: WCHAR.self, capacity: capacity,
                                           { input throws(Debuggee.Error) in
    var bytes: SIZE_T = 0
    let requested = SIZE_T(capacity * MemoryLayout<WCHAR>.stride)
    guard ReadProcessMemory(handle, address, input.baseAddress, requested,
                            &bytes) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    var characters = Int(bytes) / MemoryLayout<WCHAR>.stride
    if characters > 0, input[characters - 1] == 0 {
      characters -= 1
    }
    return try encode(input, count: characters)
  })
}

private func encode(_ input: UnsafeMutableBufferPointer<WCHAR>,
                    count: Int) throws(Debuggee.Error) -> Debuggee.Output {
  var output = Debuggee.Output()
  let fitted = fit(input, count: count)
  let written = withUnsafeMutableBytes(of: &output.bytes) { output in
    let base = output.baseAddress?.assumingMemoryBound(to: CChar.self)
    return WideCharToMultiByte(CP_UTF8, 0, input.baseAddress, CInt(fitted),
                               base, CInt(output.count), nil, nil)
  }
  guard written > 0 || fitted == 0 else {
    throw WindowsDebugControl.failure(GetLastError())
  }
  output.count = Int(written)
  return output
}

private func fit(_ input: UnsafeMutableBufferPointer<WCHAR>,
                 count: Int) -> Int {
  var lower = 0
  var upper = count
  while lower < upper {
    let middle = lower + (upper - lower + 1) / 2
    let required = WideCharToMultiByte(CP_UTF8, 0, input.baseAddress,
                                       CInt(middle), nil, 0, nil, nil)
    if required <= Configuration.OutputCapacity {
      lower = middle
    } else {
      upper = middle - 1
    }
  }
  return lower
}
#endif
