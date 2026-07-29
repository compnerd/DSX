// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define DSX_HIDDEN
#else
#define DSX_HIDDEN __attribute__((__visibility__("hidden")))
#endif

#if defined(_WIN32)
#include <ntstatus.h>
#define WIN32_NO_STATUS
#include <winsock2.h>
#include <Windows.h>
#undef WIN32_NO_STATUS
#include <winternl.h>
#include <bcrypt.h>

// Fold the signed NTSTATUS macro in Clang before Swift imports its literal.
enum { dsx_STATUS_THREAD_IS_TERMINATING = STATUS_THREAD_IS_TERMINATING };

#if defined(_M_IX86)
#include <pathcch.h>
#include <tlhelp32.h>
#include <ws2tcpip.h>

// FIXME(#1) Swift's x86 stdcall lowering can use stale ESP-relative stack slots
// after the callee pops its arguments. Keep these calls in Clang until the
// toolchain fixes the calling-convention defect.
static inline int dsx_WSAStartup(WORD version, LPWSADATA data) {
  return WSAStartup(version, data);
}

static inline int dsx_GetAddrInfoW(PCWSTR node, PCWSTR service,
                                   const ADDRINFOW *hints,
                                   PADDRINFOW *result) {
  return GetAddrInfoW(node, service, hints, result);
}

static inline void dsx_FreeAddrInfoW(PADDRINFOW address) {
  FreeAddrInfoW(address);
}

static inline SOCKET dsx_socket(int family, int type, int protocol) {
  return socket(family, type, protocol);
}

static inline int dsx_closesocket(SOCKET socket) {
  return closesocket(socket);
}

static inline int dsx_bind(SOCKET socket, const struct sockaddr *address,
                           int length) {
  return bind(socket, address, length);
}

static inline int dsx_connect(SOCKET socket, const struct sockaddr *address,
                              int length) {
  return connect(socket, address, length);
}

static inline int dsx_listen(SOCKET socket, int backlog) {
  return listen(socket, backlog);
}

static inline SOCKET dsx_accept(SOCKET socket, struct sockaddr *address,
                                int *length) {
  return accept(socket, address, length);
}

static inline int dsx_setsockopt(SOCKET socket, int level, int option,
                                 const char *value, int length) {
  return setsockopt(socket, level, option, value, length);
}

static inline int dsx_getsockname(SOCKET socket, struct sockaddr *address,
                                  int *length) {
  return getsockname(socket, address, length);
}

static inline int dsx_WSAPoll(LPWSAPOLLFD descriptors, ULONG count,
                              int timeout) {
  return WSAPoll(descriptors, count, timeout);
}

static inline int dsx_recv(SOCKET socket, void *buffer, int size, int flags) {
  return recv(socket, buffer, size, flags);
}

static inline int dsx_send(SOCKET socket, const void *buffer, int size,
                           int flags) {
  return send(socket, buffer, size, flags);
}

static inline DWORD dsx_GetCurrentDirectoryW(DWORD capacity, LPWSTR buffer) {
  return GetCurrentDirectoryW(capacity, buffer);
}

static inline HRESULT dsx_PathCchCanonicalizeEx(PWSTR output, size_t capacity,
                                               PCWSTR path, ULONG flags) {
  return PathCchCanonicalizeEx(output, capacity, path, flags);
}

static inline HRESULT dsx_PathCchCombineEx(PWSTR output, size_t capacity,
                                          PCWSTR base, PCWSTR path,
                                          ULONG flags) {
  return PathCchCombineEx(output, capacity, base, path, flags);
}

static inline BOOL dsx_PathCchIsRoot(PCWSTR path) {
  return PathCchIsRoot(path);
}

static inline HRESULT dsx_PathCchRemoveFileSpec(PWSTR path, size_t capacity) {
  return PathCchRemoveFileSpec(path, capacity);
}

static inline HRESULT dsx_PathCchStripPrefix(PWSTR path, size_t capacity) {
  return PathCchStripPrefix(path, capacity);
}

