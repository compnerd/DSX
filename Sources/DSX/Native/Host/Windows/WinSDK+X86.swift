// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(i386)
internal import WinSDK
internal import DSXShims

internal func RtlNtStatusToDosError(_ status: LONG) -> ULONG {
  dsx_RtlNtStatusToDosError(status)
}

internal func WSAStartup(_ version: WORD,
                         _ data: UnsafeMutablePointer<WSADATA>) -> CInt {
  dsx_WSAStartup(version, data)
}

internal func GetAddrInfoW(_ node: UnsafePointer<WCHAR>?,
                           _ service: UnsafePointer<WCHAR>?,
                           _ hints: UnsafePointer<ADDRINFOW>?,
                           _ result: UnsafeMutablePointer<PADDRINFOW?>)
    -> CInt {
  dsx_GetAddrInfoW(node, service, hints, result)
}

internal func FreeAddrInfoW(_ address: PADDRINFOW?) {
  dsx_FreeAddrInfoW(address)
}

internal func socket(_ family: CInt, _ type: CInt, _ `protocol`: CInt)
    -> SOCKET {
  dsx_socket(family, type, `protocol`)
}

internal func closesocket(_ socket: SOCKET) -> CInt {
  dsx_closesocket(socket)
}

internal func bind(_ socket: SOCKET, _ address: UnsafePointer<SOCKADDR>?,
                   _ length: CInt) -> CInt {
  dsx_bind(socket, address, length)
}

internal func setsockopt(_ socket: SOCKET, _ level: CInt, _ option: CInt,
                         _ value: UnsafePointer<CChar>?, _ length: CInt)
    -> CInt {
  dsx_setsockopt(socket, level, option, value, length)
}

internal func getsockname(_ socket: SOCKET,
                          _ address: UnsafeMutablePointer<SOCKADDR>?,
                          _ length: UnsafeMutablePointer<CInt>?) -> CInt {
  dsx_getsockname(socket, address, length)
}

internal func WSAPoll(_ descriptors: UnsafeMutablePointer<WSAPOLLFD>?,
                      _ count: ULONG, _ timeout: CInt) -> CInt {
  dsx_WSAPoll(descriptors, count, timeout)
}

internal func recv(_ socket: SOCKET, _ buffer: UnsafeMutableRawPointer?,
                   _ size: CInt, _ flags: CInt) -> CInt {
  dsx_recv(socket, buffer, size, flags)
}

internal func send(_ socket: SOCKET, _ buffer: UnsafeRawPointer?, _ size: CInt,
                   _ flags: CInt) -> CInt {
  dsx_send(socket, buffer, size, flags)
}

internal func GetCurrentDirectoryW(_ capacity: DWORD,
                                   _ buffer: UnsafeMutablePointer<WCHAR>?)
    -> DWORD {
  dsx_GetCurrentDirectoryW(capacity, buffer)
}

internal func PathCchCanonicalizeEx(_ output: UnsafeMutablePointer<WCHAR>?,
                                    _ capacity: Int,
                                    _ path: UnsafePointer<WCHAR>?,
                                    _ flags: ULONG) -> HRESULT {
  dsx_PathCchCanonicalizeEx(output, capacity, path, flags)
}

internal func PathCchCombineEx(_ output: UnsafeMutablePointer<WCHAR>?,
                               _ capacity: Int, _ base: UnsafePointer<WCHAR>?,
                               _ path: UnsafePointer<WCHAR>?, _ flags: ULONG)
    -> HRESULT {
  dsx_PathCchCombineEx(output, capacity, base, path, flags)
}

internal func PathCchIsRoot(_ path: UnsafePointer<WCHAR>?) -> Bool {
  dsx_PathCchIsRoot(path)
}

internal func PathCchRemoveFileSpec(_ path: UnsafeMutablePointer<WCHAR>?,
                                    _ capacity: Int) -> HRESULT {
  dsx_PathCchRemoveFileSpec(path, capacity)
}

