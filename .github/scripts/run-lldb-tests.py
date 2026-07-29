#!/usr/bin/env python3

import argparse
import collections.abc
import os
import pathlib
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import typing


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


def pythonpath(lldb: str, source: pathlib.Path) -> str:
    result = subprocess.run([lldb, "-P"], check=True, capture_output=True,
                            text=True)
    paths = [
        str(source / "lldb" / "packages" / "Python"),
        str(source / "lldb" / "test" / "API"),
    ]
    paths.extend(line for line in result.stdout.splitlines() if line)
    current = os.environ.get("PYTHONPATH")
    if current:
        paths.append(current)
    return os.pathsep.join(paths)


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
    ndk = os.environ.get("ANDROID_NDK_LATEST_HOME") or os.environ.get(
        "ANDROID_NDK_HOME")
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


def exclusions(path: typing.Optional[pathlib.Path],
               kind: str) -> list[re.Pattern[str]]:
    if path is None:
        return []
    patterns = []
    section = None
    for text in path.read_text().splitlines():
        line = text.strip()
        if not line:
            section = None
        elif section is None:
            section = line
        elif section == kind:
            patterns.append(re.compile(line))
    return patterns


def unexpected_successes(output: str) -> bool:
    summaries = re.findall(r"^FAILED \(([^)]*)\)$", output, re.MULTILINE)
    if len(summaries) != 1:
        return False
    outcomes = {}
    for outcome in summaries[0].split(", "):
        name, count = outcome.rsplit("=", 1)
        outcomes[name] = int(count)
    return (outcomes.get("unexpected successes", 0) != 0 and
            "failures" not in outcomes and "errors" not in outcomes)


def tests(source: pathlib.Path, specifications: str,
          skipped: list[re.Pattern[str]]) -> collections.abc.Iterator[
              tuple[pathlib.Path, str]]:
    api = source / "lldb" / "test" / "API"
    visited = set()
    for specification in specifications.split(","):
        path = api / specification
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = sorted(path.rglob("Test*.py"))
        else:
            raise RuntimeError(f"unable to locate LLDB tests: {path}")
        for candidate in candidates:
            if any(pattern.search(candidate.name) for pattern in skipped):
                continue
            resolved = candidate.resolve()
            if resolved in visited:
                continue
            visited.add(resolved)
            yield candidate, f"^{re.escape(candidate.name)}$"


