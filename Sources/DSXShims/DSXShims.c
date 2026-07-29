// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "DSXShims.h"

#if defined(__APPLE__)
#include <errno.h>
#include <mach/mig.h>
#include <mach/ndr.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t dsx_attach_lock = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local sigjmp_buf dsx_attach_jump;
static _Thread_local volatile sig_atomic_t dsx_attach_armed;
static struct sigaction dsx_attach_previous;

static void dsx_attach_signal(int signal) {
  if (dsx_attach_armed) {
    dsx_attach_armed = 0;
    siglongjmp(dsx_attach_jump, 1);
  }
  sigaction(SIGSEGV, &dsx_attach_previous, NULL);
  raise(signal);
}

int dsx_ptrace_attach(pid_t process, int *denied) {
  *denied = 0;
  int status = pthread_mutex_lock(&dsx_attach_lock);
  if (status != 0) {
    errno = status;
    return -1;
  }

  struct sigaction action = {0};
  action.sa_handler = dsx_attach_signal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_NODEFER;
  if (sigaction(SIGSEGV, &action, &dsx_attach_previous) != 0) {
    int error = errno;
    pthread_mutex_unlock(&dsx_attach_lock);
    errno = error;
    return -1;
  }

  int result;
  int error;
  if (sigsetjmp(dsx_attach_jump, 1) == 0) {
    dsx_attach_armed = 1;
    result = ptrace(PT_ATTACHEXC, process, NULL, 0);
    error = errno;
    dsx_attach_armed = 0;
  } else {
    *denied = 1;
    result = -1;
    error = EPERM;
  }

  sigaction(SIGSEGV, &dsx_attach_previous, NULL);
  pthread_mutex_unlock(&dsx_attach_lock);
  errno = error;
  return result;
}

typedef union dsx_exception_message {
  mach_msg_header_t header;
  uint8_t bytes[1024];
} dsx_exception_message;

#pragma pack(push, 4)
typedef struct dsx_exception_request {
  mach_msg_header_t header;
  mach_msg_body_t body;
  mach_msg_port_descriptor_t thread;
  mach_msg_port_descriptor_t task;
  NDR_record_t ndr;
  exception_type_t type;
  mach_msg_type_number_t count;
  int64_t codes[2];
} dsx_exception_request;

typedef struct dsx_exception_response {
  mach_msg_header_t header;
  NDR_record_t ndr;
  kern_return_t status;
} dsx_exception_response;
#pragma pack(pop)

typedef struct dsx_exception_entry {
  dsx_exception_message request;
  dsx_exception_message reply;
  dsx_exception_record record;
} dsx_exception_entry;

struct dsx_exception_context {
  task_t task;
  mach_port_t port;
  exception_mask_t masks[EXC_TYPES_COUNT];
  mach_port_t ports[EXC_TYPES_COUNT];
  exception_behavior_t behaviors[EXC_TYPES_COUNT];
  thread_state_flavor_t flavors[EXC_TYPES_COUNT];
  mach_msg_type_number_t saved;
  dsx_exception_entry *entries;
  size_t count;
  size_t capacity;
  boolean_t retained;
  boolean_t suspended;
};

static void dsx_exception_release(dsx_exception_record *record) {
  if (record->thread != MACH_PORT_NULL)
    mach_port_deallocate(mach_task_self(), record->thread);
  if (record->task != MACH_PORT_NULL)
    mach_port_deallocate(mach_task_self(), record->task);
  memset(record, 0, sizeof(*record));
}

static kern_return_t dsx_exception_reserve(dsx_exception_context *context) {
  if (context->count < context->capacity)
    return KERN_SUCCESS;
  size_t capacity = context->capacity == 0 ? 4 : context->capacity * 2;
  if (capacity < context->capacity ||
      capacity > SIZE_MAX / sizeof(*context->entries))
    return KERN_RESOURCE_SHORTAGE;
  dsx_exception_entry *entries =
      realloc(context->entries, capacity * sizeof(*entries));
  if (entries == NULL)
    return KERN_RESOURCE_SHORTAGE;
  context->entries = entries;
  context->capacity = capacity;
  return KERN_SUCCESS;
}