static inline BOOL dsx_CreateDirectoryW(PCWSTR path,
                                        LPSECURITY_ATTRIBUTES attributes) {
  return CreateDirectoryW(path, attributes);
}

static inline HANDLE dsx_CreateFileW(PCWSTR path, DWORD access, DWORD share,
                                     LPSECURITY_ATTRIBUTES attributes,
                                     DWORD disposition, DWORD flags,
                                     HANDLE template) {
  return CreateFileW(path, access, share, attributes, disposition, flags,
                     template);
}

static inline BOOL
dsx_GetFileInformationByHandle(HANDLE handle,
                               BY_HANDLE_FILE_INFORMATION *info) {
  return GetFileInformationByHandle(handle, info);
}

static inline BOOL dsx_CloseHandle(HANDLE handle) {
  return CloseHandle(handle);
}

static inline BOOL dsx_GetFileSizeEx(HANDLE handle, PLARGE_INTEGER size) {
  return GetFileSizeEx(handle, size);
}

static inline DWORD dsx_GetFileAttributesW(LPCWSTR path) {
  return GetFileAttributesW(path);
}

static inline BOOL dsx_SetFileAttributesW(LPCWSTR path, DWORD attributes) {
  return SetFileAttributesW(path, attributes);
}

static inline HANDLE dsx_CreateFileMappingW(HANDLE file,
                                            LPSECURITY_ATTRIBUTES attributes,
                                            DWORD protection, DWORD high,
                                            DWORD low, PCWSTR name) {
  return CreateFileMappingW(file, attributes, protection, high, low, name);
}

static inline LPVOID dsx_MapViewOfFile(HANDLE mapping, DWORD access, DWORD high,
                                      DWORD low, SIZE_T size) {
  return MapViewOfFile(mapping, access, high, low, size);
}

static inline BOOL dsx_UnmapViewOfFile(LPCVOID address) {
  return UnmapViewOfFile(address);
}

static inline BOOL dsx_ReadFile(HANDLE handle, LPVOID buffer, DWORD size,
                                LPDWORD count, LPOVERLAPPED overlapped) {
  return ReadFile(handle, buffer, size, count, overlapped);
}

static inline BOOL dsx_WriteFile(HANDLE handle, LPCVOID buffer, DWORD size,
                                 LPDWORD count, LPOVERLAPPED overlapped) {
  return WriteFile(handle, buffer, size, count, overlapped);
}

static inline BOOL dsx_CreatePipe(PHANDLE reader, PHANDLE writer,
                                  LPSECURITY_ATTRIBUTES attributes,
                                  DWORD size) {
  return CreatePipe(reader, writer, attributes, size);
}

static inline BOOL dsx_SetHandleInformation(HANDLE handle, DWORD mask,
                                            DWORD flags) {
  return SetHandleInformation(handle, mask, flags);
}

static inline BOOL dsx_PeekNamedPipe(HANDLE handle, LPVOID buffer, DWORD size,
                                     LPDWORD read, LPDWORD available,
                                     LPDWORD remaining) {
  return PeekNamedPipe(handle, buffer, size, read, available, remaining);
}

static inline DWORD dsx_WaitForSingleObject(HANDLE handle, DWORD timeout) {
  return WaitForSingleObject(handle, timeout);
}

static inline void dsx_Sleep(DWORD duration) {
  Sleep(duration);
}

static inline DWORD dsx_GetModuleFileNameW(HMODULE module, LPWSTR path,
                                         DWORD size) {
  return GetModuleFileNameW(module, path, size);
}

static inline HMODULE dsx_GetModuleHandleW(LPCWSTR name) {
  return GetModuleHandleW(name);
}

static inline DWORD dsx_GetEnvironmentVariableW(LPCWSTR name, LPWSTR value,
                                               DWORD size) {
  return GetEnvironmentVariableW(name, value, size);
}