internal func PathCchStripPrefix(_ path: UnsafeMutablePointer<WCHAR>?,
                                 _ capacity: Int) -> HRESULT {
  dsx_PathCchStripPrefix(path, capacity)
}

internal func CreateDirectoryW(_ path: UnsafePointer<WCHAR>?,
                               _ attributes: LPSECURITY_ATTRIBUTES?) -> Bool {
  dsx_CreateDirectoryW(path, attributes)
}

internal func CreateFileW(_ path: UnsafePointer<WCHAR>?, _ access: DWORD,
                          _ share: DWORD, _ attributes: LPSECURITY_ATTRIBUTES?,
                          _ disposition: DWORD, _ flags: DWORD,
                          _ template: HANDLE?) -> HANDLE? {
  dsx_CreateFileW(path, access, share, attributes, disposition, flags, template)
}

internal func GetFileInformationByHandle(_ handle: HANDLE?,
                                         _ info: LPBY_HANDLE_FILE_INFORMATION?)
    -> Bool {
  dsx_GetFileInformationByHandle(handle, info)
}

internal func CloseHandle(_ handle: HANDLE?) -> Bool {
  dsx_CloseHandle(handle)
}

internal func GetFileSizeEx(_ handle: HANDLE?,
                            _ size: UnsafeMutablePointer<LARGE_INTEGER>?)
    -> Bool {
  dsx_GetFileSizeEx(handle, size)
}

internal func GetFileAttributesW(_ path: LPCWSTR?) -> DWORD {
  dsx_GetFileAttributesW(path)
}

internal func SetFileAttributesW(_ path: LPCWSTR?, _ attributes: DWORD)
    -> Bool {
  dsx_SetFileAttributesW(path, attributes)
}

internal func CreateFileMappingW(_ file: HANDLE?,
                                 _ attributes: LPSECURITY_ATTRIBUTES?,
                                 _ protection: DWORD, _ high: DWORD,
                                 _ low: DWORD, _ name: UnsafePointer<WCHAR>?)
    -> HANDLE? {
  dsx_CreateFileMappingW(file, attributes, protection, high, low, name)
}

internal func MapViewOfFile(_ mapping: HANDLE?, _ access: DWORD, _ high: DWORD,
                            _ low: DWORD, _ size: SIZE_T)
    -> UnsafeMutableRawPointer? {
  dsx_MapViewOfFile(mapping, access, high, low, size)
}

internal func UnmapViewOfFile(_ address: UnsafeRawPointer?) -> Bool {
  dsx_UnmapViewOfFile(address)
}

internal func ReadFile(_ handle: HANDLE?, _ buffer: UnsafeMutableRawPointer?,
                       _ size: DWORD, _ count: UnsafeMutablePointer<DWORD>?,
                       _ overlapped: LPOVERLAPPED?) -> Bool {
  dsx_ReadFile(handle, buffer, size, count, overlapped)
}

internal func WriteFile(_ handle: HANDLE?, _ buffer: UnsafeRawPointer?,
                        _ size: DWORD, _ count: UnsafeMutablePointer<DWORD>?,
                        _ overlapped: LPOVERLAPPED?) -> Bool {
  dsx_WriteFile(handle, buffer, size, count, overlapped)
}

internal func CreatePipe(_ reader: UnsafeMutablePointer<HANDLE?>?,
                         _ writer: UnsafeMutablePointer<HANDLE?>?,
                         _ attributes: LPSECURITY_ATTRIBUTES?, _ size: DWORD)
    -> Bool {
  dsx_CreatePipe(reader, writer, attributes, size)
}

internal func SetHandleInformation(_ handle: HANDLE?, _ mask: DWORD,
                                   _ flags: DWORD) -> Bool {
  dsx_SetHandleInformation(handle, mask, flags)
}

