# DebugServerX Architecture

DebugServerX (DSX) implements the GDB Remote Serial Protocol (RSP) in Swift,
serving GDB and LLDB clients and LLDB platform sessions. The `DSX` dynamic
library is the implementation; the `dsx` executable is a command-line entry
point for the same functionality.

The design favors concrete value types, explicit resource ownership, borrowed
byte views, and compile-time native selection. Protocol policy is shared;
operating-system mechanisms and instruction-set details stay behind native
interfaces. Compactness is measured, not inferred from fewer types or lines.

## Source map

Paths below are relative to the repository root. The directories inside
`Sources/DSX` organize one library target, not separate runtime layers or
dynamically loaded components.

| Location | Responsibility |
|---|---|
| `Sources/DebugServerX` | Command-line entry point and subcommands. |
| `Sources/DSXArguments` | Command-line parsing and diagnostics. |
| `Sources/DSX/API` | Public configuration, connections, and embedding API. |
| `Sources/DSX/Server` | Endpoints, daemonization, and client acceptance. |
| `Sources/DSX/Transport` | Concrete socket/stream transport and waiting. |
| `Sources/DSX/GDBRemote` | Framing, negotiation, packets, and replies. |
| `Sources/DSX/Debuggee` | Portable model, session ownership, and breakpoints. |
| `Sources/DSX/Host` | Shared host services and remote file-handle ownership. |
| `Sources/DSX/Formats` | Borrowed ELF, PE, and Mach-O image interpretation. |
| `Sources/DSX/Native` | OS/ISA selection, native services, and ABI policy. |
| `Sources/DSX/Core` | Internal limits and deadline policy. |
| `Sources/DSX/Logging` | Logging state, formatting, and synchronization. |
| `Sources/DSX/Extensions` | Shared byte, string, and collection operations. |
| `Sources/DSXShims` | C interoperability unavailable through normal imports. |
| `Sources/DSXCodeGen` | Build-time packet and register generation. |
| `Definitions`, `Plugins/DefinitionsPlugin` | YAML inputs and build hook. |

Protocol-specific standard-library extensions belong in
`GDBRemote/Extensions`, not the general extensions directory. Likewise,
extensions implementing protocol behavior on `DebugSession` live under
`GDBRemote`; owning a receiver does not move wire policy into the native layer.

## Runtime composition

`DSX.initialize()` initializes host services and the disabled logging path.
`DSX.run(_:logging:to:isolate:daemonize:)` consumes a configuration selecting
GDB, LLDB, or platform-server operation. Embedding does not require the
command-line parser.

The concrete ownership paths are:

```text
DSX.run
  ├─ GDBServer
  │    ├─ Server → ConnectionEndpoint
  │    └─ GDBRemote
  │         ├─ GDBRemoteCore → GDBPacketChannel → ConnectionTransport
  │         └─ DebugSession → NativeDebugControl + portable session resources
  └─ PlatformServer
       ├─ Server → ConnectionEndpoint
       └─ PlatformRemote
            ├─ GDBRemoteCore → GDBPacketChannel → ConnectionTransport
            └─ PlatformSession → FileSystem + PlatformProcesses
```

`Server` owns endpoint establishment, notification, and acceptance.
`GDBServer` and `PlatformServer` provide their distinct lifecycles.
`GDBRemote` and `PlatformRemote` share framing and exchange handling through
`GDBRemoteCore`; neither is a generic mode wrapper.

A debug server accepts a client into a `DebugSession`. Its remote loop
interleaves packets and debuggee events, polling according to native waiting
policy. Closing the remote follows the session's normal/failure cleanup path.

A platform server can accept successive clients. `PlatformProcesses` tracks
launched children and wait handles. Ownership moves into a client session and
back to the server on release, so child tracking survives a client disconnect.
A debugger-launch request starts a child `dsx gdbserver` and returns the port
received through `ChildPort`. Host process launching and child bookkeeping are
separate from debugging the process.

## Transport and framing

`ConnectionEndpoint` represents a listener or connected transport.
`ConnectionTransport` is a closed enum of `SocketChannel` and `Stream`;
there is no byte-channel protocol or runtime backend registry. Native socket
and stream types are selected at compile time. The public connection model
covers descriptors, devices, pipes, TCP, and Unix-domain sockets, including
listening and reverse connections where applicable.

The protocol boundary is deliberately narrow:

1. `GDBPacketChannel` retains incomplete input in a reusable buffer.
2. `GDBPacketFrame` distinguishes control bytes from framed packet payloads
   and checks framing/checksums.
3. Generated classification selects the request encoding and route.
4. Binary payloads are unescaped in place.
5. A handler receives a borrowed `Span<UInt8>` containing the logical payload.