dsx_exception_context *dsx_exception_create(task_t task,
                                            exception_mask_t ignored,
                                            kern_return_t *error) {
  dsx_exception_context *context = calloc(1, sizeof(*context));
  if (context == NULL) {
    *error = KERN_RESOURCE_SHORTAGE;
    return NULL;
  }
  context->task = task;
  *error = mach_port_mod_refs(mach_task_self(), task, MACH_PORT_RIGHT_SEND, 1);
  if (*error != KERN_SUCCESS)
    goto failed;
  context->retained = TRUE;
  context->saved = EXC_TYPES_COUNT;
  *error = task_get_exception_ports(task, EXC_MASK_ALL, context->masks,
                                    &context->saved, context->ports,
                                    context->behaviors, context->flavors);
  if (*error != KERN_SUCCESS)
    goto failed;
  *error = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                              &context->port);
  if (*error != KERN_SUCCESS)
    goto failed;
  *error = mach_port_insert_right(mach_task_self(), context->port,
                                  context->port, MACH_MSG_TYPE_MAKE_SEND);
  if (*error != KERN_SUCCESS)
    goto failed;
  exception_mask_t handled = EXC_MASK_ALL & ~ignored;
  *error = task_set_exception_ports(task, handled, context->port,
                                    EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES,
                                    THREAD_STATE_NONE);
  if (*error != KERN_SUCCESS)
    goto failed;
  return context;

failed:
  dsx_exception_destroy(context);
  return NULL;
}

kern_return_t dsx_exception_update(dsx_exception_context *context,
                                   task_t task) {
  kern_return_t status =
      mach_port_mod_refs(mach_task_self(), task, MACH_PORT_RIGHT_SEND, 1);
  if (status != KERN_SUCCESS)
    return status;
  if (context->retained)
    mach_port_mod_refs(mach_task_self(), context->task,
                       MACH_PORT_RIGHT_SEND, -1);
  context->task = task;
  context->retained = TRUE;
  boolean_t pending = FALSE;
  for (size_t index = 0; index < context->count; ++index) {
    if (context->entries[index].record.task == task) {
      pending = TRUE;
      break;
    }
  }
  if (pending && !context->suspended) {
    status = task_suspend(task);
    if (status != KERN_SUCCESS)
      return status;
    context->suspended = TRUE;
  }
  return KERN_SUCCESS;
}

kern_return_t dsx_exception_destroy(dsx_exception_context *context) {
  if (context == NULL)
    return KERN_SUCCESS;
  kern_return_t result = KERN_SUCCESS;
  for (mach_msg_type_number_t index = 0; index < context->saved; ++index) {
    kern_return_t status = task_set_exception_ports(
        context->task, context->masks[index], context->ports[index],
        context->behaviors[index], context->flavors[index]);
    if (result == KERN_SUCCESS)
      result = status;
  }
  for (;;) {
    if (context->count > 0) {
      kern_return_t status = dsx_exception_reply(context);
      if (result == KERN_SUCCESS)
        result = status;
      if (status != KERN_SUCCESS)
        break;
    }
    boolean_t received = FALSE;
    dsx_exception_record record;
    kern_return_t status =
        dsx_exception_receive(context, &record, &received);
    if (status != KERN_SUCCESS) {
      if (result == KERN_SUCCESS)
        result = status;
      break;
    }
    if (!received)
      break;
  }
  if (context->suspended) {
    kern_return_t status = dsx_exception_resume(context);
    if (result == KERN_SUCCESS)
      result = status;
  }
  if (context->port != MACH_PORT_NULL) {
    mach_port_mod_refs(mach_task_self(), context->port,
                       MACH_PORT_RIGHT_SEND, -1);
    mach_port_mod_refs(mach_task_self(), context->port,
                       MACH_PORT_RIGHT_RECEIVE, -1);
  }
  if (context->retained)
    mach_port_mod_refs(mach_task_self(), context->task,
                       MACH_PORT_RIGHT_SEND, -1);
  free(context->entries);
  free(context);
  return result;
}