internal func PeekNamedPipe(_ handle: HANDLE?,
                            _ buffer: UnsafeMutableRawPointer?, _ size: DWORD,
                            _ read: UnsafeMutablePointer<DWORD>?,
                            _ available: UnsafeMutablePointer<DWORD>?,
                            _ remaining: UnsafeMutablePointer<DWORD>?) -> Bool {
  dsx_PeekNamedPipe(handle, buffer, size, read, available, remaining)
}

internal func WaitForSingleObject(_ handle: HANDLE?, _ timeout: DWORD)
    -> DWORD {
  dsx_WaitForSingleObject(handle, timeout)
}

internal func Sleep(_ duration: DWORD) {
  dsx_Sleep(duration)
}

internal func GetModuleFileNameW(_ module: HMODULE?,
                                 _ path: UnsafeMutablePointer<WCHAR>?,
                                 _ size: DWORD) -> DWORD {
  dsx_GetModuleFileNameW(module, path, size)
}

internal func GetModuleHandleW(_ name: UnsafePointer<WCHAR>?) -> HMODULE? {
  dsx_GetModuleHandleW(name)
}

internal func GetEnvironmentVariableW(_ name: UnsafePointer<WCHAR>?,
                                      _ value: UnsafeMutablePointer<WCHAR>?,
                                      _ size: DWORD) -> DWORD {
  dsx_GetEnvironmentVariableW(name, value, size)
}

internal func FreeEnvironmentStringsW(_ block: UnsafeMutablePointer<WCHAR>?)
    -> Bool {
  dsx_FreeEnvironmentStringsW(block)
}

internal func CompareStringOrdinal(_ lhs: UnsafePointer<WCHAR>?, _ lcount: CInt,
                                   _ rhs: UnsafePointer<WCHAR>?, _ rcount: CInt,
                                   _ ignore: Bool) -> CInt {
  dsx_CompareStringOrdinal(lhs, lcount, rhs, rcount, ignore)
}

internal func SetLastError(_ error: DWORD) {
  dsx_SetLastError(error)
}

internal func DebugSetProcessKillOnExit(_ kill: Bool) -> Bool {
  dsx_DebugSetProcessKillOnExit(kill)
}

internal func WaitForDebugEventEx(_ event: UnsafeMutablePointer<DEBUG_EVENT>?,
                                  _ timeout: DWORD) -> Bool {
  dsx_WaitForDebugEventEx(event, timeout)
}

internal func ContinueDebugEvent(_ process: DWORD, _ thread: DWORD,
                                 _ status: DWORD) -> Bool {
  dsx_ContinueDebugEvent(process, thread, status)
}

internal func GetFinalPathNameByHandleW(_ handle: HANDLE?,
                                        _ path: UnsafeMutablePointer<WCHAR>?,
                                        _ size: DWORD, _ flags: DWORD)
    -> DWORD {
  dsx_GetFinalPathNameByHandleW(handle, path, size, flags)
}

internal func GetThreadContext(_ thread: HANDLE?,
                               _ context: UnsafeMutablePointer<CONTEXT>?)
    -> Bool {
  dsx_GetThreadContext(thread, context)
}

internal func SetThreadContext(_ thread: HANDLE?,
                               _ context: UnsafePointer<CONTEXT>?) -> Bool {
  dsx_SetThreadContext(thread, context)
}

internal func ResumeThread(_ thread: HANDLE?) -> DWORD {
  dsx_ResumeThread(thread)
}

internal func SuspendThread(_ thread: HANDLE?) -> DWORD {
  dsx_SuspendThread(thread)
}

internal func ReadProcessMemory(_ process: HANDLE?,
                                _ address: UnsafeRawPointer?,
                                _ buffer: UnsafeMutableRawPointer?,
                                _ size: SIZE_T, _ read: PSIZE_T?) -> Bool {
  dsx_ReadProcessMemory(process, address, buffer, size, read)
}