A one-byte payload remains a packet even when its value resembles an
acknowledgement or interrupt. Framing identity is not inferred from length.

Handlers produce logical responses through `GDBPacketWriter`.
`GDBPacketBuffer` retains the output, applies escaping and checksum framing,
and supports retransmission. Neither handlers nor native backends assemble
wire frames. Input and output storage is reused; larger responses can grow
within configured limits.

## Protocol ownership and routing

`GDBRemoteSessionState` owns compatibility, negotiation, process/thread
selection, enumeration, non-stop mode, notification queues, signal delivery
preferences, module invalidation, and reply policy. `CompatibilityMode`
remains a runtime choice: the same binary can serve GDB or LLDB.

`Definitions/Packets.yaml` generates the classifier and `GDBPacketLeaf`.
Routes select existing receivers rather than a registration system:

| Route | Receiver |
|---|---|
| `remote` | `GDBRemoteSessionState.handle` for common protocol requests. |
| `session` | Shared `route` operating on launch configuration and files. |
| `mode` | `DebugSession.handle` or `PlatformSession.handle`. |
| `unsupported` | The protocol's unsupported-packet response. |

Domain handlers live under `GDBRemote/Packets`. Request initializers validate
borrowed payloads; reader and span operations perform common parsing. Reply
operations belong on writers or emitters, such as `writer.emit(info)`.
Negotiation combines protocol support with `DebugCapabilities`; implementing
a classifier entry alone does not justify advertising a feature.

Framing errors, malformed requests, unsupported operations, native failures,
and transport failures remain distinct until the appropriate exchange boundary
maps them to replies or session termination.

## Debuggee state and native events

`Debuggee` models processes, threads, launch configuration, memory, images,
stops, faults, exits, continuations, and output without encoding RSP.
`DebugSession` owns that model together with native control, breakpoints,
files, allocations, saved registers, launch state, and deferred events.

Native control converts ptrace, Mach, or Windows events into
`Debuggee.Event`. Shared session operations maintain model state and resource
ownership. Protocol-layer session extensions apply negotiated event reporting,
signal, fork/exec, and stop-reply policy; `GDBRemote` drives the exchange.
For Linux, common stop interpretation serves both ordinary event consumption
and the all-stop barrier. Decoding a stop does not itself decide to resume it.

Continuation plans resolve thread-specific actions before process actions and
defaults, rejecting conflicting actions before native execution. Fork and exec
handling also reconcile breakpoint ownership and process state; suppressing a
protocol event must not suppress those model transitions.

## Breakpoints, memory, and registers

`BreakpointTable` is concrete. It owns logical sites, handles, activation,
and inheritance; `DebugBreakpointHandle` and `BreakpointSite` carry installation
and native-operation responsibilities. Software breakpoints use native memory
patching, while hardware breakpoints use the selected debug-control backend.
ISA-specific trap instructions and debug-register layouts remain outside RSP.

`DebugSession` owns shared memory operations, search, and allocation cleanup.
`NativeMemory` supplies reads, writes, patches, mappings, and allocation
mechanisms. Reads have a uniform optional mapping argument. Writes and patches
report the committed prefix even on failure, allowing shared code to reconcile
partially completed operations.

`NativeRegisterState` represents a native register snapshot. It exposes
read/write/commit operations and shared `pc`, `fp`, and `set(pc:)` access.
Generated role lookups identify these registers without scanning the complete
register list. `RegisterDescription` and `RegisterConfiguration` hide layout
selection, including Linux/Android ARM64 scalable registers; packet handlers
do not select an ISA-specific register implementation.

`NativeStack` walks the supported native frame chain and enforces progress
and bounds. The GDB writer encodes the resulting frame data. This is frame-chain
inspection, not a general DWARF unwinder.

## Host access versus image interpretation

`Host` describes the machine running DSX. `NativeProcess`, environments,
paths, sockets, streams, and mapped files implement its OS-specific mechanisms.
Shared orchestration operates on those concrete resources rather than
duplicating launch and cleanup policy in each caller.

`FileSystem` owns remote file identifiers, handles, and the selected filesystem
root. `NativeFileSystem` implements actual host operations, path rules, and
native error translation. On Linux/Android, rooted access uses `LinuxFileRoot`;
`LinuxFileLocation` owns a resolved parent for non-following remove/link
operations. Rooted lookup requires `openat2` and fails when that facility is
unavailable rather than silently weakening resolution.

`NativeMappedFile` owns the mapping. `ELFModule`, `PEModule`, and
`MachOModule` borrow its bytes and validate format-specific offsets, records,
architectures, and identifiers. Format parsing is separate from host file
access: reading an ELF file is not inherently a Linux operation.
`Debuggee.Module` connects this interpretation to module queries.

