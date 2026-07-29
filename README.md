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

MD5 checksums use platform libraries on supported hosts. Linux requires an
OpenSSL-compatible `libcrypto` with MD5 support. Android uses Swift Crypto
because the system `libcrypto` is a private API.

## Size

DSX targets optimized library builds below **512 KiB**, excluding the Swift
runtime and system libraries. Exact sizes vary with the platform, toolchain,
SDK, linker, and enabled debugging metadata.

## Build

Use Swift 6.4 or newer, CMake 4.4 or newer, and Ninja. Put the Swift toolchain's
`bin` directory on `PATH`. Linux also needs the OpenSSL development package.

```sh
cmake -S . -B .build/cmake/release -G Ninja \
  --toolchain cmake/toolchains/Swift.cmake \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build .build/cmake/release --parallel
```

The size-optimized CLI and shared library are in `.build/cmake/release/bin`.

Build tests separately to retain reflection and debug information:

```sh
cmake -S . -B .build/cmake/debug -G Ninja \
  --toolchain cmake/toolchains/Swift.cmake \
  -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build .build/cmake/debug --parallel
ctest --test-dir .build/cmake/debug --output-on-failure --no-tests=error
```

SwiftPM builds are also supported.

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