def wait_android(adb: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    subprocess.run([adb, "wait-for-device"], check=True,
                   timeout=max(0.1, deadline - time.monotonic()))
    while time.monotonic() < deadline:
        result = subprocess.run([adb, "shell", "getprop", "sys.boot_completed"],
                                capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip() == "1":
            return
        time.sleep(2)
    raise RuntimeError("Android emulator did not finish booting")


def android_server(adb: str, arguments: argparse.Namespace,
                   compiler: pathlib.Path, environment: dict[str, str],
                   log: pathlib.Path) -> tuple[subprocess.Popen[bytes], str,
                                               str]:
    port = available_port()
    remote = "/data/local/tmp/dsx"
    directory = arguments.working_directory or "/data/local/tmp/dsx-lldb"
    forward = f"tcp:{port}"
    try:
        subprocess.run([adb, "shell", "mkdir", "-p", directory], check=True)
        subprocess.run([adb, "push", str(arguments.dsx.resolve()), remote],
                       check=True)
        subprocess.run([adb, "shell", "chmod", "755", remote], check=True)
        runtime = android_runtime(compiler, arguments.arch)
        subprocess.run([adb, "push", str(runtime),
                        "/data/local/tmp/libc++_shared.so"], check=True)
        subprocess.run([adb, "forward", forward, forward], check=True)
        command = (f"cd {shlex.quote(str(pathlib.PurePosixPath(remote).parent))} "
                   f"&& exec {shlex.quote(remote)} platform --server "
                   f"--listen 127.0.0.1:{port}")
        with log.open("wb") as output:
            server = subprocess.Popen([adb, "shell", command], stdout=output,
                                      stderr=output, env=environment)
        return server, f"connect://127.0.0.1:{port}", forward
    except Exception:
        subprocess.run([adb, "shell", "pkill", "dsx"], check=False)
        subprocess.run([adb, "forward", "--remove", forward], check=False)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", required=True)
    parser.add_argument("--android", action="store_true")
    parser.add_argument("--android-api", default=28, type=int)
    parser.add_argument("--android-boot-timeout", default=240.0, type=float)
    parser.add_argument("--compiler", type=pathlib.Path)
    parser.add_argument("--dsx", required=True, type=pathlib.Path)
    parser.add_argument("--exclusions", type=pathlib.Path)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--server-url")
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--server-timeout", default=30.0, type=float)
    parser.add_argument("--tests", required=True)
    parser.add_argument("--tools", required=True, type=pathlib.Path)
    parser.add_argument("--triple", required=True)
    parser.add_argument("--working-directory")
    arguments = parser.parse_args()

    lldb = tool("lldb")
    if arguments.compiler:
        compiler = arguments.compiler.resolve()
    elif arguments.android:
        compiler = android_compiler(arguments.arch, arguments.android_api)
    else:
        compiler = pathlib.Path(tool("clang"))
    root = pathlib.Path(tempfile.mkdtemp(prefix="dsx-lldb-"))
    build = root / "lldb-test-build.noindex"
    platform = root / "platform"
    build.mkdir()
    platform.mkdir()
    log = root / "server.log"
    environment = os.environ.copy()
    if sys.platform == "win32" and environment.get("SDKROOT"):
        environment["SDKROOT"] = environment["SDKROOT"].rstrip("/\\")
    environment["PYTHONPATH"] = pythonpath(lldb, arguments.source)
    adb = None
    forward = None
    server = None
    server_url = arguments.server_url
    if arguments.android:
        if server_url:
            raise RuntimeError("--android and --server-url cannot be combined")
        adb = tool("adb")
        wait_android(adb, arguments.android_boot_timeout)
        server, server_url, forward = android_server(adb, arguments, compiler,
                                                     environment, log)
    elif not server_url:
        port = available_port()
        server_url = f"connect://127.0.0.1:{port}"
        command = [
            str(arguments.dsx.resolve()),
            "platform",
            "--server",
            "--listen",
            f"127.0.0.1:{port}",
        ]
        with log.open("wb") as output:
            server = subprocess.Popen(command, stdout=output, stderr=output,
                                      env=environment)
    try:
        if server:
            wait(server, log, arguments.server_timeout)
        dotest = arguments.source / "lldb" / "test" / "API" / "dotest.py"
        command = [
            sys.executable,
            str(dotest),
            "-v",
            "--triple", arguments.triple,
            "-C", str(compiler),
            "--executable", lldb,
            "--llvm-tools-dir", str(arguments.tools.resolve()),
            "--make", tool("make"),
            "--platform-name", arguments.platform,
            "--platform-url", server_url,
            "--platform-working-dir",
            arguments.working_directory or str(platform),
            "--build-dir", str(build),
            "--out-of-tree-debugserver",
        ]
        if sys.platform == "win32":
            command.extend(("--env", "LLDB_LAUNCH_FLAG_USE_PIPES=1"))
        if arguments.exclusions:
            command.extend(("--excluded",
                            str(arguments.exclusions.resolve())))
        status = 0
        skipped = exclusions(arguments.exclusions, "skip")
        for module, pattern in tests(arguments.source, arguments.tests,
                                     skipped):
            print(f"Running LLDB API tests: {module}", flush=True)
            result = subprocess.run(command + ["-p", pattern,
                                                str(module.parent)],
                                    env=environment, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end="", flush=True)
            if result.returncode != 0 and not unexpected_successes(
                    result.stdout):
                print(f"LLDB API tests exited with status "
                      f"{result.returncode}: {module}",
                      flush=True)
                status = result.returncode
        return status
    finally:
        if server:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        if adb:
            subprocess.run([adb, "shell", "pkill", "dsx"], check=False)
            if forward:
                subprocess.run([adb, "forward", "--remove", forward],
                               check=False)
        if server:
            destination = pathlib.Path(os.environ.get("RUNNER_TEMP", root))
            shutil.copy2(log, destination / "dsx-server.log")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
