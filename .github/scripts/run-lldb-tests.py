#!/usr/bin/env python3

import argparse
import concurrent.futures
import json
import math
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import lldb_results

kAndroidRuntime = "/data/local/tmp/dsx-runtime"


def tool(name: str, directory: pathlib.Path | None = None) -> str:
    path = shutil.which(name, path=str(directory) if directory else None)
    if path:
        if sys.platform == "win32" and path.lower().endswith(".exe"):
            return path[:-4] + ".exe"
        return path
    raise RuntimeError(f"unable to locate {name}")


def python_command(lldb: str, script: str, executable: str,
                   timeout: float = 0) -> list[str]:
    command = [executable]
    if sys.platform == "win32":
        directories = [pathlib.Path(lldb).resolve().parent]
        if os.environ.get("OPENSSL_DIR"):
            directories.append(pathlib.Path(os.environ["OPENSSL_DIR"]) / "bin")
        for value in os.environ.get("PATH", "").split(os.pathsep):
            directory = pathlib.Path(value)
            if (directory / "swiftCore.dll").is_file():
                directories.append(directory)
        paths = os.pathsep.join(map(str, dict.fromkeys(directories)))
        bootstrap = (
            "import os,runpy,sys;"
            "handles=[os.add_dll_directory(path) for path in "
            "sys.argv.pop(1).split(os.pathsep) if path];"
            "script=sys.argv.pop(1);"
            "sys.argv[0]=script;"
            "sys.path.insert(0,os.path.dirname(os.path.abspath(script)));"
            "runpy.run_path(script,run_name='__main__')"
        )
        command.extend(("-c", bootstrap, paths))
    elif sys.platform == "darwin":
        # Use faulthandler's watchdog, as dotest does on Windows. Unlike an
        # external signal, this also works when native code blocks signals.
        # Capture before the deadline without changing the test's outcome.
        bootstrap = (
            "import faulthandler,os,runpy,sys;"
            "timeout=float(sys.argv.pop(1));"
            "faulthandler.dump_traceback_later(max(1,timeout*.9),exit=False) "
            "if timeout>0 else None;"
            "script=sys.argv.pop(1);"
            "sys.argv[0]=script;"
            "sys.path.insert(0,os.path.dirname(os.path.abspath(script)));"
            "runpy.run_path(script,run_name='__main__')"
        )
        command.extend(("-c", bootstrap, str(timeout)))
    command.append(str(script))
    return command


def wait(server: subprocess.Popen[bytes], log: pathlib.Path,
         timeout: float) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = server.poll()
        if status is not None:
            detail = log.read_text(errors="replace")
            raise RuntimeError(f"DSX exited with status {status}:\n{detail}")
        if log.is_file():
            match = re.search(r"^Listening on port ([0-9]+)\r?\n",
                              log.read_text(errors="replace"), re.MULTILINE)
            if match and 0 < int(match[1]) <= 65535:
                return int(match[1])
        time.sleep(0.1)
    raise RuntimeError("DSX did not establish its listening endpoint")


def android_target(architecture: str) -> tuple[str, str]:
    targets = {
        "arm": ("armv7a-linux-androideabi", "arm-linux-androideabi"),
        "arm64": ("aarch64-linux-android", "aarch64-linux-android"),
        "i386": ("i686-linux-android", "i686-linux-android"),
        "x86_64": ("x86_64-linux-android", "x86_64-linux-android"),
    }
    target = targets.get(architecture)
    if target is None:
        raise RuntimeError(f"unsupported Android architecture: {architecture}")
    return target


def android_compiler(architecture: str, api: int) -> pathlib.Path:
    ndk = os.environ.get("ANDROID_NDK_HOME") or os.environ.get(
        "ANDROID_NDK_LATEST_HOME")
    if not ndk:
        raise RuntimeError("unable to locate the Android NDK")
    target, _ = android_target(architecture)
    pattern = f"*/bin/{target}{api}-clang"
    matches = list((pathlib.Path(ndk) / "toolchains" / "llvm" /
                    "prebuilt").glob(pattern))
    if len(matches) != 1:
        raise RuntimeError(f"unable to locate Android compiler: {pattern}")
    return matches[0]


