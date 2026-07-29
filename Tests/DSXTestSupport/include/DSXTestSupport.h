// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#pragma once

#if defined(__linux__)
// Unlike _exit, the raw system call exits only the calling thread.
_Noreturn void dsx_test_exit_thread(int status);
#endif