static inline BOOL dsx_FreeEnvironmentStringsW(LPWCH block) {
  return FreeEnvironmentStringsW(block);
}

static inline int dsx_CompareStringOrdinal(LPCWCH lhs, int lcount, LPCWCH rhs,
                                         int rcount, BOOL ignore) {
  return CompareStringOrdinal(lhs, lcount, rhs, rcount, ignore);
}

static inline void dsx_SetLastError(DWORD error) {
  SetLastError(error);
}

static inline BOOL dsx_DebugSetProcessKillOnExit(BOOL kill) {
  return DebugSetProcessKillOnExit(kill);
}

static inline BOOL dsx_WaitForDebugEventEx(LPDEBUG_EVENT event, DWORD timeout) {
  return WaitForDebugEventEx(event, timeout);
}

static inline BOOL dsx_ContinueDebugEvent(DWORD process, DWORD thread,
                                          DWORD status) {
  return ContinueDebugEvent(process, thread, status);
}

static inline DWORD dsx_GetFinalPathNameByHandleW(HANDLE handle, LPWSTR path,
                                                  DWORD size, DWORD flags) {
  return GetFinalPathNameByHandleW(handle, path, size, flags);
}

static inline BOOL dsx_GetThreadContext(HANDLE thread, LPCONTEXT context) {
  return GetThreadContext(thread, context);
}

static inline BOOL dsx_SetThreadContext(HANDLE thread, const CONTEXT *context) {
  return SetThreadContext(thread, context);
}

static inline DWORD dsx_ResumeThread(HANDLE thread) {
  return ResumeThread(thread);
}

static inline DWORD dsx_SuspendThread(HANDLE thread) {
  return SuspendThread(thread);
}

static inline ULONG dsx_RtlNtStatusToDosError(LONG status) {
  return RtlNtStatusToDosError(status);
}

static inline BOOL dsx_ReadProcessMemory(HANDLE process, LPCVOID address,
                                         LPVOID buffer, SIZE_T size,
                                         SIZE_T *read) {
  return ReadProcessMemory(process, address, buffer, size, read);
}

static inline BOOL dsx_WriteProcessMemory(HANDLE process, LPVOID address,
                                          LPCVOID buffer, SIZE_T size,
                                          SIZE_T *written) {
  return WriteProcessMemory(process, address, buffer, size, written);
}

static inline BOOL dsx_FlushInstructionCache(HANDLE process, LPCVOID address,
                                             SIZE_T size) {
  return FlushInstructionCache(process, address, size);
}

static inline UINT dsx_GetWindowsDirectoryW(LPWSTR path, UINT size) {
  return GetWindowsDirectoryW(path, size);
}

static inline HANDLE dsx_OpenThread(DWORD access, BOOL inherit, DWORD thread) {
  return OpenThread(access, inherit, thread);
}

static inline HANDLE dsx_OpenProcess(DWORD access, BOOL inherit,
                                     DWORD process) {
  return OpenProcess(access, inherit, process);
}

static inline HANDLE dsx_CreateToolhelp32Snapshot(DWORD flags, DWORD process) {
  return CreateToolhelp32Snapshot(flags, process);
}

static inline BOOL dsx_Thread32First(HANDLE snapshot, LPTHREADENTRY32 entry) {
  return Thread32First(snapshot, entry);
}

static inline BOOL dsx_Thread32Next(HANDLE snapshot, LPTHREADENTRY32 entry) {
  return Thread32Next(snapshot, entry);
}

static inline BOOL dsx_Module32FirstW(HANDLE snapshot, LPMODULEENTRY32W entry) {
  return Module32FirstW(snapshot, entry);
}

static inline BOOL dsx_Module32NextW(HANDLE snapshot, LPMODULEENTRY32W entry) {
  return Module32NextW(snapshot, entry);
}

static inline HRESULT dsx_GetThreadDescription(HANDLE thread,
                                               PWSTR *description) {
  return GetThreadDescription(thread, description);
}