File errors use the common `FileFailure` model, with native translation at the
host boundary and GDB numbering at the protocol boundary. MD5 module checksums
use native libraries, except Android's Swift Crypto implementation; Linux
links an OpenSSL-compatible `libcrypto`. DSX does not maintain its own MD5
compression algorithm.

## Native composition and portability

`Native/Native.swift` rejects unsupported OS/ISA pairs and selects concrete
types: `NativeDebugControl`, `NativeMemory`, `NativeRegisterState`,
`NativeProcess`, `NativeEnvironment`, `NativeFileSystem`, `NativeMappedFile`,
`NativeSocket`, `NativeStream`, and the process/image/library cursors.

`Native/NativeInterfaces.swift` contains one private, uncalled validation
function. Its typed bindings and calls check the selected backend's common
interface during compilation without introducing a production protocol,
existential dispatch, or runtime validation object. Each target checks only
its own selection; this is not a substitute for building other targets.

Within `Native`:

- `Host` contains OS services independent of debuggee control.
- `Debugging` contains OS debugger mechanisms, with ISA subdirectories for
  register storage, breakpoints, and exception details.
- `ABI` contains data-layout and calling conventions, pointer width,
  endianness, and frame policy.

Keep portable policy above these mechanisms. Use pointer-width checks for
pointer layout, architecture checks for instruction/register differences, and
OS checks for facilities or ABI differences. Optional capabilities may be
absent; missing required architecture implementations should fail the build.

`DSXShims` bridges APIs that normal imports cannot expose correctly.
Typed Swift overlays give imported constants and functions their canonical
types. Ordinary system APIs should remain direct Swift calls, not acquire
another shim merely for symmetry.

The current composition selects Windows i386/x86_64/arm64; Linux and Android
i386/x86_64/arm/arm64; Apple x86_64/arm64; and experimental FreeBSD/OpenBSD
x86_64. See the [coverage table](../README.md#platform-coverage) for the public
platform summary. Selection does not imply identical optional capabilities or
that every target was executed in a particular validation run.

## Build-time definitions

`DefinitionsPlugin` runs `DSXCodeGen` for packet classification and register
profiles. Register YAML describes identity, storage, numbering domains, roles,
sets, relationships, platform conditions, and protocol metadata. Generation
produces fixed records, inline arrays, strings, and direct lookups.

Register-set titles serve LLDB display names; explicit groups serve GDB.
Conditional sets preserve their platform gates even when IDs overlap.
Validation rejects unsafe protocol identifiers; display text is XML-escaped
at generation time, with Swift literals escaped separately.

YAML parsing and its Yams dependency remain build-time only. Android's Crypto
dependency, by contrast, implements a runtime checksum facility. Fixed
register metadata needs no YAML parser or dynamic registration in the server;
native runtime configuration still handles variable layouts where required.

## Ownership, logging, and size

`~Copyable` protects unique resources. `borrowing`, `consuming`, and
lifetime-annotated views make access and transfer explicit. Initializers create
validated values; operations live on the receiver whose resource or invariant
they manage. A shorter signature is not sufficient reason to invent a wrapper
or add mutable state.

Buffers, session tables, paths, and metadata can allocate. Allocation avoidance
is a property of individual paths, not a claim that the server is allocation
free. Borrowed spans and reused storage reduce temporary copies.

Logging uses an atomic enablement check, lazy messages, and a mutex around
enabled formatting/output. Native sinks stay separate from log formatting.
Logging failure disables subsequent writes instead of failing the session.

Compact builds optimize for size and omit reflection/debug metadata. Compare
the DLL and executable separately, with the same compiler, dependencies, SDK,
and flags, excluding external runtimes and system libraries. Track code,
read-only/writable data, BSS, unwind, and Swift metadata separately from file
padding. Equal file sizes can conceal content growth. Compare with both the
immediate baseline and the retained low-water reference.

## Extending and validating

For a packet, add its definition, implement a validated request and handler in
the matching protocol domain, route it to the appropriate receiver, and add
malformed-input and compatibility tests. Advertise only complete behavior.

For a backend, select its concrete types in `Native.swift`, satisfy
`NativeInterfaces.swift`, add native mechanisms and the register profile, and
report accurate capabilities. Share policy before adding another OS branch to
a protocol handler.

Tests are separated into executable, library, and generator targets. Focused
tests cover parsing, ownership, lifecycle, and native helpers; LLDB integration
tests exercise cross-layer remote behavior. Foreign-target parsing and
source-derived probes are useful early checks, but do not establish native
type-checking, execution, or binary size. Build and test the affected native
targets, then measure retained production artifacts.
