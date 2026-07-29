// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define DSX_HIDDEN
#else
#define DSX_HIDDEN __attribute__((__visibility__("hidden")))
#endif

#if defined(_WIN32)
#include <Windows.h>

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

DSX_HIDDEN LONG dsx_NtQueryInformationThread(HANDLE thread, int information,
                                             void *output, ULONG size,
                                             ULONG *returned);
DSX_HIDDEN LONG dsx_RtlGetVersion(OSVERSIONINFOW *version);
#else
#include <signal.h>
#include <spawn.h>
#include <sys/ioctl.h>
#include <sys/types.h>

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

static inline int dsx_signal_ignored(int signal) {
  struct sigaction action;
  if (sigaction(signal, NULL, &action) != 0)
    return -1;
  return action.sa_handler == SIG_IGN;
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
kern_return_t dsx_exception_receive(dsx_exception_context *context,
                                    dsx_exception_record *record,
                                    boolean_t *received);
kern_return_t dsx_exception_reply(dsx_exception_context *context);
kern_return_t dsx_exception_reject(dsx_exception_context *context);
kern_return_t dsx_exception_resume(dsx_exception_context *context);
kern_return_t dsx_exception_update(dsx_exception_context *context,
                                   task_t task);
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
#include <signal.h>
#include <sys/uio.h>

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
                                        size_t remotes,
                                        unsigned long flags);
DSX_HIDDEN ssize_t dsx_process_vm_writev(pid_t process,
                                         const struct iovec *local,
                                         size_t locals,
                                         const struct iovec *remote,
                                         size_t remotes,
                                         unsigned long flags);
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