def android_runtimes(compiler: pathlib.Path,
                     architecture: str) -> list[pathlib.Path]:
    _, target = android_target(architecture)
    runtime = (compiler.parent.parent / "sysroot" / "usr" / "lib" / target /
               "libc++_shared.so")
    if not runtime.is_file():
        raise RuntimeError(f"unable to locate Android C++ runtime: {runtime}")
    cpu = target.partition("-")[0]
    name = f"libclang_rt.asan-{cpu}-android.so"
    command = [str(compiler), f"--print-file-name={name}"]
    path = subprocess.check_output(command, text=True, timeout=30).strip()
    sanitizer = pathlib.Path(path)
    if not sanitizer.is_absolute() or not sanitizer.is_file():
        raise RuntimeError(f"unable to locate Android ASan runtime: {sanitizer}")
    return [runtime, sanitizer]


def configuration(arguments: argparse.Namespace, root: pathlib.Path):
    # Supply relocated build settings; LLDB owns the command and environment.
    source = arguments.source.resolve()
    sys.path.insert(0, str(source / "llvm/utils/lit"))
    from lit.LitConfig import LitConfig
    from lit.TestingConfig import TestingConfig

    settings = LitConfig("dsx-lldb", [], "note", False, False, [], False,
                         False, sys.platform == "win32", "lexical", {})
    config = TestingConfig.fromdefaults(settings)
    config.environment = os.environ.copy()
    sdk = config.environment.get("SDKROOT")
    if sys.platform == "win32" and sdk:
        config.environment["SDKROOT"] = sdk.rstrip("/\\")
    config.lldb_src_root = str(source / "lldb")
    config.lldb_obj_root = str(root)
    config.lldb_build_directory = str(root / "lldb-test-build.noindex")
    config.lldb_executable = tool("lldb", arguments.tools.resolve())
    config.llvm_tools_dir = str(arguments.tools.resolve())
    config.llvm_shlib_dir = str(pathlib.Path(config.lldb_executable).parent)
    config.python_executable = sys.executable
    config.python_root_dir = sys.base_prefix
    config.lldb_enable_python = True
    config.cmake_build_type = "Debug"
    config.test_arch = arguments.arch
    config.test_triple = arguments.triple
    if arguments.platform == "remote-windows" and arguments.arch == "i386":
        # dotest derives its architecture from the triple, not test_arch.
        # Use LLDB's i386 spelling for Win32 fixtures (Clang selects the same
        # CPU and ABI as i686), including upstream architecture decorators.
        config.test_triple = "i386-" + arguments.triple.partition("-")[2]
    if arguments.android:
        target, directory = android_target(arguments.arch)
        config.test_triple = f"{target}{arguments.android_api}"
        # A runpath survives tests replacing LD_LIBRARY_PATH. Do not export
        # LDFLAGS: recursive make would inherit the parent fixture's libraries
        # while building those libraries' prerequisites.
        config.environment["LLDB_ANDROID_RUNTIME"] = kAndroidRuntime
        # Android.rules needs an unversioned library directory, but Clang
        # must retain the API level in its target for availability checks.
        flags = config.environment.get("MAKEFLAGS", "")
        config.environment["MAKEFLAGS"] = (
            f"{flags} API_LEVEL={arguments.android_api} ARCH_DIR={directory}"
        ).strip()
    compiler = arguments.compiler
    if compiler is None:
        if arguments.android:
            compiler = android_compiler(arguments.arch, arguments.android_api)
        elif sys.platform == "darwin":
            # Objective-C fixtures use Apple-only language extensions.
            # This also selects Xcode for tests invoking `xcrun clang`.
            toolchain = "com.apple.dt.toolchain.XcodeDefault"
            config.environment["TOOLCHAINS"] = toolchain
            compiler = pathlib.Path(subprocess.check_output(
                ["xcrun", "--find", "clang"], text=True,
                env=config.environment).strip())
        else:
            compiler = pathlib.Path(tool("clang", arguments.tools.resolve()))
    # Preserve clang/clang-cl spelling for LLDB's C++ compiler selection.
    config.test_compiler = str(compiler.absolute())
    config.make = shutil.which("gmake") or tool("make")
    config.lldb_platform_working_dir = (arguments.working_directory or
                                       ("/data/local/tmp/dsx-lldb"
                                        if arguments.android else
                                        str(root / "platform")))
    options = ["-v", "--platform-name", arguments.platform,
               "--out-of-tree-debugserver"]
    if arguments.trace:
        # Emit dotest's commands as they run, including fixture builds. Its
        # in-memory session otherwise disappears when a module times out.
        options.append("-t")
        # Step logging formats frames inside RunThreadPlan. On Darwin that
        # can evaluate an Objective-C expression and deadlock on reentry.
        # Packet logging retains the protocol evidence without executing code.
        options.extend(("--channel", "gdb-remote packets"))
        if arguments.android:
            # Distinguish remote module enumeration from client-side loading.
            options.extend(("--channel", "lldb dyld"))
    if arguments.android:
        # LLDB's embedded Clang does not inherit the NDK driver's
        # architecture-specific system include directory.
        _, directory = android_target(arguments.arch)
        headers = compiler.parent.parent / "sysroot/usr/include" / directory
        options.extend(("--setting",
                        f'target.clang-module-search-paths="{headers}"'))
    if arguments.exclusions:
        options.extend(("--excluded", str(arguments.exclusions.resolve())))
    config.dotest_user_args_str = ";".join(options)
    settings.load_config(config, str(source / "lldb/test/API/lit.cfg.py"))
    return settings, config