static inline HLOCAL dsx_LocalFree(HLOCAL memory) {
  return LocalFree(memory);
}

static inline BOOL dsx_VirtualProtectEx(HANDLE process, LPVOID address,
                                        SIZE_T size, DWORD protection,
                                        PDWORD previous) {
  return VirtualProtectEx(process, address, size, protection, previous);
}

static inline BOOL dsx_Process32FirstW(HANDLE snapshot,
                                       LPPROCESSENTRY32W entry) {
  return Process32FirstW(snapshot, entry);
}

static inline BOOL dsx_Process32NextW(HANDLE snapshot,
                                      LPPROCESSENTRY32W entry) {
  return Process32NextW(snapshot, entry);
}

static inline BOOL dsx_IsWow64Process2(HANDLE process, USHORT *guest,
                                       USHORT *native) {
  return IsWow64Process2(process, guest, native);
}

static inline BOOL dsx_GetProcessInformation(HANDLE process,
                                             PROCESS_INFORMATION_CLASS kind,
                                             LPVOID information, DWORD size) {
  return GetProcessInformation(process, kind, information, size);
}

static inline SIZE_T dsx_VirtualQueryEx(HANDLE process, LPCVOID address,
                                        PMEMORY_BASIC_INFORMATION info,
                                        SIZE_T size) {
  return VirtualQueryEx(process, address, info, size);
}

static inline LPVOID dsx_VirtualAllocEx(HANDLE process, LPVOID address,
                                        SIZE_T size, DWORD allocation,
                                        DWORD protection) {
  return VirtualAllocEx(process, address, size, allocation, protection);
}

static inline BOOL dsx_VirtualFreeEx(HANDLE process, LPVOID address,
                                     SIZE_T size, DWORD type) {
  return VirtualFreeEx(process, address, size, type);
}

static inline BOOL dsx_DebugActiveProcess(DWORD process) {
  return DebugActiveProcess(process);
}

static inline BOOL dsx_DebugActiveProcessStop(DWORD process) {
  return DebugActiveProcessStop(process);
}

static inline BOOL dsx_DebugBreakProcess(HANDLE process) {
  return DebugBreakProcess(process);
}

static inline BOOL dsx_GetExitCodeProcess(HANDLE handle, LPDWORD code) {
  return GetExitCodeProcess(handle, code);
}

static inline BOOL dsx_TerminateProcess(HANDLE handle, UINT code) {
  return TerminateProcess(handle, code);
}

static inline HANDLE dsx_GetStdHandle(DWORD standard) {
  return GetStdHandle(standard);
}

static inline BOOL dsx_DuplicateHandle(HANDLE source, HANDLE handle,
                                       HANDLE target, LPHANDLE duplicate,
                                       DWORD access, BOOL inherit,
                                       DWORD options) {
  return DuplicateHandle(source, handle, target, duplicate, access, inherit,
                         options);
}

static inline BOOL
dsx_InitializeProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST list,
                                     DWORD count, DWORD flags, PSIZE_T size) {
  return InitializeProcThreadAttributeList(list, count, flags, size);
}

static inline BOOL
dsx_UpdateProcThreadAttribute(LPPROC_THREAD_ATTRIBUTE_LIST list, DWORD flags,
                              DWORD_PTR attribute, PVOID value, SIZE_T size,
                              PVOID previous, PSIZE_T returned) {
  return UpdateProcThreadAttribute(list, flags, attribute, value, size,
                                   previous, returned);
}

static inline void
dsx_DeleteProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST list) {
  DeleteProcThreadAttributeList(list);
}

static inline BOOL dsx_CreateProcessW(LPCWSTR application, LPWSTR command,
                                      LPSECURITY_ATTRIBUTES process,
                                      LPSECURITY_ATTRIBUTES thread,
                                      BOOL inherit, DWORD flags,
                                      LPVOID environment, LPCWSTR directory,
                                      LPSTARTUPINFOW startup,
                                      LPPROCESS_INFORMATION information) {
  return CreateProcessW(application, command, process, thread, inherit, flags,
                        environment, directory, startup, information);
}