kern_return_t dsx_exception_receive(dsx_exception_context *context,
                                    dsx_exception_record *record,
                                    boolean_t *received) {
  *received = FALSE;
  dsx_exception_entry entry = {0};
  mach_msg_timeout_t timeout = context->count == 0 ? 0 : 1;
  kern_return_t status = mach_msg(
      &entry.request.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
      sizeof(entry.request), context->port, timeout, MACH_PORT_NULL);
  if (status == MACH_RCV_TIMED_OUT)
    return KERN_SUCCESS;
  if (status != KERN_SUCCESS)
    return status;
  dsx_exception_request *request =
      (dsx_exception_request *)&entry.request;
  if (request->header.msgh_id != 2405 ||
      !(request->header.msgh_bits & MACH_MSGH_BITS_COMPLEX) ||
      request->body.msgh_descriptor_count != 2 || request->count > 2) {
    mach_msg_destroy(&entry.request.header);
    return MIG_BAD_ID;
  }
  entry.record.thread = request->thread.name;
  entry.record.task = request->task.name;
  entry.record.type = request->type;
  entry.record.count = request->count;
  for (mach_msg_type_number_t index = 0; index < request->count; ++index)
    entry.record.codes[index] = request->codes[index];
  dsx_exception_response *reply = (dsx_exception_response *)&entry.reply;
  reply->header.msgh_bits =
      MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request->header.msgh_bits), 0);
  reply->header.msgh_size = sizeof(*reply);
  reply->header.msgh_remote_port = request->header.msgh_remote_port;
  reply->header.msgh_local_port = MACH_PORT_NULL;
  reply->header.msgh_id = request->header.msgh_id + 100;
  reply->ndr = NDR_record;
  reply->status = KERN_SUCCESS;
  status = dsx_exception_reserve(context);
  if (status != KERN_SUCCESS) {
    reply->status = KERN_RESOURCE_SHORTAGE;
    mach_msg(&entry.reply.header, MACH_SEND_MSG | MACH_SEND_INTERRUPT,
             entry.reply.header.msgh_size, 0, MACH_PORT_NULL,
             MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    dsx_exception_release(&entry.record);
    return status;
  }
  context->entries[context->count++] = entry;
  if (entry.record.task == context->task && !context->suspended) {
    status = task_suspend(context->task);
    if (status != KERN_SUCCESS)
      return status;
    context->suspended = TRUE;
  }
  *record = entry.record;
  *received = TRUE;
  return KERN_SUCCESS;
}