def tests(arguments, settings, config):
    from lit.Test import TestSuite
    from lit.discovery import getTestsInSuite

    sys.path.insert(0, str(arguments.source.resolve() / "lldb/packages/Python"))
    from lldbsuite.test import configuration, dotest

    configuration.skip_tests = None
    if arguments.exclusions:
        dotest.parseExclusion(str(arguments.exclusions.resolve()))
    skipped = [re.compile(pattern)
               for pattern in configuration.skip_tests or []]
    api = pathlib.Path(config.test_source_root)
    suite = TestSuite(config.name, str(api), config.test_exec_root, config)
    visited = set()
    for specification in arguments.tests.split(","):
        path = api / specification
        if not path.exists():
            raise RuntimeError(f"unable to locate LLDB tests: {path}")
        relative = path.relative_to(api).parts
        candidates = getTestsInSuite(suite, relative, settings, {}, {})
        for test in sorted(candidates, key=lambda test: test.getSourcePath()):
            candidate = pathlib.Path(test.getSourcePath())
            if any(pattern.search(candidate.name) for pattern in skipped):
                continue
            resolved = candidate.resolve()
            if resolved in visited:
                continue
            visited.add(resolved)
            yield test


def wait_android(adb: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    subprocess.run([adb, "wait-for-device"], check=True,
                   timeout=max(0.1, deadline - time.monotonic()))
    while time.monotonic() < deadline:
        result = subprocess.run([adb, "shell", "getprop", "sys.boot_completed"],
                                capture_output=True, text=True,
                                timeout=max(0.1, deadline - time.monotonic()))
        if result.returncode == 0 and result.stdout.strip() == "1":
            return
        time.sleep(2)
    raise RuntimeError("Android emulator did not finish booting")


def android_server(adb: str, arguments: argparse.Namespace,
                   compiler: pathlib.Path, environment: dict[str, str],
                   log: pathlib.Path, deploy: bool = True) -> tuple[
                       subprocess.Popen[bytes], str]:
    remote = "/data/local/tmp/dsx"
    directory = arguments.working_directory or "/data/local/tmp/dsx-lldb"
    if deploy:
        runtimes = android_runtimes(compiler, arguments.arch)
        subprocess.run([adb, "shell", "mkdir", "-p", directory,
                        kAndroidRuntime], check=True, timeout=30)
        subprocess.run([adb, "push", str(arguments.dsx.resolve()), remote],
                       check=True, timeout=60)
        subprocess.run([adb, "shell", "chmod", "755", remote], check=True,
                       timeout=30)
        subprocess.run([adb, "push", *map(str, runtimes), kAndroidRuntime],
                       check=True, timeout=60)
    parent = shlex.quote(str(pathlib.PurePosixPath(remote).parent))
    command = ("echo DSX_BOOT:$(cat /proc/sys/kernel/random/boot_id); "
               f"echo DSX_PID:$$; exec {shlex.quote(remote)} platform --server "
               "--listen 127.0.0.1:0")
    if arguments.trace:
        command += " --log-channels all,trace"
    # Retain the remote exit status independently of ADB's transport status.
    # Keep the child in the foreground so it inherits normal signal handling.
    command = (f"cd {parent} && export LD_LIBRARY_PATH={kAndroidRuntime} && "
               f"sh -c {shlex.quote(command)}; status=$?; "
               'echo DSX_EXIT:$status; exit "$status"')
    with log.open("wb") as output:
        server = subprocess.Popen([adb, "shell", command], stdout=output,
                                  stderr=output, env=environment,
                                  start_new_session=sys.platform != "win32")
    return server, directory


class Server:
    """Own the server across modules, retaining every recovery generation."""

    def __init__(self, arguments, root, compiler, environment):
        self.arguments = arguments
        self.root = root
        self.compiler = compiler
        self.environment = environment
        self.url = arguments.server_url
        self.process = None
        self.adb = None
        self.generation = 0
        self.log = root / "server.log"
        if arguments.android:
            if self.url:
                raise RuntimeError("--android and --server-url cannot combine")
            self.adb = tool("adb")
            wait_android(self.adb, arguments.android_boot_timeout)

    @property
    def owned(self):
        return self.arguments.server_url is None

    def start(self):
        if not self.owned:
            return
        if self.adb:
            self.process, directory = android_server(
                self.adb, self.arguments, self.compiler, self.environment,
                self.log, deploy=self.generation == 0)
            self.arguments.working_directory = directory
        else:
            command = [str(self.arguments.dsx.resolve()), "platform",
                       "--server", "--listen", "127.0.0.1:0"]
            if self.arguments.trace:
                command.extend(("--log-channels", "all,trace"))
            session = sys.platform != "win32"
            with self.log.open("wb") as output:
                self.process = subprocess.Popen(command, stdout=output,
                                                stderr=output,
                                                env=self.environment,
                                                start_new_session=session)
        # Allocate on the server's host and retain the bound socket. Probing a
        # local port cannot reserve it, especially in a different network space.
        port = wait(self.process, self.log, self.arguments.server_timeout)
        # remote-android uses the hostname as an ADB device selector. localhost
        # selects the default device; LLDB owns the connection's forwarding.
        host = "localhost" if self.adb else "127.0.0.1"
        self.url = f"connect://{host}:{port}"

    def stop(self, *, strict=False):
        if not self.process:
            return
        try:
            if self.adb:
                text = self.log.read_text(errors="replace").replace("\r", "")
                pid = re.search(r"^DSX_PID:(\d+)$", text, re.MULTILINE)
                if pid:
                    # The adb client PID is not the remote server PID.
                    # A reboot can reuse the PID. Only kill our executable.
                    command = (f'if [ "$(readlink /proc/{pid[1]}/exe)" = '
                               f'"/data/local/tmp/dsx" ]; then '
                               f"kill -KILL {pid[1]} 2>/dev/null || "
                               f"! kill -0 {pid[1]} 2>/dev/null; fi")
                    subprocess.run([self.adb, "shell", command], check=True,
                                   timeout=15)
        except (subprocess.CalledProcessError,
                subprocess.TimeoutExpired) as error:
            print(f"Android server cleanup failed: {error}", file=sys.stderr)
            if strict:
                raise
        finally:
            terminate(self.process)
            self.process = None

    def probe(self, lldb, log=None):
        command = [lldb, "--batch", "--no-lldbinit",
                   "-o", f"platform select {self.arguments.platform}",
                   "-o", f"platform connect {self.url}"]
        # Darwin's platform service can respond while debuggee launch is wedged.
        # Exercise launch/stop/kill before accepting recovery on that platform.
        lifecycle = self.owned and self.arguments.platform == "remote-macosx"
        if lifecycle:
            executable = shlex.quote(self.arguments.dsx.resolve().as_posix())
            directory = self.root / "platform"
            directory.mkdir(exist_ok=True)
            remote = shlex.quote((directory / self.arguments.dsx.name).as_posix())
            target = f"target create {executable} --remote-file {remote}"
            working = f"platform settings -w {shlex.quote(str(directory))}"
            timeout = math.ceil(self.arguments.server_timeout)
            # Kill can return before LLDB publishes the exit. Subscribe first
            # so either an already queued or a later exit validates the probe.
            command.extend(("-o", working,
                            "-o", target,
                            "-o", "process launch --stop-at-entry --no-stdio "
                            "-- version",
                            "-o", "script p = lldb.debugger.GetSelectedTarget()"
                            ".GetProcess(); listener = lldb.SBListener("
                            "'dsx.lifecycle'); p.GetBroadcaster().AddListener("
                            "listener, "
                            "lldb.SBProcess.eBroadcastBitStateChanged)",
                            "-o", "process kill",
                            "-o", "script event = lldb.SBEvent(); "
                            "print('DSX_LIFECYCLE_OK' if "
                            f"listener.WaitForEvent({timeout}, "
                            "event) and "
                            "lldb.SBProcess.GetStateFromEvent(event) "
                            "== lldb.eStateExited and "
                            "p.GetExitDescription() == 'killed' else "
                            "'DSX_LIFECYCLE_FAILED')"))
        command.extend(("-o", "platform disconnect"))
        log = log or self.root / f"probe-{self.generation:03d}.log"
        status, timedout = execute(command, self.environment, log,
                                   self.arguments.server_timeout, self)
        if status != 0 or timedout:
            raise RuntimeError(f"LLDB platform probe failed (see {log.name})")
        if lifecycle and "DSX_LIFECYCLE_OK" not in log.read_text(
                errors="replace").splitlines():
            raise RuntimeError(f"LLDB lifecycle probe failed (see {log.name})")

    def recover(self, lldb):
        if not self.owned:
            raise RuntimeError("cannot restart an external server")
        if self.adb:
            wait_android(self.adb, self.arguments.android_boot_timeout)
        self.stop(strict=True)
        self.generation += 1
        self.log = self.root / f"server-{self.generation:03d}.log"
        self.start()
        self.probe(lldb)

    def diagnose(self, path):
        if not self.adb:
            return
        # An adb shell status is not the debug server's termination reason.
        # Preserve crash/low-memory evidence before recovery kills survivors.
        # Bound both output and elapsed time even when the device is wedged.
        started = time.monotonic()
        commands = [
            ["shell", "cat /proc/sys/kernel/random/boot_id /proc/uptime; "
             "dmesg | tail -n 120"],
            ["logcat", "-b", "crash", "-d", "-t", "200"],
            # lmkd uses the lowmemorykiller tag in Android's main buffer.
            ["logcat", "-b", "main", "-b", "system", "-d", "-t", "200",
             "ActivityManager:I", "lowmemorykiller:I", "adbd:I", "*:S"],
            ["shell", "ps", "-A", "-o", "PID,PPID,STAT,WCHAN,NAME"],
        ]
        log = path.with_suffix(".android.log")
        with log.open("w", encoding="utf-8") as output:
            for command in commands:
                remaining = 10 - (time.monotonic() - started)
                if remaining <= 0:
                    break
                print(shlex.join([self.adb] + command), file=output, flush=True)
                try:
                    result = subprocess.run([self.adb] + command, stdout=output,
                                            stderr=subprocess.STDOUT,
                                            env=self.environment,
                                            timeout=remaining, check=False)
                    print(f"Exit status: {result.returncode}", file=output)
                except (OSError, subprocess.SubprocessError) as error:
                    print(f"Android diagnostics failed: {error}", file=output)
        print(f"Android diagnostics: {log}", flush=True)


def terminate(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       check=False, timeout=15)
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait(timeout=15)


def diagnose(process, path, server=None):
    # Capture native waits before killing a timed-out Darwin client. Its
    # debug server is owned by the platform server, not by the client tree.
    # Subtract elapsed time before the budget (adding the budget to an absolute
    # timestamp can round up and hand subprocess a timeout above the limit).
    started = time.monotonic()
    log = path.with_suffix(".diagnostics.log")
    print(f"::group::Timeout diagnostics: {path.name}", flush=True)
    with log.open("w", encoding="utf-8") as output, \
         concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        def capture(pid):
            remaining = 10 - (time.monotonic() - started)
            if remaining <= 0:
                print(f"Sample budget exhausted before capture: {pid}",
                      file=output)
                return
            sample = path.with_suffix(f".{pid}.sample.log")
            try:
                # External dSYM lookup can consume the entire deadline. Keep
                # image symbols and addresses without loading debug bundles.
                command = ["sample", str(pid), "1", "10", "-nodsyms",
                           "-file", str(sample)]
                # Hosted runners permit noninteractive access to task ports.
                if os.environ.get("GITHUB_ACTIONS") == "true":
                    command = ["sudo", "-n"] + command
                result = subprocess.run(command, stdout=output, stderr=output,
                                        check=False, timeout=remaining)
                if result.returncode != 0 or not sample.is_file():
                    print(f"Sample unavailable: {pid} "
                          f"(exit status {result.returncode})", file=output)
            except subprocess.TimeoutExpired:
                print(f"Sample deadline reached: {pid}", file=output)
            except OSError as error:
                print(f"Timeout diagnostics failed: {error}", file=output)

        roots = [process.pid]
        if server is not None and server.process is not None:
            roots.append(server.process.pid)
        # Start known tasks before process enumeration, socket inspection, or
        # console output. Under load those can exhaust the diagnostic budget.
        futures = [pool.submit(capture, pid) for pid in roots]
        ordered = list(roots)
        try:
            if server is not None and server.log.is_file():
                with server.log.open("rb") as trace:
                    trace.seek(0, os.SEEK_END)
                    trace.seek(max(0, trace.tell() - 4096))
                    print("Last DSX output:", flush=True)
                    print(trace.read().decode(errors="replace"), flush=True)
            command = ["ps", "-axo", "pid=,ppid=,state=,etime=,comm="]
            try:
                result = subprocess.run(command, capture_output=True, text=True,
                                        check=True, timeout=2)
                processes = result.stdout
            except (OSError, subprocess.SubprocessError) as error:
                print(f"Process diagnostics failed: {error}", file=output)
                print(f"Process diagnostics failed: {error}", flush=True)
                processes = ""
            records = {}
            for line in processes.splitlines():
                fields = line.split(None, 4)
                if len(fields) == 5 and fields[0].isdigit():
                    records[int(fields[0])] = (int(fields[1]), line)
            selected = set(roots)
            while True:
                children = {pid for pid, (parent, _) in records.items()
                            if parent in selected}
                if children <= selected:
                    break
                ordered.extend(sorted(children - selected, key=lambda pid:
                                      (records[pid][0] != roots[-1], pid)))
                selected.update(children)
            if server is not None and server.process is not None:
                children = [pid for pid in ordered if pid in records and
                            records[pid][0] == server.process.pid]
                ordered = list(dict.fromkeys(list(reversed(children)) + ordered))
            # task_for_pid can block in authorization outside the DSX tree.
            # Sample those services too, within the same diagnostic deadline.
            services = {"taskgated", "taskgated-helper", "authd", "SecurityAgent"}
            ordered.extend(pid for pid, (_, line) in records.items()
                           if pid not in selected and
                           pathlib.Path(line.split(None, 4)[4]).name in services)
            futures.extend(pool.submit(capture, pid) for pid in ordered
                           if pid not in roots and
                           records[pid][1].split()[2].startswith("Z") is False)
            for pid in ordered:
                if pid in records:
                    print(records[pid][1], file=output)
                    print(records[pid][1], flush=True)
            # A handshake stall can leave the client and listener on different
            # sockets. Preserve their endpoints before terminating either side.
            try:
                sockets = subprocess.run(
                    ["lsof", "-nP", "-a", "-p",
                     ",".join(map(str, sorted(selected))), "-iTCP"],
                    capture_output=True, text=True, check=False, timeout=2)
                print(sockets.stdout, file=output)
                print(sockets.stdout, flush=True)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"Socket diagnostics failed: {error}", file=output)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Timeout diagnostics failed: {error}", file=output)
            print(f"Timeout diagnostics failed: {error}", flush=True)
        for future in futures:
            future.result()
        for pid in ordered:
            sample = path.with_suffix(f".{pid}.sample.log")
            if sample.is_file():
                with sample.open(errors="replace") as stack:
                    text = stack.read(8192).split("Binary Images:", 1)[0]
                    print(text, flush=True)
    print("::endgroup::", flush=True)


