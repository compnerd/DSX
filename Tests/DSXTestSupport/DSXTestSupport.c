// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#include "DSXTestSupport.h"

#if defined(__linux__)
#include <sys/syscall.h>
#include <unistd.h>

_Noreturn void dsx_test_exit_thread(int status) {
  syscall(SYS_exit, status);
  __builtin_unreachable();
}
#endif