kern_return_t dsx_exception_reply(dsx_exception_context *context) {
  while (context->count > 0) {
    dsx_exception_entry *entry = &context->entries[0];
    kern_return_t status = mach_msg(
        &entry->reply.header, MACH_SEND_MSG | MACH_SEND_INTERRUPT,
        entry->reply.header.msgh_size, 0, MACH_PORT_NULL,
        MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (status != KERN_SUCCESS)
      return status;
    dsx_exception_release(&entry->record);
    --context->count;
    if (context->count > 0)
      memmove(entry, entry + 1, context->count * sizeof(*entry));
  }
  return KERN_SUCCESS;
}

kern_return_t dsx_exception_reject(dsx_exception_context *context) {
  if (context->count == 0)
    return KERN_SUCCESS;
  dsx_exception_entry *entry = &context->entries[context->count - 1];
  dsx_exception_response *reply = (dsx_exception_response *)&entry->reply;
  reply->status = KERN_FAILURE;
  kern_return_t status = mach_msg(
      &entry->reply.header, MACH_SEND_MSG | MACH_SEND_INTERRUPT,
      entry->reply.header.msgh_size, 0, MACH_PORT_NULL,
      MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (status == KERN_SUCCESS) {
    dsx_exception_release(&entry->record);
    --context->count;
  }
  return status;
}

kern_return_t dsx_exception_resume(dsx_exception_context *context) {
  if (!context->suspended)
    return KERN_SUCCESS;
  kern_return_t status = task_resume(context->task);
  if (status == KERN_SUCCESS)
    context->suspended = FALSE;
  return status;
}
#endif

#if defined(_WIN32)
#include <winternl.h>

NTSYSAPI NTSTATUS NTAPI RtlGetVersion(PRTL_OSVERSIONINFOW version);

LONG dsx_NtQueryInformationThread(HANDLE thread, int information, void *output,
                                  ULONG size, ULONG *returned) {
  return NtQueryInformationThread(thread, (THREADINFOCLASS)information, output,
                                  size, returned);
}

LONG dsx_RtlGetVersion(OSVERSIONINFOW *version) {
  version->dwOSVersionInfoSize = sizeof(*version);
  return RtlGetVersion((PRTL_OSVERSIONINFOW)version);
}
#endif

#if defined(__ANDROID__) || defined(__linux__) || defined(__FreeBSD__) ||      \
    defined(__OpenBSD__)
#include <fcntl.h>
#include <unistd.h>

int dsx_open(const char *path, int flags, mode_t mode) {
  return open(path, flags, mode);
}
#endif

#if defined(__ANDROID__) || defined(__linux__)
#include <stdlib.h>
#include <sys/ptrace.h>
#if defined(__linux__)
#include <sys/personality.h>
#include <sys/syscall.h>
#endif

uintptr_t dsx_siginfo_address(const siginfo_t *info) {
  return (uintptr_t)info->si_addr;
}

int dsx_siginfo_sender(const siginfo_t *info) {
  return (int)info->si_pid;
}

long dsx_ptrace(int request, pid_t process, void *address, void *data) {
  return ptrace(request, process, address, data);
}

#if defined(__linux__)
char **dsx_environment(void) {
  return environ;
}

int dsx_personality(unsigned long persona) {
  return personality(persona);
}

#if !defined(__ANDROID__)
int dsx_grantpt(int descriptor) {
  return grantpt(descriptor);
}

ssize_t dsx_process_vm_readv(pid_t process, const struct iovec *local,
                             size_t locals, const struct iovec *remote,
                             size_t remotes, unsigned long flags) {
  return process_vm_readv(process, local, locals, remote, remotes, flags);
}

ssize_t dsx_process_vm_writev(pid_t process, const struct iovec *local,
                              size_t locals, const struct iovec *remote,
                              size_t remotes, unsigned long flags) {
  return process_vm_writev(process, local, locals, remote, remotes, flags);
}

int dsx_ptsname_r(int descriptor, char *name, size_t capacity) {
  return ptsname_r(descriptor, name, capacity);
}

int dsx_tgkill(pid_t process, pid_t thread, int signal) {
  return (int)syscall(SYS_tgkill, process, thread, signal);
}

int dsx_unlockpt(int descriptor) {
  return unlockpt(descriptor);
}
#endif
#endif
#endif

#if defined(__FreeBSD__) || defined(__OpenBSD__)
#include <sys/ptrace.h>

int dsx_ptrace(int request, pid_t process, void *address, int data) {
  return ptrace(request, process, address, data);
}
#endif

#if defined(__FreeBSD__)
#include <errno.h>

int dsx_coredump_supported(void) {
#if defined(PT_COREDUMP)
  return 1;
#else
  return 0;
#endif
}

int dsx_coredump(pid_t process, int descriptor) {
#if defined(PT_COREDUMP)
  struct ptrace_coredump dump = {
      .pc_fd = descriptor,
  };
  return ptrace(PT_COREDUMP, process, &dump, sizeof(dump));
#else
  errno = ENOTSUP;
  return -1;
#endif
}
#endif

#if defined(__ANDROID__)
int dsx_spawn_file_actions_init(void *actions) {
  return posix_spawn_file_actions_init((posix_spawn_file_actions_t *)actions);
}
#endif

#if !defined(_WIN32) && !defined(__APPLE__)
#include <errno.h>
#include <unistd.h>
#if defined(__FreeBSD__)
#include <sys/param.h>
#endif

int dsx_pipe2(int descriptors[2], int flags) {
  return pipe2(descriptors, flags);
}

int dsx_spawn_chdir(void *raw, const char *path) {
#if (defined(__ANDROID__) && __ANDROID_API__ >= 34) ||                     \
    (defined(__linux__) && !defined(__ANDROID__)) ||                      \
    (defined(__FreeBSD__) && __FreeBSD_version >= 1301000)
  posix_spawn_file_actions_t *actions = raw;
  return posix_spawn_file_actions_addchdir_np(actions, path);
#else
  (void)raw;
  (void)path;
  return ENOTSUP;
#endif
}
#endif