def execute(command: list[str], environment: dict[str, str],
            path: pathlib.Path, timeout: float, server=None) -> tuple[int, bool]:
    # A file avoids hanging on stdout inherited by a surviving grandchild.
    # Tail it while the direct child runs, retaining all bytes on timeout.
    # Isolate cleanup without making LLDB a session leader: opening a PTY
    # could otherwise acquire a controlling terminal and deliver SIGHUP to
    # the client when the debuggee is torn down. Requires Python 3.11+.
    with path.open("wb") as output:
        process = subprocess.Popen(command, env=environment, stdout=output,
                                   stderr=subprocess.STDOUT,
                                   process_group=(None if sys.platform == "win32"
                                                  else 0))
    timedout = False
    deadline = time.monotonic() + timeout if timeout else None
    try:
        with path.open(encoding="utf-8", errors="replace") as reader:
            while process.poll() is None:
                text = reader.read()
                if text:
                    print(text, end="", flush=True)
                if deadline is not None and time.monotonic() >= deadline:
                    timedout = True
                    print(f"Module deadline reached: {path.name}", flush=True)
                    if sys.platform == "darwin":
                        diagnose(process, path, server)
                    terminate(process)
                    break
                time.sleep(0.1)
            print(reader.read(), end="", flush=True)
        return process.wait(), timedout
    finally:
        terminate(process)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", required=True)
    parser.add_argument("--android", action="store_true")
    parser.add_argument("--android-api", default=28, type=int)
    parser.add_argument("--android-boot-timeout", default=240.0, type=float)
    parser.add_argument("--compiler", type=pathlib.Path)
    parser.add_argument("--dsx", required=True, type=pathlib.Path)
    parser.add_argument("--exclusions", type=pathlib.Path)
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--label", default="LLDB")
    parser.add_argument("--timeout", type=float, default=600,
                        help="per-module deadline in seconds (0 disables)")
    parser.add_argument("--platform", required=True)
    parser.add_argument("--server-url")
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--server-timeout", default=30.0, type=float)
    parser.add_argument("--tests", required=True)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--tools", required=True, type=pathlib.Path)
    parser.add_argument("--triple", required=True)
    parser.add_argument("--working-directory")
    arguments = parser.parse_args()
    if arguments.timeout < 0:
        parser.error("--timeout must be nonnegative")
    if arguments.server_timeout <= 0:
        parser.error("--server-timeout must be positive")

    root = arguments.output or pathlib.Path(tempfile.mkdtemp(
        prefix="dsx-lldb-", dir=os.environ.get("RUNNER_TEMP")))
    root = root.absolute() if sys.platform == "win32" else root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    if (root / "summary.json").exists():
        parser.error("--output already contains a run (use a fresh directory)")
    modules = []
    selected = []
    lldb_results.save(root, modules, 0, arguments.label)
    try:
        settings, config = configuration(arguments, root)
        selected = list(tests(arguments, settings, config))
        if not selected:
            raise RuntimeError("no matching LLDB test modules")
        lldb_results.save(root, modules, len(selected), arguments.label)
        return run(arguments, root, selected, modules, config)
    except (Exception, KeyboardInterrupt, SystemExit) as error:
        detail = str(error) or type(error).__name__
        if isinstance(error, subprocess.CalledProcessError):
            detail += f"\n{error.stdout or ''}\n{error.stderr or ''}"
        (root / "harness-error.log").write_text(detail + "\n", encoding="utf-8")
        result = lldb_results.outcome("", 1)
        result["module"] = "<harness>"
        result["reason"] = detail
        modules.append(result)
        print(result["reason"], file=sys.stderr)
        return 1
    finally:
        data = lldb_results.save(root, modules, len(selected), arguments.label,
                                 completed=True)
        print(lldb_results.render(data), flush=True)
        print(f"Results: {root}", flush=True)