static inline void dsx_AcquireSRWLockExclusive(PSRWLOCK lock) {
  AcquireSRWLockExclusive(lock);
}

static inline void dsx_ReleaseSRWLockExclusive(PSRWLOCK lock) {
  ReleaseSRWLockExclusive(lock);
}
#endif

static inline BCRYPT_ALG_HANDLE dsx_md5_algorithm(void) {
  return BCRYPT_MD5_ALG_HANDLE;
}

// See REPARSE_DATA_BUFFER in ntifs.h (not part of the user-mode SDK).
typedef struct dsx_reparse_names {
  ULONG ReparseTag;
  USHORT ReparseDataLength;
  USHORT Reserved;
  USHORT SubstituteNameOffset;
  USHORT SubstituteNameLength;
  USHORT PrintNameOffset;
  USHORT PrintNameLength;
} dsx_reparse_names;

static inline DWORD_PTR dsx_proc_thread_attribute_handle_list(void) {
  return PROC_THREAD_ATTRIBUTE_HANDLE_LIST;
}

// THREAD_BASIC_INFORMATION is not exposed by the user-mode SDK.
typedef struct dsx_thread_basic_information {
  LONG ExitStatus;
  void *TebBaseAddress;
  struct {
    HANDLE UniqueProcess;
    HANDLE UniqueThread;
  } ClientId;
  ULONG_PTR AffinityMask;
  LONG Priority;
  LONG BasePriority;
} dsx_thread_basic_information;

DSX_HIDDEN LONG dsx_NtQueryInformationThread(HANDLE thread, int information,
                                             void *output, ULONG size,
                                             ULONG *returned);
DSX_HIDDEN LONG dsx_NtSuspendThread(HANDLE thread, ULONG *count);
DSX_HIDDEN LONG dsx_RtlGetVersion(OSVERSIONINFOW *version);
#else
#include <signal.h>
#include <spawn.h>
#include <sys/ioctl.h>
#include <sys/types.h>

#if defined(__OpenBSD__)
#include <sys/time.h>
// Exported by libc, but absent from its public signal.h.
int __thrsigdivert(sigset_t set, siginfo_t *info,
                  const struct timespec *timeout);
#endif

#if defined(__APPLE__)
#include <CommonCrypto/CommonDigest.h>

#if __has_include(<mach-o/dyld_process_info.h>)
#include <mach-o/dyld_process_info.h>
#else
// Private dyld SPI layout from <mach-o/dyld_process_info.h>.
typedef struct dyld_process_state_info {
  uint64_t timestamp;
  uint32_t imageCount;
  uint32_t initialImageCount;
  uint8_t dyldState;
} dyld_process_state_info;
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline int dsx_md5_init(CC_MD5_CTX *context) {
  return CC_MD5_Init(context);
}

static inline int dsx_md5_update(CC_MD5_CTX *context, const void *data,
                                 CC_LONG count) {
  return CC_MD5_Update(context, data, count);
}

static inline int dsx_md5_final(unsigned char *digest, CC_MD5_CTX *context) {
  return CC_MD5_Final(digest, context);
}
#pragma clang diagnostic pop
#elif defined(__ANDROID__)
// MD5 is supplied by Swift Crypto.
#elif defined(__linux__)
#include <openssl/evp.h>
// EVP_MD_CTX is opaque in OpenSSL but complete in BoringSSL.
typedef EVP_MD_CTX *dsx_digest_context;
#elif defined(__FreeBSD__) || defined(__OpenBSD__)
#include <md5.h>
#else
#error "MD5 provider required for this platform"
#endif

#if !defined(__APPLE__)
DSX_HIDDEN int dsx_spawn_chdir(void *actions, const char *path);
DSX_HIDDEN int dsx_pipe2(int descriptors[2], int flags);
#endif