internal func WriteProcessMemory(_ process: HANDLE?,
                                 _ address: UnsafeMutableRawPointer?,
                                 _ buffer: UnsafeRawPointer?, _ size: SIZE_T,
                                 _ written: PSIZE_T?) -> Bool {
  dsx_WriteProcessMemory(process, address, buffer, size, written)
}

internal func FlushInstructionCache(_ process: HANDLE?,
                                    _ address: UnsafeRawPointer?,
                                    _ size: SIZE_T) -> Bool {
  dsx_FlushInstructionCache(process, address, size)
}

internal func GetWindowsDirectoryW(_ path: UnsafeMutablePointer<WCHAR>?,
                                   _ size: UINT) -> UINT {
  dsx_GetWindowsDirectoryW(path, size)
}

internal func OpenThread(_ access: DWORD, _ inherit: Bool,
                         _ thread: DWORD) -> HANDLE? {
  dsx_OpenThread(access, inherit, thread)
}

internal func OpenProcess(_ access: DWORD, _ inherit: Bool,
                          _ process: DWORD) -> HANDLE? {
  dsx_OpenProcess(access, inherit, process)
}

internal func CreateToolhelp32Snapshot(_ flags: DWORD,
                                       _ process: DWORD) -> HANDLE? {
  dsx_CreateToolhelp32Snapshot(flags, process)
}

internal func Thread32First(_ snapshot: HANDLE?,
                            _ entry: UnsafeMutablePointer<THREADENTRY32>?)
    -> Bool {
  dsx_Thread32First(snapshot, entry)
}

internal func Thread32Next(_ snapshot: HANDLE?,
                           _ entry: UnsafeMutablePointer<THREADENTRY32>?)
    -> Bool {
  dsx_Thread32Next(snapshot, entry)
}

internal func GetThreadDescription(_ thread: HANDLE?,
                                   _ description: UnsafeMutablePointer<PWSTR?>?)
    -> HRESULT {
  dsx_GetThreadDescription(thread, description)
}

internal func Module32FirstW(_ snapshot: HANDLE?,
                             _ entry: UnsafeMutablePointer<MODULEENTRY32W>?)
    -> Bool {
  dsx_Module32FirstW(snapshot, entry)
}

internal func Module32NextW(_ snapshot: HANDLE?,
                            _ entry: UnsafeMutablePointer<MODULEENTRY32W>?)
    -> Bool {
  dsx_Module32NextW(snapshot, entry)
}

internal func LocalFree(_ memory: HLOCAL?) -> HLOCAL? {
  dsx_LocalFree(memory)
}

internal func VirtualProtectEx(_ process: HANDLE?,
                               _ address: UnsafeMutableRawPointer?,
                               _ size: SIZE_T, _ protection: DWORD,
                               _ previous: PDWORD?) -> Bool {
  dsx_VirtualProtectEx(process, address, size, protection, previous)
}

internal func Process32FirstW(_ snapshot: HANDLE?,
                              _ entry: UnsafeMutablePointer<PROCESSENTRY32W>?)
    -> Bool {
  dsx_Process32FirstW(snapshot, entry)
}

internal func Process32NextW(_ snapshot: HANDLE?,
                             _ entry: UnsafeMutablePointer<PROCESSENTRY32W>?)
    -> Bool {
  dsx_Process32NextW(snapshot, entry)
}

internal func IsWow64Process2(_ process: HANDLE?,
                              _ guest: UnsafeMutablePointer<USHORT>?,
                              _ native: UnsafeMutablePointer<USHORT>?) -> Bool {
  dsx_IsWow64Process2(process, guest, native)
}

internal func GetProcessInformation(_ process: HANDLE,
                                    _ kind: PROCESS_INFORMATION_CLASS,
                                    _ information: UnsafeMutableRawPointer,
                                    _ size: DWORD) -> Bool {
  dsx_GetProcessInformation(process, kind, information, size)
}