def simulator(arguments, test):
    path = pathlib.Path(test.getSourcePath()).parts[-3:]
    return (arguments.platform == "remote-macosx" and arguments.arch == "arm64"
            and path == ("macosx", "simulator", "TestSimulatorPlatform.py"))


def prepare(arguments, config, root):
    path = root / "simulator-preparation.log"
    script = pathlib.Path(__file__).with_name("prepare-simulators.py")
    command = [config.python_executable, str(script), "--tools",
               str(arguments.tools), "--source", str(arguments.source)]
    # Preserve the old provisioning cap, independently of the test deadline.
    # execute owns the entire child group and retains diagnostics on timeout.
    try:
        status, timedout = execute(command, config.environment, path, 600)
        if status == 0 and not timedout:
            return None
        reason = "timed out" if timedout else f"exited with status {status}"
    except OSError as error:
        reason = str(error)
    failure = lldb_results.outcome("", 1)
    failure.update(module="<harness>", log=path.name,
                   reason=f"Simulator preparation {reason}")
    return failure


def run(arguments: argparse.Namespace, root: pathlib.Path,
        selected: list, modules: list, config) -> int:
    lldb = config.lldb_executable
    (root / "platform").mkdir()
    compiler = pathlib.Path(config.test_compiler)
    server = Server(arguments, root, compiler, config.environment)
    try:
        server.start()
        server.probe(lldb)
        status = 0
        # A specialized prerequisite must not gate unrelated coverage. Run the
        # simulator module last, after checkpointing the other module results.
        selected = sorted(selected, key=lambda test: simulator(arguments, test))
        for index, test in enumerate(selected):
            if simulator(arguments, test):
                failure = prepare(arguments, config, root)
                if failure:
                    modules.append(failure)
                    status = 1
                    lldb_results.save(root, modules, len(selected),
                                      arguments.label)
                    # Preserve the provisioning failure but still run the real
                    # tests. A failed warm-up is not an unsupported feature.
                    print(failure["reason"], flush=True)
            module = pathlib.Path(test.getSourcePath())
            heading = f"Running LLDB API tests: {module}"
            print(heading, flush=True)
            path = root / f"{index:04d}-{module.stem}.log"
            command = test.config.test_format.dotest_cmd
            driver = python_command(lldb, command[0],
                                    test.config.python_executable,
                                    arguments.timeout)
            invocation = driver + command[1:] + [
                "--platform-url", server.url,
                "-p", f"^{re.escape(module.name)}$", str(module.parent)]
            (path.with_suffix(".command.json")).write_text(
                json.dumps(invocation, indent=2) + "\n", encoding="utf-8")
            started = time.monotonic()
            result, timedout = execute(invocation, test.config.environment, path,
                                       arguments.timeout, server)
            text = path.read_text(encoding="utf-8", errors="replace")
            outcome = lldb_results.outcome(text, result, timedout)
            outcome["module"] = str(module)
            outcome["log"] = path.name
            outcome["seconds"] = round(time.monotonic() - started, 3)
            outcome["server"] = server.log.name if server.owned else server.url
            if server.process and server.process.poll() is not None:
                if outcome["status"] != "TIMEOUT":
                    outcome["status"] = "INVALID"
                owner = "ADB session" if server.adb else "DSX"
                status = server.process.returncode
                if server.adb:
                    remote = re.search(r"^DSX_EXIT:(\d+)$",
                                       server.log.read_text(errors="replace"),
                                       re.MULTILINE)
                    if remote:
                        owner, status = "DSX", int(remote[1])
                outcome["reason"] = f"{owner} exited with status {status}"
            if outcome["status"] in ("INVALID", "TIMEOUT"):
                server.diagnose(path)
            modules.append(outcome)
            lldb_results.save(root, modules, len(selected), arguments.label)
            if outcome["status"] != "PASS":
                status = 1
                print(f"{outcome['status']}: {module}", flush=True)
                if arguments.fail_fast or index + 1 == len(selected):
                    break
                recover = outcome["status"] in ("INVALID", "TIMEOUT")
                if not recover:
                    # A live process does not imply a responsive service.
                    # Keep the test failure, and restart only after a failed
                    # health check rather than masking ordinary assertions.
                    try:
                        server.probe(lldb, path.with_suffix(".probe.log"))
                    except RuntimeError as error:
                        outcome["health"] = str(error)
                        server.diagnose(path)
                        recover = True
                if recover:
                    if not server.owned:
                        outcome["recovery"] = "unavailable (external server)"
                        lldb_results.save(root, modules, len(selected),
                                          arguments.label)
                        break
                    # One bounded recovery per incident, never a module retry.
                    # A failed restart/probe ends the shard as a harness error.
                    outcome["recovery"] = "starting"
                    lldb_results.save(root, modules, len(selected),
                                      arguments.label)
                    print("Recovering owned DSX server", flush=True)
                    try:
                        server.recover(lldb)
                        outcome["recovery"] = f"ready ({server.log.name})"
                    except Exception as error:
                        outcome["recovery"] = f"failed: {error}"
                        raise
                    finally:
                        lldb_results.save(root, modules, len(selected),
                                          arguments.label)
        return status
    finally:
        server.stop()


if __name__ == "__main__":
    # Windows redirected streams otherwise use the legacy ANSI code page.
    # Keep live output and child Python logs consistent with our UTF-8 reader.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    os.environ["PYTHONIOENCODING"] = "utf-8"
    raise SystemExit(main())