static inline int dsx_terminal_size(int descriptor, uint16_t columns,
                                    uint16_t rows) {
  struct winsize size = {
      .ws_row = rows,
      .ws_col = columns,
  };
  return ioctl(descriptor, TIOCSWINSZ, &size);
}

#if defined(__APPLE__)
#include <mach/mach.h>
#include <sys/ptrace.h>
#include <unistd.h>

typedef struct dsx_exception_context dsx_exception_context;

typedef struct dsx_exception_record {
  mach_port_t thread;
  mach_port_t task;
  exception_type_t type;
  mach_msg_type_number_t count;
  mach_exception_data_type_t codes[2];
} dsx_exception_record;

dsx_exception_context *dsx_exception_create(task_t task,
                                            exception_mask_t ignored,
                                            kern_return_t *error);
kern_return_t dsx_exception_destroy(dsx_exception_context *context);
kern_return_t dsx_exception_restore(dsx_exception_context *context);
kern_return_t dsx_exception_receive(dsx_exception_context *context,
                                    dsx_exception_record *record,
                                    boolean_t *received);
kern_return_t dsx_exception_reply(dsx_exception_context *context);
kern_return_t dsx_exception_reject(dsx_exception_context *context);
kern_return_t dsx_exception_resume(dsx_exception_context *context);
void dsx_exception_detached(dsx_exception_context *context);
kern_return_t dsx_exception_update(dsx_exception_context *context, task_t task);
int dsx_ptrace_attach(pid_t process, int *denied);

static inline pid_t dsx_fork(void) {
  return fork();
}

static inline int dsx_ptrace(int request, pid_t process, void *address,
                             int data) {
  return ptrace(request, process, address, data);
}
#endif
#endif

#if defined(__ANDROID__) || defined(__linux__) || defined(__FreeBSD__) ||      \
    defined(__OpenBSD__)
#include <fcntl.h>
DSX_HIDDEN int dsx_open(const char *path, int flags, mode_t mode);
#endif

#if defined(__ANDROID__) || defined(__linux__)
#include <linux/openat2.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/uio.h>

DSX_HIDDEN int dsx_openat2(int directory, const char *path,
                           const struct open_how *how, size_t size);
DSX_HIDDEN uintptr_t dsx_siginfo_address(const siginfo_t *info);
DSX_HIDDEN int dsx_siginfo_sender(const siginfo_t *info);
DSX_HIDDEN long dsx_ptrace(int request, pid_t process, void *address,
                           void *data);
#if defined(__linux__)
DSX_HIDDEN char **dsx_environment(void);
DSX_HIDDEN int dsx_personality(unsigned long persona);
#if !defined(__ANDROID__)
DSX_HIDDEN int dsx_grantpt(int descriptor);
DSX_HIDDEN ssize_t dsx_process_vm_readv(pid_t process,
                                        const struct iovec *local,
                                        size_t locals,
                                        const struct iovec *remote,
                                        size_t remotes, unsigned long flags);
DSX_HIDDEN ssize_t dsx_process_vm_writev(pid_t process,
                                         const struct iovec *local,
                                         size_t locals,
                                         const struct iovec *remote,
                                         size_t remotes, unsigned long flags);
DSX_HIDDEN int dsx_ptsname_r(int descriptor, char *name, size_t capacity);
DSX_HIDDEN int dsx_tgkill(pid_t process, pid_t thread, int signal);
DSX_HIDDEN int dsx_unlockpt(int descriptor);
#endif
#endif
#endif

#if defined(__FreeBSD__) || defined(__OpenBSD__)
DSX_HIDDEN int dsx_ptrace(int request, pid_t process, void *address, int data);
#endif

#if defined(__FreeBSD__)
DSX_HIDDEN int dsx_coredump_supported(void);
DSX_HIDDEN int dsx_coredump(pid_t process, int descriptor);
#endif

#if defined(__ANDROID__)
#include <spawn.h>

DSX_HIDDEN int dsx_spawn_file_actions_init(void *actions);
#endif