internal func VirtualQueryEx(_ process: HANDLE?, _ address: UnsafeRawPointer?,
                             _ info: PMEMORY_BASIC_INFORMATION?,
                             _ size: SIZE_T) -> SIZE_T {
  dsx_VirtualQueryEx(process, address, info, size)
}

internal func VirtualAllocEx(_ process: HANDLE?,
                             _ address: UnsafeMutableRawPointer?,
                             _ size: SIZE_T, _ allocation: DWORD,
                             _ protection: DWORD) -> UnsafeMutableRawPointer? {
  dsx_VirtualAllocEx(process, address, size, allocation, protection)
}

internal func VirtualFreeEx(_ process: HANDLE?,
                            _ address: UnsafeMutableRawPointer?, _ size: SIZE_T,
                            _ type: DWORD) -> Bool {
  dsx_VirtualFreeEx(process, address, size, type)
}

internal func DebugActiveProcess(_ process: DWORD) -> Bool {
  dsx_DebugActiveProcess(process)
}

internal func DebugActiveProcessStop(_ process: DWORD) -> Bool {
  dsx_DebugActiveProcessStop(process)
}

internal func DebugBreakProcess(_ process: HANDLE?) -> Bool {
  dsx_DebugBreakProcess(process)
}

internal func GetExitCodeProcess(_ handle: HANDLE?,
                                 _ code: UnsafeMutablePointer<DWORD>?) -> Bool {
  dsx_GetExitCodeProcess(handle, code)
}

internal func TerminateProcess(_ handle: HANDLE?, _ code: UINT) -> Bool {
  dsx_TerminateProcess(handle, code)
}

internal func GetStdHandle(_ standard: DWORD) -> HANDLE? {
  dsx_GetStdHandle(standard)
}

internal func DuplicateHandle(_ source: HANDLE?, _ handle: HANDLE?,
                              _ target: HANDLE?,
                              _ duplicate: UnsafeMutablePointer<HANDLE?>?,
                              _ access: DWORD, _ inherit: Bool,
                              _ options: DWORD) -> Bool {
  dsx_DuplicateHandle(source, handle, target, duplicate, access, inherit,
                      options)
}

internal func InitializeProcThreadAttributeList(_ list: OpaquePointer?,
                                                _ count: DWORD, _ flags: DWORD,
                                                _ size: PSIZE_T?) -> Bool {
  dsx_InitializeProcThreadAttributeList(list, count, flags, size)
}

internal func UpdateProcThreadAttribute(_ list: LPPROC_THREAD_ATTRIBUTE_LIST?,
                                        _ flags: DWORD, _ attribute: DWORD_PTR,
                                        _ value: UnsafeMutableRawPointer?,
                                        _ size: SIZE_T,
                                        _ previous: UnsafeMutableRawPointer?,
                                        _ returned: PSIZE_T?) -> Bool {
  dsx_UpdateProcThreadAttribute(list, flags, attribute, value, size, previous,
                                returned)
}

internal func DeleteProcThreadAttributeList(_ list: OpaquePointer?) {
  dsx_DeleteProcThreadAttributeList(list)
}

internal func CreateProcessW(_ application: UnsafePointer<WCHAR>?,
                             _ command: UnsafeMutablePointer<WCHAR>?,
                             _ process: LPSECURITY_ATTRIBUTES?,
                             _ thread: LPSECURITY_ATTRIBUTES?, _ inherit: Bool,
                             _ flags: DWORD,
                             _ environment: UnsafeMutableRawPointer?,
                             _ directory: UnsafePointer<WCHAR>?,
                             _ startup: LPSTARTUPINFOW?,
                             _ information: LPPROCESS_INFORMATION?) -> Bool {
  dsx_CreateProcessW(application, command, process, thread, inherit, flags,
                     environment, directory, startup, information)
}
#endif
