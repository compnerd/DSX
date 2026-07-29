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
import socket
import subprocess
import sys
import tempfile
import time

import lldb_results


def available_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def tool(name: str) -> str:
    path = shutil.which(name)
    if path:
        if sys.platform == "win32" and path.lower().endswith(".exe"):
            return path[:-4] + ".exe"
        return path
    raise RuntimeError(f"unable to locate {name}")


def python_command(lldb: str, script: str, executable: str) -> list[str]:
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
    command.append(str(script))
    return command


def wait(server: subprocess.Popen[bytes], log: pathlib.Path,
         timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = server.poll()
        if status is not None:
            detail = log.read_text(errors="replace")
            raise RuntimeError(f"DSX exited with status {status}:\n{detail}")
        if log.is_file() and "Listening on port" in log.read_text(
                errors="replace"):
            return
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


def android_runtime(compiler: pathlib.Path, architecture: str) -> pathlib.Path:
    _, target = android_target(architecture)
    runtime = (compiler.parent.parent / "sysroot" / "usr" / "lib" / target /
               "libc++_shared.so")
    if not runtime.is_file():
        raise RuntimeError(f"unable to locate Android C++ runtime: {runtime}")
    return runtime


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
    config.lldb_executable = tool("lldb")
    config.llvm_tools_dir = str(arguments.tools.resolve())
    config.llvm_shlib_dir = str(pathlib.Path(config.lldb_executable).parent)
    config.python_executable = sys.executable
    config.python_root_dir = sys.base_prefix
    config.lldb_enable_python = True
    config.cmake_build_type = "Debug"
    config.test_arch = arguments.arch
    config.test_triple = arguments.triple
    if arguments.android:
        target, directory = android_target(arguments.arch)
        config.test_triple = f"{target}{arguments.android_api}"
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
            compiler = pathlib.Path(tool("clang"))
    # Preserve clang/clang-cl spelling for LLDB's C++ compiler selection.
    config.test_compiler = str(compiler.absolute())
    config.make = shutil.which("gmake") or tool("make")
    config.lldb_platform_working_dir = (arguments.working_directory or
                                       ("/data/local/tmp/dsx-lldb"
                                        if arguments.android else
                                        str(root / "platform")))
    options = ["-v", "--platform-name", arguments.platform,
               "--out-of-tree-debugserver"]
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
                       subprocess.Popen[bytes], str, str]:
    port = available_port()
    remote = "/data/local/tmp/dsx"
    directory = arguments.working_directory or "/data/local/tmp/dsx-lldb"
    if deploy:
        subprocess.run([adb, "shell", "mkdir", "-p", directory], check=True,
                       timeout=30)
        subprocess.run([adb, "push", str(arguments.dsx.resolve()), remote],
                       check=True, timeout=60)
        subprocess.run([adb, "shell", "chmod", "755", remote], check=True,
                       timeout=30)
        runtime = android_runtime(compiler, arguments.arch)
        subprocess.run([adb, "push", str(runtime),
                        "/data/local/tmp/libc++_shared.so"], check=True,
                       timeout=60)
    parent = shlex.quote(str(pathlib.PurePosixPath(remote).parent))
    command = (f"cd {parent} && echo DSX_PID:$$ "
               f"&& exec {shlex.quote(remote)} platform --server "
               f"--listen 127.0.0.1:{port}")
    if arguments.trace:
        command += " --log-channels all,trace"
    with log.open("wb") as output:
        server = subprocess.Popen([adb, "shell", command], stdout=output,
                                  stderr=output, env=environment,
                                  start_new_session=sys.platform != "win32")
    # remote-android treats the hostname as an ADB device selector. localhost
    # selects the default device; LLDB manages forwards for both server modes.
    return server, f"connect://localhost:{port}", directory


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
            self.process, self.url, directory = android_server(
                self.adb, self.arguments, self.compiler, self.environment,
                self.log, deploy=self.generation == 0)
            self.arguments.working_directory = directory
        else:
            port = available_port()
            self.url = f"connect://127.0.0.1:{port}"
            command = [str(self.arguments.dsx.resolve()), "platform",
                       "--server", "--listen", f"127.0.0.1:{port}"]
            if self.arguments.trace:
                command.extend(("--log-channels", "all,trace"))
            session = sys.platform != "win32"
            with self.log.open("wb") as output:
                self.process = subprocess.Popen(command, stdout=output,
                                                stderr=output,
                                                env=self.environment,
                                                start_new_session=session)
        wait(self.process, self.log, self.arguments.server_timeout)

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

    def probe(self, lldb):
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
        log = self.root / f"probe-{self.generation:03d}.log"
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
        deadline = time.monotonic() + 10
        commands = [
            ["logcat", "-b", "crash", "-d", "-t", "200"],
            ["logcat", "-b", "system", "-d", "-t", "200",
             "ActivityManager:I", "lmkd:I", "*:S"],
            ["shell", "ps", "-A", "-o", "PID,PPID,STAT,WCHAN,NAME"],
        ]
        log = path.with_suffix(".android.log")
        with log.open("w", encoding="utf-8") as output:
            for command in commands:
                remaining = deadline - time.monotonic()
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
    deadline = time.monotonic() + 10
    log = path.with_suffix(".diagnostics.log")
    print(f"::group::Timeout diagnostics: {path.name}", flush=True)
    with log.open("w", encoding="utf-8") as output:
        try:
            if server is not None and server.log.is_file():
                with server.log.open("rb") as trace:
                    trace.seek(0, os.SEEK_END)
                    trace.seek(max(0, trace.tell() - 4096))
                    print("Last DSX output:", flush=True)
                    print(trace.read().decode(errors="replace"), flush=True)
            command = ["ps", "-axo", "pid=,ppid=,state=,etime=,comm="]
            result = subprocess.run(command, capture_output=True, text=True,
                                    check=True, timeout=2)
            records = {}
            for line in result.stdout.splitlines():
                fields = line.split(None, 4)
                if len(fields) == 5 and fields[0].isdigit():
                    records[int(fields[0])] = (int(fields[1]), line)
            roots = [process.pid]
            if server is not None and server.process is not None:
                roots.append(server.process.pid)
            selected = set(roots)
            ordered = list(roots)
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
            output.flush()
            def capture(pid):
                if pid in records and records[pid][1].split()[2].startswith("Z"):
                    return
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return
                sample = path.with_suffix(f".{pid}.sample.log")
                try:
                    command = ["sample", str(pid), "1", "10", "-file",
                               str(sample)]
                    # Use hosted runners' noninteractive sudo for task-port
                    # access. Elevated sampling still shares the deadline.
                    if os.environ.get("GITHUB_ACTIONS") == "true":
                        command = ["sudo", "-n"] + command
                    subprocess.run(command, stdout=output, stderr=output,
                                   check=False, timeout=remaining)
                except subprocess.TimeoutExpired:
                    print(f"Sample deadline reached: {pid}", file=output)
                    print(f"Sample deadline reached: {pid}", flush=True)
                if sample.is_file():
                    with sample.open(errors="replace") as stack:
                        text = stack.read(8192).split("Binary Images:", 1)[0]
                        print(text, flush=True)
            # Symbolication shares the existing total budget rather than
            # consuming it serially before reaching the blocked debug server.
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                list(pool.map(capture, ordered))
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Timeout diagnostics failed: {error}", file=output)
            print(f"Timeout diagnostics failed: {error}", flush=True)
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
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as output:
                output.write(lldb_results.aggregate([root / "summary.json"]))


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
        for index, test in enumerate(selected):
            module = pathlib.Path(test.getSourcePath())
            heading = f"Running LLDB API tests: {module}"
            print(heading, flush=True)
            path = root / f"{index:04d}-{module.stem}.log"
            command = test.config.test_format.dotest_cmd
            driver = python_command(lldb, command[0],
                                    test.config.python_executable)
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
                outcome["reason"] = (f"{owner} exited with status "
                                     f"{server.process.returncode}")
            if outcome["status"] in ("INVALID", "TIMEOUT"):
                server.diagnose(path)
            modules.append(outcome)
            lldb_results.save(root, modules, len(selected), arguments.label)
            if outcome["status"] != "PASS":
                status = 1
                print(f"{outcome['status']}: {module}", flush=True)
                if arguments.fail_fast:
                    break
                if outcome["status"] in ("INVALID", "TIMEOUT"):
                    if index + 1 == len(selected):
                        break
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
