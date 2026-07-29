# DebugServerX

DebugServerX (`dsx`) is a compact, cross-platform implementation of the GDB
Remote Serial Protocol written in Swift. It is designed both for standalone use
as a command-line tool and for integration into other applications as an
embeddable library. DSX can run as an LLDB-compatible debug server or platform
server, launch or attach to processes, and expose threads, registers, memory,
modules, breakpoints, and watchpoints to a remote debugger.

## Platform coverage

| Platform | i386 | x86_64 | armv7 | arm64 |
|---|:---:|:---:|:---:|:---:|
| Windows | ✔ | ✔ | — | ✔ |
| Linux | ✔ | ✔ | ✔ | ✔ |
| Android | ✔ | ✔ | ✔ | ✔ |
| macOS | — | ✔ | — | ✔ |
| FreeBSD | — | ◐ | — | — |
| OpenBSD | — | ◐ | — | — |

**✔ Supported** · **◐ Experimental** · **— Not targeted**

Coverage denotes a selected native backend with register and process support.
Individual operating systems may expose different optional debugging
facilities.

## Size

DSX targets optimized library builds below **512 KiB**, excluding the Swift
runtime and system libraries. Exact sizes vary with the platform, toolchain,
SDK, linker, and enabled debugging metadata.

## Embedding

The dynamic `DSX` library exposes a small programmatic API for embedding GDB,
LLDB, or platform-server functionality. Embedders select a connection,
configure launch or attach behavior, and run the server without routing through
the `dsx` command-line interface.

## Use

Launch a program under the debug server:

```console
dsx gdbserver 127.0.0.1:1234 -- ./program argument
```

Attach to an existing process:

```console
dsx gdbserver --attach 1234 127.0.0.1:1234
```

Run an LLDB platform server:

```console
dsx platform --listen 127.0.0.1:1234
```

Run `dsx help <subcommand>` for transport, logging, daemon, and connection
options.
