# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import ast
import importlib.util
import io
import json
import math
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import lldb_results

spec = importlib.util.spec_from_file_location(
    "harness", pathlib.Path(__file__).resolve().parents[1] / "run-lldb-tests.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class Patches(unittest.TestCase):
    def test_series(self):
        upstream = pathlib.Path(os.environ.get("LLVM_SOURCE", "llvm-project"))
        if not (upstream / ".git").exists():
            self.skipTest("set LLVM_SOURCE to an LLVM checkout")
        source = pathlib.Path(__file__).resolve().parents[3]
        patches = sorted((source / ".github/patches").glob("lldb-*.patch"))
        # Start from committed inputs, not the already patched test checkout.
        paths = {line.removeprefix("--- a/")
                 for path in patches for line in path.read_text().splitlines()
                 if line.startswith("--- a/")}
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            for path in sorted(paths):
                result = subprocess.run(
                    ["git", "-C", str(upstream), "show", f"HEAD:{path}"],
                    check=True, capture_output=True)
                output = root / path
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(result.stdout)
            for path in patches:
                with self.subTest(patch=path.name):
                    result = subprocess.run(
                        ["git", "-C", str(root), "apply", str(path)],
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
            # The workflow must also recognize an already applied series.
            for path in patches:
                with self.subTest(applied=path.name):
                    result = subprocess.run(
                        ["git", "-C", str(root), "apply", "--reverse",
                         "--check", str(path)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_checkout(self):
        source = pathlib.Path(__file__).resolve().parents[3]
        patches = sorted((source / ".github/patches").glob("lldb-*.patch"))
        self.assertTrue(patches)
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            (root / ".gitattributes").write_bytes(
                (source / ".gitattributes").read_bytes())
            for path in patches:
                (root / path.name).write_bytes(path.read_bytes())
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            checkout = root / "checkout"
            subprocess.run(["git", "-C", str(root), "-c", "core.autocrlf=true",
                            "checkout-index", "--all",
                            f"--prefix={checkout.as_posix()}/"], check=True)
            for path in checkout.glob("*.patch"):
                with self.subTest(patch=path.name):
                    result = subprocess.run(
                        ["git", "apply", "--numstat", str(path)],
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn(b"\r", path.read_bytes())


class Tools(unittest.TestCase):
    def test_directory(self):
        directory = pathlib.Path("selected-tools")
        with patch.object(harness.shutil, "which",
                          return_value="selected-tools/lldb") as search:
            self.assertEqual(harness.tool("lldb", directory),
                             "selected-tools/lldb")
        search.assert_called_once_with("lldb", path=str(directory))

    def test_missing(self):
        with patch.object(harness.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "unable to locate"):
                harness.tool("lldb", pathlib.Path("selected-tools"))

    def test_path(self):
        with patch.object(harness.shutil, "which", return_value="make") as search:
            self.assertEqual(harness.tool("make"), "make")
        search.assert_called_once_with("make", path=None)

    def test_android_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tools = root / "toolchains/llvm/prebuilt/host/bin"
            tools.mkdir(parents=True)
            for api in (28, 30):
                (tools / f"x86_64-linux-android{api}-clang").touch()
            with patch.dict(os.environ, {"ANDROID_NDK_HOME": str(root)}):
                for api in (28, 30):
                    with self.subTest(api=api):
                        self.assertEqual(
                            harness.android_compiler("x86_64", api),
                            tools / f"x86_64-linux-android{api}-clang")

    def test_android_runtimes(self):
        for arch, cpu in (("arm", "arm"), ("arm64", "aarch64"),
                          ("i386", "i686"), ("x86_64", "x86_64")):
            with self.subTest(arch=arch), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                target, library = harness.android_target(arch)
                compiler = root / "bin" / f"{target}30-clang"
                runtime = (root / "sysroot/usr/lib" / library /
                           "libc++_shared.so")
                runtime.parent.mkdir(parents=True)
                runtime.touch()
                name = f"libclang_rt.asan-{cpu}-android.so"
                sanitizer = root / "lib" / name
                sanitizer.parent.mkdir()
                sanitizer.touch()
                with patch.object(harness.subprocess, "check_output",
                                  return_value=f"{sanitizer}\n") as query:
                    self.assertEqual(harness.android_runtimes(compiler, arch),
                                     [runtime, sanitizer])
                query.assert_called_once_with(
                    [str(compiler), f"--print-file-name={name}"], text=True,
                    timeout=30)
                for missing in (name, str(root / "missing.so")):
                    with patch.object(harness.subprocess, "check_output",
                                      return_value=missing):
                        with self.assertRaisesRegex(RuntimeError,
                                                    "Android ASan runtime"):
                            harness.android_runtimes(compiler, arch)


class Streams(unittest.TestCase):
    def test_encoding(self):
        source = pathlib.Path(harness.__file__).resolve()
        with tempfile.TemporaryDirectory() as directory:
            script = pathlib.Path(directory) / "lldb-\u6e2c\u8a66.py"
            script.write_bytes(source.read_bytes())
            environment = os.environ | {
                "PYTHONIOENCODING": "cp1252",
                "PYTHONPATH": str(source.parent),
            }
            for option, status in (("--help", 0), ("--invalid-\u6e2c\u8a66", 2)):
                with self.subTest(option=option):
                    result = subprocess.run(
                        [sys.executable, str(script), option], env=environment,
                        capture_output=True)
                    self.assertEqual(result.returncode, status, result.stderr)
                    output = result.stdout if status == 0 else result.stderr
                    self.assertIn(script.name, output.decode("utf-8"))


class Results(unittest.TestCase):
    def test_success(self):
        result = lldb_results.outcome("Ran 5 tests in 0.1s\n\nOK\n", 0)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["counts"]["PASS"], 5)

    def test_errors(self):
        result = lldb_results.outcome(
            "FAIL: LLDB (clang) :: example\nERROR: example (Test.example)\n"
            "Ran 8 tests in 0.1s\n\nFAILED (failures=1, errors=2, skipped=1, "
            "expected failures=1, unexpected successes=1)\n", 1)
        self.assertEqual(result["counts"],
                         {"PASS": 2, "FAIL": 1, "ERROR": 2, "UNSUPPORTED": 1,
                          "XFAIL": 1, "UXPASS": 1})
        self.assertEqual(len(result["tests"]), 1)
        self.assertEqual(result["tests"][0]["outcome"], "ERROR")

    def test_unexpected(self):
        result = lldb_results.outcome(
            "Ran 2 tests in 0.1s\n\nFAILED (unexpected successes=1)\n", 1)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["counts"]["UXPASS"], 1)

    def test_skip(self):
        result = lldb_results.outcome(
            "Ran 2 tests in 0.1s\n\nOK (skipped=2)\n", 0)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["counts"]["PASS"], 0)
        self.assertEqual(result["counts"]["UNSUPPORTED"], 2)

    def test_invalid(self):
        for text, status in (("", 0), ("Ran 0 tests in 0s\nOK\n", 0),
                              ("Ran 1 test in 0s\nOK\n", -11),
                              ("Ran 1 test in 0s\nFAILED (failures=1)\n", 0)):
            with self.subTest(text=text, status=status):
                self.assertEqual(lldb_results.outcome(text, status)["status"],
                                 "INVALID")

    def test_timeout(self):
        self.assertEqual(lldb_results.outcome("", -9, True)["status"],
                         "TIMEOUT")
        with tempfile.TemporaryDirectory() as directory:
            module = lldb_results.outcome("", -9, True)
            module["module"] = "TestTimeout.py"
            data = lldb_results.save(pathlib.Path(directory), [module], 2, "x")
            self.assertEqual(data["attempted"], 1)
            self.assertEqual(data["finished"], 0)
            self.assertIn("Modules not run:  1", lldb_results.render(data))

    def test_collected(self):
        for status, timedout in ((-1, False), (-9, True)):
            with self.subTest(status=status):
                module = lldb_results.outcome(
                    "Collected 2 tests\n1: test_ios ... ", status, timedout)
                self.assertEqual(module["total"], 2)
                self.assertEqual(sum(module["counts"].values()), 0)
                module["module"] = "TestSimulator.py"
                with tempfile.TemporaryDirectory() as directory:
                    root = pathlib.Path(directory)
                    data = lldb_results.save(root, [module], 1, "simulator")
                    summary = lldb_results.render(data)
                    self.assertIn("Tests run:        0", summary)
                    self.assertIn("Tests unreported: 2", summary)
                    summary = lldb_results.aggregate([root / "summary.json"])
                    self.assertIn("| simulator | 2 | 0 |", summary)

    def test_partial(self):
        result = lldb_results.outcome(
            "Collected 4 tests\nRan 1 test in 0.1s\nFAILED (failures=1)\n", 1)
        self.assertEqual(result["total"], 4)
        self.assertEqual(result["counts"]["FAIL"], 1)
        self.assertEqual(result["counts"]["PASS"], 0)

    def test_teardown_failure(self):
        # A test body and its teardown can both fail. Outcomes are not a
        # substitute for unittest's count of executed test cases.
        result = lldb_results.outcome(
            "Collected 1 test\nRan 1 test in 0s\nFAILED (failures=2)\n", 1)
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["reported"], 1)
        self.assertEqual(result["counts"]["FAIL"], 2)

    def test_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            module = lldb_results.outcome("Ran 1 test in 0s\nOK\n", 0)
            module["module"] = "TestExample.py"
            data = lldb_results.save(root, [module], 3, "example")
            self.assertEqual(data["finished"], 1)
            self.assertEqual(json.loads((root / "summary.json").read_text()),
                             data)
            self.assertIn("Modules not run:  2", lldb_results.render(data))
            self.assertIn("| example |", lldb_results.aggregate(
                [root / "summary.json"]))

    def test_harness(self):
        with tempfile.TemporaryDirectory() as directory:
            module = lldb_results.outcome("", 1)
            module["module"] = "<harness>"
            data = lldb_results.save(pathlib.Path(directory), [module], 0, "x")
            self.assertEqual(data["finished"], 0)
            self.assertEqual(data["counts"]["INVALID"], 1)

    def test_discovered(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for label in ("first", "second"):
                root = pathlib.Path(directory) / label
                root.mkdir()
                module = lldb_results.outcome(
                    "Ran 5 tests in 0.1s\nOK (skipped=2)\n", 0)
                module["module"] = "TestExample.py"
                lldb_results.save(root, [module], 1, label)
                paths.append(root / "summary.json")
            summary = lldb_results.aggregate(paths)
            self.assertIn("| Shard | Discovered | Run |", summary)
            self.assertIn("| first | 5 | 3 |", summary)
            self.assertIn("| second | 5 | 3 |", summary)
            self.assertIn("| Total | 10 | 6 |", summary)
            rows = [line for line in summary.splitlines()
                    if line.startswith("|")]
            self.assertEqual(len({row.count("|") for row in rows}), 1)

    def test_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            module = lldb_results.outcome(
                "Ran 2 tests in 0.1s\nOK (skipped=2)\n", 0)
            module["module"] = "TestSkipped.py"
            data = lldb_results.save(root, [module], 1, "unsupported")
            self.assertIn("No coverage: no reported test executions",
                          lldb_results.render(data))
            self.assertIn("No coverage (no reported executions): unsupported.",
                          lldb_results.aggregate([root / "summary.json"]))

    def test_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            lldb_results.finalize(root, "setup")
            data = json.loads((root / "summary.json").read_text())
            self.assertEqual(data["counts"]["INVALID"], 1)
            self.assertTrue(data["completed"])
            lldb_results.finalize(root, "setup")
            self.assertEqual(json.loads((root / "summary.json").read_text()),
                             data)

    def test_interrupted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            module = lldb_results.outcome("Ran 1 test in 0s\nOK\n", 0)
            module["module"] = "TestExample.py"
            lldb_results.save(root, [module], 3, "interrupted")
            lldb_results.finalize(root, "interrupted")
            data = json.loads((root / "summary.json").read_text())
            self.assertEqual(data["counts"]["PASS"], 1)
            self.assertEqual(data["counts"]["INVALID"], 1)
            self.assertEqual(data["finished"], 1)


class Platforms(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name)

    def write(self, shard, text="Ran 2 tests in 0s\nOK\n", status=0,
              selected=1, completed=True, timedout=False):
        root = self.root / shard
        root.mkdir()
        module = lldb_results.outcome(text, status, timedout)
        module["module"] = "TestExample.py"
        lldb_results.save(root, [module], selected,
                          f"Windows ARM64/{shard}/snapshot", completed)
        return root / "summary.json"

    def summary(self, shards=("commands", "tools"), result="success"):
        return lldb_results.platform(list(self.root.rglob("summary.json")),
                                      "Windows ARM64", "snapshot", list(shards),
                                      result)

    def test_clean(self):
        self.write("commands")
        self.write("tools", "Ran 2 tests in 0s\nOK (skipped=2)\n")
        text, clean = self.summary()
        self.assertTrue(clean)
        self.assertIn("**Clean**", text)
        self.assertIn("**2/2** (2 passed, 0 failed, 0 incomplete)", text)
        self.assertIn("| Total | — | 4 | 2 |", text)
        self.assertIn("No coverage (no reported executions)", text)
        rows = [line for line in text.splitlines() if line.startswith("|")]
        self.assertEqual(len({row.count("|") for row in rows}), 1)

    def test_failure(self):
        self.write("commands", "Ran 2 tests in 0s\nFAILED (errors=1)\n", 1)
        self.write("tools")
        text, clean = self.summary(result="failure")
        self.assertFalse(clean)
        self.assertIn("**Failing**", text)
        self.assertIn("**2/2** (1 passed, 1 failed, 0 incomplete)", text)

    def test_unexpected(self):
        self.write("commands", "Ran 2 tests in 0s\n"
                   "FAILED (unexpected successes=1)\n", 1)
        text, clean = self.summary(shards=("commands",))
        self.assertTrue(clean)
        self.assertIn("**Clean**", text)
        self.assertIn("| Total | — | 2 | 2 | 1 | 0 | 1 |", text)

    def test_missing(self):
        self.write("commands")
        text, clean = self.summary()
        self.assertFalse(clean)
        self.assertIn("**Incomplete**", text)
        self.assertIn("**1/2** (1 passed, 0 failed, 1 incomplete)", text)
        self.assertIn("| tools | Missing | — |", text)

    def test_empty(self):
        for shards in (("commands",), ()):
            with self.subTest(shards=shards):
                text, clean = self.summary(shards=shards)
                self.assertFalse(clean)
                self.assertIn("**Incomplete**", text)

    def test_partial(self):
        self.write("commands", selected=2, completed=False)
        text, clean = self.summary(shards=("commands",))
        self.assertFalse(clean)
        self.assertIn("**Incomplete**", text)
        self.assertIn("**0/1**", text)

    def test_timeout(self):
        self.write("commands", "Collected 2 tests\n", -9, timedout=True)
        text, clean = self.summary(shards=("commands",), result="failure")
        self.assertFalse(clean)
        self.assertIn("**Incomplete**", text)
        self.assertIn("| Total | — | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 1 |",
                      text)

    def test_failure_with_missing(self):
        self.write("commands", "Ran 1 test in 0s\nFAILED (failures=1)\n", 1)
        text, clean = self.summary(result="failure")
        self.assertFalse(clean)
        self.assertIn("**Failing (incomplete)**", text)

    def test_no_coverage(self):
        self.write("commands", "Ran 2 tests in 0s\nOK (skipped=2)\n")
        text, clean = self.summary(shards=("commands",))
        self.assertFalse(clean)
        self.assertIn("**No coverage**", text)

    def test_job_failure(self):
        self.write("commands")
        for result in ("failure", "cancelled", "skipped"):
            with self.subTest(result=result):
                text, clean = self.summary(shards=("commands",), result=result)
                self.assertFalse(clean)
                self.assertIn("**Incomplete**", text)
                self.assertIn(f"Shard jobs: {result}", text)

    def test_duplicate(self):
        path = self.write("commands")
        duplicate = self.root / "duplicate"
        duplicate.mkdir()
        (duplicate / "summary.json").write_bytes(path.read_bytes())
        text, clean = self.summary(shards=("commands",))
        self.assertFalse(clean)
        self.assertIn("| commands | Duplicate | — |", text)

    def test_corrupt(self):
        path = self.write("commands")
        path.write_text("{", encoding="utf-8")
        text, clean = self.summary(shards=("commands",))
        self.assertFalse(clean)
        self.assertIn("**Incomplete**", text)
        self.assertIn("Unreadable or unexpected summary", text)

    def test_malformed(self):
        path = self.write("commands")
        path.write_text('{"label":"Windows ARM64/commands/snapshot"}',
                         encoding="utf-8")
        text, clean = self.summary(shards=("commands",))
        self.assertFalse(clean)
        self.assertIn("**Incomplete**", text)
        self.assertIn("| commands | Invalid summary | — |", text)

    def test_selected_shards(self):
        self.write("commands")
        text, clean = self.summary(shards=("commands",))
        self.assertTrue(clean)
        self.assertIn("Selected shards: commands.", text)
        self.assertIn("Only the selected scope is assessed", text)

    def test_cli(self):
        script = pathlib.Path(lldb_results.__file__)
        command = [sys.executable, str(script), str(self.root),
                   "--target", "Windows ARM64", "--build", "snapshot",
                   "--shards", '[{"name":"commands"}]']
        missing = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("**Incomplete**", missing.stdout)
        self.write("commands")
        complete = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(complete.returncode, 0, complete.stderr)
        self.assertIn("**Clean**", complete.stdout)


class Harness(unittest.TestCase):
    def test_python(self):
        with tempfile.TemporaryDirectory(prefix="dsx python ") as directory:
            root = pathlib.Path(directory)
            (root / "sibling.py").write_text("value = 42\n")
            script = root / "entry.py"
            script.write_text("import json,sys,sibling\n"
                              "print(json.dumps([sibling.value,sys.argv]))\n")
            command = harness.python_command(str(root / "lldb.exe"),
                                             str(script), sys.executable)
            command.append("argument with spaces")
            result = subprocess.run(command, cwd=root.parent, check=True,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(result.stdout),
                             [42, [str(script), "argument with spaces"]])

    @unittest.skipUnless(sys.platform == "darwin", "Darwin timeout stacks")
    def test_python_stacks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            script = root / "entry.py"
            script.write_text("import signal,time\n"
                              "signal.pthread_sigmask(signal.SIG_BLOCK, "
                              "{signal.SIGUSR1})\n"
                              "print('ready', flush=True)\n"
                              "time.sleep(60)\n")
            command = harness.python_command("lldb", str(script),
                                             sys.executable, timeout=1)
            process = subprocess.Popen(command, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True)
            try:
                ready = threading.Event()

                def read():
                    if process.stdout.readline() == "ready\n":
                        ready.set()

                reader = threading.Thread(target=read)
                reader.start()
                self.assertTrue(ready.wait(10))
                reader.join(timeout=1)
                output = []
                captured = threading.Event()

                def stack():
                    for line in process.stderr:
                        output.append(line)
                        if str(script) in line:
                            captured.set()
                            return

                sampler = threading.Thread(target=stack)
                sampler.start()
                self.assertTrue(captured.wait(10))
                sampler.join(timeout=1)
                self.assertIsNone(process.poll())
                self.assertIn("line 4", "".join(output))
            finally:
                process.kill()
                process.wait(timeout=10)
                process.stdout.close()
                process.stderr.close()

    def exercise(self, root, results, *, owned=True, fail_fast=False,
                 recovery=None, dead=False, remote=None, probe=None,
                 platform="remote-linux", arch="aarch64", paths=None):
        args = argparse.Namespace(
            compiler=root / "clang", source=root, tools=root,
            platform=platform, working_directory=None,
            triple="aarch64-unknown-linux-gnu", arch=arch,
            exclusions=None, timeout=1, label="fixture", fail_fast=fail_fast)
        config = Mock(lldb_executable="lldb", test_compiler=str(root / "clang"),
                      environment=os.environ.copy(),
                      python_executable=sys.executable)
        config.test_format.dotest_cmd = ["dotest.py"]
        server = Mock(owned=owned, adb=None, url="connect://127.0.0.1:1234",
                      log=root / "server.log")
        if remote is not None:
            server.adb = "adb"
            server.log.write_text(remote)
        server.process = Mock(returncode=1) if dead else None
        if dead:
            server.process.poll.return_value = 1
            if remote is not None:
                server.process.returncode = 255

        def recover(_):
            if recovery:
                raise RuntimeError(recovery)
            server.url = "connect://127.0.0.1:5678"
            server.log = root / "server-001.log"
            server.process = None

        server.recover.side_effect = recover
        server.probe.side_effect = probe
        pending = iter(results)

        def execute(command, environment, path, timeout, server=None):
            text, status, timedout = next(pending)
            path.write_text(text)
            return status, timedout

        selected = [Mock(config=config) for _ in results]
        for index, test in enumerate(selected):
            name = paths[index] if paths else f"Test{index}.py"
            test.getSourcePath.return_value = str(root / name)
        modules = []
        with patch.object(harness, "Server", return_value=server), \
             patch.object(harness, "tool", return_value="lldb"), \
             patch.object(harness.shutil, "which", return_value="make"), \
             patch.object(harness, "execute", side_effect=execute) as calls:
            try:
                status = harness.run(args, root, selected, modules, config)
            except RuntimeError:
                server.stop.assert_called_once()
                raise
        server.stop.assert_called_once()
        return status, modules, server, calls

    def test_simulator_isolation(self):
        paths = ["macosx/simulator/TestSimulatorPlatform.py", "TestOther.py"]
        for failed in (False, True):
            with self.subTest(failed=failed), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)

                def prepare(arguments, config, output):
                    data = json.loads((output / "summary.json").read_text())
                    self.assertEqual(data["attempted"], 1)
                    module = data["modules"][0]["module"]
                    self.assertTrue(module.endswith("TestOther.py"))
                    if failed:
                        failure = lldb_results.outcome("", 1)
                        failure.update(module="<harness>", reason="setup failed")
                        return failure

                results = [("Ran 1 test in 0s\nOK\n", 0, False)] * 2
                with patch.object(harness, "prepare", side_effect=prepare):
                    outcome = self.exercise(root, results, paths=paths,
                                            platform="remote-macosx",
                                            arch="arm64")
                result, modules, server, calls = outcome
                self.assertEqual(result, int(failed))
                self.assertEqual(calls.call_count, 2)
                self.assertEqual(pathlib.Path(modules[-1]["module"]),
                                 root / paths[0])
                self.assertEqual(modules[-1]["status"], "PASS")
                data = json.loads((root / "summary.json").read_text())
                self.assertEqual(data["attempted"], 2)
                self.assertEqual(data["reported"], 2)
                self.assertEqual(data["counts"]["INVALID"], int(failed))
                self.assertEqual(data["counts"]["UNSUPPORTED"], 0)
                server.recover.assert_not_called()

    def test_simulator_scope(self):
        test = Mock()
        test.getSourcePath.return_value = (
            "/source/macosx/simulator/TestSimulatorPlatform.py")
        for platform, arch, expected in (("remote-macosx", "arm64", True),
                                         ("remote-macosx", "x86_64", False),
                                         ("remote-windows", "arm64", False),
                                         ("remote-linux", "arm64", False)):
            arguments = argparse.Namespace(platform=platform, arch=arch)
            self.assertEqual(harness.simulator(arguments, test), expected)

    def test_simulator_preparation_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            arguments = argparse.Namespace(tools=root, source=root)
            config = Mock(python_executable=sys.executable, environment={})
            for response in ((1, False), (-9, True), OSError("missing tool")):
                error = isinstance(response, OSError)
                key = "side_effect" if error else "return_value"
                options = {key: response}
                with self.subTest(response=response), \
                     patch.object(harness, "execute", **options):
                    failure = harness.prepare(arguments, config, root)
                self.assertEqual(failure["status"], "INVALID")
                self.assertEqual(failure["module"], "<harness>")
                self.assertEqual(failure["total"], 0)
                self.assertIn("Simulator preparation", failure["reason"])

    def test_recovery(self):
        for text, status, timedout, kind in (
                ("client crashed", -11, False, "INVALID"),
                ("client hung", -9, True, "TIMEOUT")):
            with self.subTest(kind=kind), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                result, modules, server, calls = self.exercise(
                    root, [(text, status, timedout),
                           ("Ran 1 test in 0s\nOK\n", 0, False)])
                self.assertEqual(result, 1)
                self.assertEqual([m["status"] for m in modules], [kind, "PASS"])
                self.assertEqual(modules[0]["recovery"],
                                 "ready (server-001.log)")
                server.recover.assert_called_once()
                self.assertEqual(calls.call_count, 2)
                self.assertIn("connect://127.0.0.1:5678",
                              calls.call_args.args[0])
                self.assertEqual((root / modules[0]["log"]).read_text(), text)

    def test_recovery_disabled(self):
        for owned, fast in ((False, False), (True, True)):
            with self.subTest(owned=owned, fast=fast), \
                 tempfile.TemporaryDirectory() as directory:
                result, modules, server, calls = self.exercise(
                    pathlib.Path(directory), [("", -9, True)] * 2,
                    owned=owned, fail_fast=fast)
                self.assertEqual(result, 1)
                self.assertEqual(len(modules), 1)
                server.recover.assert_not_called()
                self.assertEqual(calls.call_count, 1)

    def test_recovery_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with self.assertRaisesRegex(RuntimeError, "probe failed"):
                self.exercise(root, [("", -9, True)] * 2,
                              recovery="probe failed")
            summary = json.loads((root / "summary.json").read_text())
            self.assertEqual(summary["attempted"], 1)
            self.assertEqual(summary["counts"]["TIMEOUT"], 1)
            self.assertIn("failed: probe failed",
                          summary["modules"][0]["recovery"])

    def test_server_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            result, modules, server, _ = self.exercise(
                pathlib.Path(directory),
                [("Ran 1 test in 0s\nOK\n", 0, False)] * 2, dead=True)
            self.assertEqual(result, 1)
            self.assertEqual(modules[0]["status"], "INVALID")
            self.assertEqual(modules[1]["status"], "PASS")
            self.assertIn("DSX exited", modules[0]["reason"])
            server.recover.assert_called_once()

    def test_timeout_with_server_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            result, modules, server, _ = self.exercise(
                pathlib.Path(directory), [("", -9, True)], dead=True)
            self.assertEqual(result, 1)
            self.assertEqual(modules[0]["status"], "TIMEOUT")
            self.assertIn("DSX exited", modules[0]["reason"])
            server.recover.assert_not_called()

    def test_android_exit(self):
        for text, owner, status in (("DSX_EXIT:7\n", "DSX", 7),
                                    ("DSX_EXIT:143\r\n", "DSX", 143),
                                    ("DSX_PID:123\n", "ADB session", 255)):
            with self.subTest(owner=owner, status=status), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                results = [("Ran 1 test in 0s\nOK\n", 0, False)]
                result, modules, _, _ = self.exercise(root, results, dead=True,
                                                    remote=text)
                self.assertEqual(result, 1)
                self.assertEqual(modules[0]["status"], "INVALID")
                self.assertEqual(modules[0]["reason"],
                                 f"{owner} exited with status {status}")

    def test_shared_server(self):
        with tempfile.TemporaryDirectory() as directory:
            result, modules, server, calls = self.exercise(
                pathlib.Path(directory),
                [("Ran 1 test in 0s\nFAILED (failures=1)\n", 1, False),
                 ("Ran 1 test in 0s\nOK\n", 0, False)])
            self.assertEqual(result, 1)
            self.assertEqual([m["status"] for m in modules], ["FAIL", "PASS"])
            server.start.assert_called_once()
            server.recover.assert_not_called()
            self.assertEqual(server.probe.call_count, 2)
            self.assertEqual(calls.call_count, 2)

    def test_unresponsive_server(self):
        for failure in ("failures=1", "errors=1"):
            with self.subTest(failure=failure), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                text = f"Ran 1 test in 0s\nFAILED ({failure})\n"
                results = [(text, 1, False),
                           ("Ran 1 test in 0s\nOK\n", 0, False)]
                probe = [None, RuntimeError("platform probe failed")]
                result, modules, server, calls = self.exercise(root, results,
                                                             probe=probe)
                self.assertEqual(result, 1)
                self.assertEqual([m["status"] for m in modules],
                                 ["FAIL", "PASS"])
                self.assertEqual(modules[0]["health"], "platform probe failed")
                self.assertEqual(modules[0]["recovery"],
                                 "ready (server-001.log)")
                self.assertEqual((root / modules[0]["log"]).read_text(), text)
                server.probe.assert_called_with("lldb",
                                                root / "0000-Test0.probe.log")
                server.diagnose.assert_called_once()
                server.recover.assert_called_once()
                self.assertEqual(calls.call_count, 2)
                self.assertIn("connect://127.0.0.1:5678",
                              calls.call_args.args[0])

    def test_unresponsive_external_server(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            text = "Ran 1 test in 0s\nFAILED (failures=1)\n"
            results = [(text, 1, False)] * 2
            probe = [None, RuntimeError("platform probe failed")]
            result, modules, server, calls = self.exercise(root, results,
                                                         owned=False,
                                                         probe=probe)
            self.assertEqual(result, 1)
            self.assertEqual(len(modules), 1)
            self.assertEqual(modules[0]["status"], "FAIL")
            self.assertEqual(modules[0]["recovery"],
                             "unavailable (external server)")
            server.recover.assert_not_called()
            self.assertEqual(calls.call_count, 1)

    def test_failure_without_followup(self):
        for count, fast in ((1, False), (2, True)):
            with self.subTest(count=count, fast=fast), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                text = "Ran 1 test in 0s\nFAILED (failures=1)\n"
                results = [(text, 1, False)] * count
                result, modules, server, calls = self.exercise(root, results,
                                                             fail_fast=fast)
                self.assertEqual(result, 1)
                self.assertEqual(len(modules), 1)
                server.probe.assert_called_once_with("lldb")
                server.recover.assert_not_called()
                self.assertEqual(calls.call_count, 1)

    def test_external_ownership(self):
        args = argparse.Namespace(server_url="connect://localhost:1234",
                                  android=False)
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness.subprocess, "Popen") as popen:
            server = harness.Server(args, pathlib.Path(directory), None, {})
            server.start()
            server.stop()
            self.assertFalse(server.owned)
            with self.assertRaisesRegex(RuntimeError, "external server"):
                server.recover("lldb")
            popen.assert_not_called()

    def test_android_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(working_directory="/data/local/tmp/tests",
                                      dsx=root / "dsx", arch="x86_64",
                                      trace=False)
            with patch.object(harness.subprocess, "run") as run, \
                 patch.object(harness.subprocess, "Popen") as popen:
                _, working = harness.android_server(
                    "adb", args, root, {}, root / "server-001.log", deploy=False)
            self.assertIn("--listen 127.0.0.1:0", popen.call_args.args[0][2])
            self.assertEqual(working, args.working_directory)
            run.assert_not_called()

    def test_server_port(self):
        # Execute a real listener to ensure readiness supplies the port of the
        # still-owned socket, rather than a separately probed/released port.
        popen = subprocess.Popen
        script = ("import socket; s=socket.socket(); "
                  "s.bind(('127.0.0.1',0)); s.listen(); "
                  "print('Listening on port',s.getsockname()[1],flush=True); "
                  "c,_=s.accept(); c.sendall(b'ready'); c.close()")
        for android in (False, True):
            with self.subTest(android=android), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                args = argparse.Namespace(server_url=None, android=android,
                                          android_boot_timeout=1, trace=False,
                                          working_directory=None,
                                          dsx=root / "dsx", server_timeout=10)

                def launch(command, **kwargs):
                    command = " ".join(command)
                    self.assertIn("--listen 127.0.0.1:0", command)
                    return popen([sys.executable, "-c", script], **kwargs)

                with patch.object(harness, "tool", return_value="adb"), \
                     patch.object(harness, "wait_android"), \
                     patch.object(harness.subprocess, "Popen",
                                  side_effect=launch):
                    server = harness.Server(args, root, root, os.environ.copy())
                    server.generation = 1
                    try:
                        server.start()
                        host = "localhost" if android else "127.0.0.1"
                        prefix = f"connect://{host}:"
                        self.assertTrue(server.url.startswith(prefix))
                        port = int(server.url.rpartition(":")[2])
                        with socket.create_connection(("127.0.0.1", port),
                                                      timeout=5) as client:
                            with client.makefile("rb") as stream:
                                self.assertEqual(stream.read(5), b"ready")
                        self.assertEqual(server.process.wait(timeout=5), 0)
                    finally:
                        server.stop()

    def test_server_readiness(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "server.log"
            process = Mock()
            process.poll.return_value = None
            for initial in ("", "Listening on port ", "Listening on port 12",
                            "Listening on port 0\n",
                            "Listening on port 65536\n",
                            '[trace] "Listening on port 1234"\n'):
                with self.subTest(initial=initial):
                    log.write_text(initial)
                    with patch.object(harness.time, "sleep",
                                      side_effect=lambda _: log.write_text(
                                          "Listening on port 4321\r\n")):
                        self.assertEqual(harness.wait(process, log, 1), 4321)
            process.poll.return_value = 1
            with self.assertRaisesRegex(RuntimeError, "status 1"):
                harness.wait(process, log, 1)

    def test_android_cleanup(self):
        args = argparse.Namespace(server_url=None, android=True,
                                  android_boot_timeout=1)
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness, "tool", return_value="adb"), \
             patch.object(harness, "wait_android"), \
             patch.object(harness, "terminate") as terminate, \
             patch.object(harness.subprocess, "run") as run:
            root = pathlib.Path(directory)
            server = harness.Server(args, root, None, {})
            process = server.process = Mock(pid=999)
            server.log.write_text("DSX_PID:123\r\nListening on port 1234\r\n")
            server.stop()
            command = run.call_args.args[0]
            self.assertEqual(command[:2], ["adb", "shell"])
            self.assertIn("kill -KILL 123", command[2])
            self.assertIn("readlink /proc/123/exe", command[2])
            self.assertNotIn("999", command[2])
            terminate.assert_called_once_with(process)
            self.assertIsNone(server.process)

    def test_android_recovery_connection(self):
        args = argparse.Namespace(server_url=None, android=True,
                                  android_boot_timeout=2)
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness, "tool", return_value="adb"), \
             patch.object(harness, "wait_android") as wait:
            server = harness.Server(args, pathlib.Path(directory), None, {})
            wait.reset_mock()
            calls = Mock()
            calls.attach_mock(wait, "wait")
            server.stop = calls.stop
            server.start = calls.start
            server.probe = calls.probe
            server.recover("lldb")
            self.assertEqual([call[0] for call in calls.mock_calls],
                             ["wait", "stop", "start", "probe"])
            wait.assert_called_once_with("adb", 2)
            calls.stop.assert_called_once_with(strict=True)

    def test_android_boot_deadline(self):
        with patch.object(harness.time, "monotonic", return_value=1), \
             patch.object(harness.subprocess, "run",
                          return_value=Mock(returncode=0, stdout="1\n")) as run:
            harness.wait_android("adb", 2)
        self.assertEqual(run.call_count, 2)
        for call in run.call_args_list:
            self.assertEqual(call.kwargs["timeout"], 2)

    def test_android_cleanup_failure(self):
        args = argparse.Namespace(server_url=None, android=True,
                                  android_boot_timeout=1)
        for strict in (False, True):
            with self.subTest(strict=strict), \
                 tempfile.TemporaryDirectory() as directory, \
                 patch.object(harness, "tool", return_value="adb"), \
                 patch.object(harness, "wait_android"), \
                 patch.object(harness, "terminate") as terminate, \
                 patch.object(harness.subprocess, "run",
                              side_effect=subprocess.CalledProcessError(
                                  1, ["adb", "shell"])), \
                 patch.object(harness.sys, "stderr"):
                server = harness.Server(args, pathlib.Path(directory), None, {})
                process = server.process = Mock()
                server.log.write_text("DSX_PID:123\n")
                if strict:
                    with self.assertRaises(subprocess.CalledProcessError):
                        server.stop(strict=True)
                else:
                    server.stop()
                terminate.assert_called_once_with(process)
                self.assertIsNone(server.process)

    def test_probe_failure(self):
        args = argparse.Namespace(server_url="connect://localhost:1234",
                                  android=False, server_timeout=1,
                                  platform="remote-linux")
        with tempfile.TemporaryDirectory() as directory:
            server = harness.Server(args, pathlib.Path(directory), None, {})
            for status, timedout in ((1, False), (-9, True)):
                with patch.object(harness, "execute",
                                  return_value=(status, timedout)):
                    with self.assertRaisesRegex(RuntimeError, "probe failed"):
                        server.probe("lldb")

    def test_probe_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(server_url=None, android=False,
                                      server_timeout=1.5,
                                      platform="remote-macosx",
                                      dsx=root / "DSX build" / "dsx")
            server = harness.Server(args, root, None, {})
            server.url = "connect://localhost:1234"
            (root / "probe-000.log").write_text("DSX_LIFECYCLE_OK\n")
            with patch.object(harness, "execute",
                              return_value=(0, False)) as execute:
                server.probe("lldb")
            command = execute.call_args.args[0]
            executable = f"'{args.dsx.resolve().as_posix()}'"
            remote = (root / "platform" / "dsx").as_posix()
            target = f"target create {executable} --remote-file {remote}"
            self.assertEqual(command[-12:-8], [
                "-o", target,
                "-o", "process launch --stop-at-entry --no-stdio -- version"])
            self.assertIn("AddListener(listener, ", command[-7])
            self.assertEqual(command[-6:-4], ["-o", "process kill"])
            self.assertIn("listener.WaitForEvent(2, event)", command[-3])
            self.assertIn("GetStateFromEvent(event)", command[-3])
            self.assertIn("p.GetExitDescription() == 'killed'", command[-3])
            self.assertEqual(execute.call_args.args[3], 1.5)

            # LLDB can report a successful `process kill` command even when
            # the remote reply was a stop packet rather than an exit packet.
            (root / "probe-000.log").write_text(
                "script print('DSX_LIFECYCLE_OK')\nDSX_LIFECYCLE_FAILED\n")
            with patch.object(harness, "execute", return_value=(0, False)):
                with self.assertRaisesRegex(RuntimeError, "lifecycle probe"):
                    server.probe("lldb")

            for platform in ("remote-linux", "remote-android", "remote-windows"):
                args.platform = platform
                with patch.object(harness, "execute",
                                  return_value=(0, False)) as execute:
                    server.probe("lldb")
                self.assertFalse(any("process launch" in argument
                                     for argument in execute.call_args.args[0]))

    def test_probe_external(self):
        args = argparse.Namespace(server_url="connect://localhost:1234",
                                  android=False, server_timeout=1,
                                  platform="remote-linux")
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness, "execute", return_value=(0, False)) as run:
            server = harness.Server(args, pathlib.Path(directory), None, {})
            server.probe("lldb")
            self.assertFalse(any("process launch" in argument
                                 for argument in run.call_args.args[0]))

    def test_execute(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "test.log"
            result = harness.execute([sys.executable, "-c", "print('hello')"],
                                     os.environ.copy(), log, 10)
            self.assertEqual(result, (0, False))
            self.assertEqual(log.read_text().strip(), "hello")

    def test_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "timeout.log"
            code = "import time; print('started', flush=True); time.sleep(30)"
            def diagnose(process, path, server):
                # Probes without the Python bootstrap must not receive a
                # signal whose default action terminates them before sampling.
                self.assertIsNone(process.poll())

            with patch.object(harness, "diagnose", side_effect=diagnose):
                status, timedout = harness.execute([sys.executable, "-c", code],
                                                  os.environ.copy(), log, 1)
            self.assertTrue(timedout)
            self.assertNotEqual(status, 0)
            self.assertIn("started", log.read_text())

    def test_android_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            server = object.__new__(harness.Server)
            server.adb = "/test/adb"
            server.environment = {"PATH": "/test"}
            path = pathlib.Path(directory) / "test.log"

            def run(command, **kwargs):
                self.assertEqual(kwargs["env"], server.environment)
                self.assertGreater(kwargs["timeout"], 0)
                self.assertLessEqual(kwargs["timeout"], 10)
                kwargs["stdout"].write("device diagnostic\n")
                return subprocess.CompletedProcess(command, 0)

            # Fixed elapsed times keep this budget assertion independent of
            # clock resolution and floating-point rounding on the runner.
            with patch.object(harness.time, "monotonic",
                              side_effect=[100, 100, 101, 102, 103]), \
                 patch.object(harness.subprocess, "run",
                              side_effect=run) as call:
                server.diagnose(path)
                self.assertEqual(call.call_count, 4)
                self.assertEqual([item.kwargs["timeout"]
                                  for item in call.call_args_list], [10, 9, 8, 7])
                self.assertIn("/proc/sys/kernel/random/boot_id",
                              call.call_args_list[0].args[0][2])
                self.assertIn("dmesg | tail -n 120",
                              call.call_args_list[0].args[0][2])
                self.assertEqual(call.call_args_list[1].args[0][1:4],
                                 ["logcat", "-b", "crash"])
                self.assertEqual(call.call_args_list[2].args[0][1:],
                                 ["logcat", "-b", "main", "-b", "system",
                                  "-d", "-t", "200", "ActivityManager:I",
                                  "lowmemorykiller:I", "adbd:I", "*:S"])
            text = path.with_suffix(".android.log").read_text()
            self.assertEqual(text.count("device diagnostic"), 4)

    def test_android_diagnostic_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            server = object.__new__(harness.Server)
            server.adb = "/test/adb"
            server.environment = {}
            path = pathlib.Path(directory) / "test.log"
            error = subprocess.TimeoutExpired("adb", 10)
            with patch.object(harness.time, "monotonic",
                              side_effect=[0, 0, 11]), \
                 patch.object(harness.subprocess, "run",
                              side_effect=error) as call:
                server.diagnose(path)
                self.assertEqual(call.call_count, 1)
            self.assertIn("Android diagnostics failed",
                          path.with_suffix(".android.log").read_text())

    def test_android_diagnostic_scope(self):
        server = object.__new__(harness.Server)
        server.adb = None
        with patch.object(harness.subprocess, "run") as call:
            server.diagnose(pathlib.Path("unused/test.log"))
            call.assert_not_called()

    def test_diagnostics(self):
        processes = "\n".join([
            "10 1 S 01:00 client", "11 10 S 00:59 fixture",
            "20 1 S 02:00 platform", "21 20 S 00:59 dsx",
            "22 21 T 00:58 inferior", "30 1 S 01:00 unrelated",
            "40 1 S 01:00 /usr/libexec/taskgated",
            "41 1 S 01:00 /usr/libexec/authd"])
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
             patch.object(harness.sys, "platform", "darwin"), \
             patch.object(harness.subprocess, "run") as run:
            run.side_effect = lambda command, **kwargs: Mock(
                stdout=processes if command[0] == "ps" else "owned sockets")
            path = pathlib.Path(directory) / "test.log"
            server = Mock(process=Mock(pid=20), log=path.parent / "server.log")
            server.log.write_text("x" * 5000 + "last packet\n")
            output = io.StringIO()
            with patch.object(harness.sys, "stdout", output):
                harness.diagnose(Mock(pid=10), path, server)
            self.assertIn("last packet", output.getvalue())
            self.assertNotIn("x" * 4096, output.getvalue())
            samples = [int(call.args[0][1]) for call in run.call_args_list
                       if call.args[0][0] == "sample"]
            self.assertCountEqual(samples, [10, 20, 21, 11, 22, 40, 41])
            for call in run.call_args_list:
                if call.args[0][0] == "sample":
                    self.assertIn("-nodsyms", call.args[0])
            log = path.with_suffix(".diagnostics.log").read_text()
            self.assertIn("inferior", log)
            self.assertNotIn("unrelated", log)
            sockets = [call.args[0] for call in run.call_args_list
                       if call.args[0][0] == "lsof"]
            self.assertEqual(sockets,
                             [["lsof", "-nP", "-a", "-p", "10,11,20,21,22",
                               "-iTCP"]])
            self.assertTrue(all(call.kwargs["timeout"] <= 10
                                for call in run.call_args_list))

    def test_diagnostic_precision(self):
        # Adding the budget to this timestamp rounds upwards. An unchanged
        # monotonic clock must still produce a timeout no greater than 10.
        timestamp = math.nextafter(507.0, 0.0)
        for android in (False, True):
            with self.subTest(android=android), \
                 tempfile.TemporaryDirectory() as directory, \
                 patch.object(harness.time, "monotonic",
                              return_value=timestamp), \
                 patch.object(harness.subprocess, "run") as run:
                run.return_value = Mock(stdout="", returncode=0)
                path = pathlib.Path(directory) / "test.log"
                if android:
                    server = object.__new__(harness.Server)
                    server.adb = "/test/adb"
                    server.environment = {}
                    server.diagnose(path)
                else:
                    harness.diagnose(Mock(pid=10), path)
                self.assertTrue(run.call_args_list)
                for call in run.call_args_list:
                    self.assertGreater(call.kwargs["timeout"], 0)
                    self.assertLessEqual(call.kwargs["timeout"], 10)

    def test_sampling_authorization(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}), \
             patch.object(harness.subprocess, "run") as run:
            run.return_value.stdout = "10 1 S 01:00 client"
            path = pathlib.Path(directory) / "test.log"
            harness.diagnose(Mock(pid=10), path)
            command = next(call.args[0] for call in run.call_args_list
                           if "sample" in call.args[0])
            self.assertEqual(command[:4], ["sudo", "-n", "sample", "10"])

    def test_sampling_missing_output(self):
        for status in (0, 1):
            with self.subTest(status=status), \
                 tempfile.TemporaryDirectory() as directory, \
                 patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
                 patch.object(harness.subprocess, "run") as run:
                run.return_value = Mock(returncode=status, stdout="")
                path = pathlib.Path(directory) / "test.log"
                harness.diagnose(Mock(pid=10), path)
                text = path.with_suffix(".diagnostics.log").read_text()
                self.assertIn(f"Sample unavailable: 10 (exit status {status})",
                              text)

    def test_sampling_exhausted_budget(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness.time, "monotonic", side_effect=[0, 11]), \
             patch.object(harness.subprocess, "run") as run:
            run.return_value = Mock(stdout="")
            path = pathlib.Path(directory) / "test.log"
            harness.diagnose(Mock(pid=10), path)
            text = path.with_suffix(".diagnostics.log").read_text()
            self.assertIn("Sample budget exhausted before capture: 10", text)
            self.assertFalse(any("sample" in call.args[0]
                                 for call in run.call_args_list))

    def test_sampling_precedes_enumeration(self):
        sampled = {pid: threading.Event() for pid in (10, 20)}

        def capture(command, **kwargs):
            if command[0] == "sample":
                sampled[int(command[1])].set()
            if command[0] == "ps":
                # Even a stalled process inventory must not delay sampling
                # the client and server whose identifiers are already known.
                for event in sampled.values():
                    self.assertTrue(event.wait(2))
                raise subprocess.TimeoutExpired(command, 2)
            return Mock(stdout="")

        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
             patch.object(harness.subprocess, "run", side_effect=capture):
            path = pathlib.Path(directory) / "test.log"
            server = Mock(process=Mock(pid=20), log=path.parent / "server.log")
            harness.diagnose(Mock(pid=10), path, server)

    def test_diagnostics_failure(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness.sys, "platform", "darwin"), \
             patch.object(harness.subprocess, "run", side_effect=OSError):
            path = pathlib.Path(directory) / "test.log"
            harness.diagnose(Mock(pid=10), path)
            log = path.with_suffix(".diagnostics.log").read_text()
            self.assertIn("Timeout diagnostics failed", log)

    def test_socket_diagnostics_failure(self):
        for failure in (OSError("lsof unavailable"),
                        subprocess.TimeoutExpired(["lsof"], 2)):
            with self.subTest(failure=failure), \
                 tempfile.TemporaryDirectory() as directory, \
                 patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
                 patch.object(harness.subprocess, "run") as run:
                def capture(command, **kwargs):
                    if command[0] == "lsof":
                        raise failure
                    return Mock(stdout="10 1 S 01:00 client")

                run.side_effect = capture
                path = pathlib.Path(directory) / "test.log"
                harness.diagnose(Mock(pid=10), path)
                self.assertTrue(any(call.args[0][:2] == ["sample", "10"]
                                    for call in run.call_args_list))
                self.assertIn("Socket diagnostics failed",
                              path.with_suffix(".diagnostics.log").read_text())

    def test_process_diagnostics_failure(self):
        for failure in (OSError("ps unavailable"),
                        subprocess.TimeoutExpired(["ps"], 2)):
            with self.subTest(failure=failure), \
                 tempfile.TemporaryDirectory() as directory, \
                 patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
                 patch.object(harness.subprocess, "run") as run:
                def capture(command, **kwargs):
                    if command[0] == "ps":
                        raise failure
                    return Mock(stdout="")

                run.side_effect = capture
                path = pathlib.Path(directory) / "test.log"
                server = Mock(process=Mock(pid=20),
                              log=path.parent / "server.log")
                harness.diagnose(Mock(pid=10), path, server)
                samples = [call.args[0][1] for call in run.call_args_list
                           if call.args[0][0] == "sample"]
                self.assertCountEqual(samples, ["10", "20"])
                self.assertIn("Process diagnostics failed",
                              path.with_suffix(".diagnostics.log").read_text())

    def test_sampling_timeout(self):
        result = Mock(stdout="10 1 S 01:00 client\n20 1 S 02:00 platform")
        failure = subprocess.TimeoutExpired(["sample", "10"], 3)

        def sample(command, **kwargs):
            if command[0] == "ps":
                return result
            if command[1] == "10":
                raise failure
            return Mock()

        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), \
             patch.object(harness.subprocess, "run",
                          side_effect=sample) as run:
            path = pathlib.Path(directory) / "test.log"
            server = Mock(process=Mock(pid=20), log=path.parent / "server.log")
            harness.diagnose(Mock(pid=10), path, server)
            self.assertTrue(any(call.args[0][:2] == ["sample", "20"]
                                for call in run.call_args_list))
            self.assertIn("Sample deadline reached: 10",
                          path.with_suffix(".diagnostics.log").read_text())

    def test_sampling_parallel(self):
        barrier = threading.Barrier(3)

        def sample(command, **kwargs):
            if command[0] == "ps":
                return Mock(stdout="10 1 S 01:00 client\n"
                            "20 1 S 01:00 platform\n21 20 S 01:00 dsx")
            if command[0] == "lsof":
                return Mock(stdout="")
            barrier.wait(timeout=2)
            return Mock()

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(harness.subprocess, "run", side_effect=sample):
            path = pathlib.Path(directory) / "test.log"
            server = Mock(process=Mock(pid=20), log=path.parent / "server.log")
            harness.diagnose(Mock(pid=10), path, server)

    def test_inherited_output(self):
        # A descendant retaining stdout must not keep a finished module alive.
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            release, finished = root / "release", root / "finished"
            child = ("import os,pathlib,time;"
                     f"release=pathlib.Path({str(release)!r});"
                     "deadline=time.monotonic()+60\n"
                     "while not release.exists() and time.monotonic()<deadline:"
                     " time.sleep(0.01)\n"
                     "os.close(1);os.close(2);"
                     f"pathlib.Path({str(finished)!r}).touch()")
            parent = ("import subprocess,sys;"
                      f"subprocess.Popen([sys.executable,'-c',{child!r}],"
                      "close_fds=False);print('parent finished')")
            scripts = pathlib.Path(spec.origin).parent
            driver = ("import os,pathlib,runpy,sys;"
                      f"sys.path.insert(0,{str(scripts)!r});"
                      f"h=runpy.run_path({str(spec.origin)!r});"
                      f"r=h['execute']([sys.executable,'-c',{parent!r}],"
                      f"os.environ.copy(),pathlib.Path({str(root / 'log')!r}),0);"
                      "assert r==(0,False),r")
            try:
                # This checks completion without EOF, not a module deadline.
                # Startup under load must not invoke Darwin timeout diagnostics
                # inside a shorter outer deadline and obscure that assertion.
                subprocess.run([sys.executable, "-c", driver], check=True,
                               capture_output=True, text=True, timeout=30)
                self.assertFalse(finished.exists())
            finally:
                release.touch()
                deadline = time.monotonic() + 5
                while not finished.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
            self.assertTrue(finished.exists())

    @unittest.skipIf(sys.platform == "win32", "POSIX process groups")
    def test_group(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "group.log"
            script = ("import json,os;print(json.dumps([os.getpid(),"
                      "os.getpgrp(),os.getsid(0)]))")
            status, timedout = harness.execute(
                [sys.executable, "-c", script], os.environ.copy(), path, 5)
            self.assertEqual(status, 0)
            self.assertFalse(timedout)
            process, group, session = json.loads(path.read_text())
            self.assertEqual(process, group)
            self.assertEqual(session, os.getsid(0))
            self.assertNotEqual(process, session)

    def test_android(self):
        import argparse
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(working_directory="/data/local/tmp/tests",
                                      dsx=root / "dsx", arch="x86_64",
                                      trace=True)
            runtimes = [root / "libc++_shared.so", root / "libclang_rt.asan.so"]
            with patch.object(harness, "android_runtimes",
                              return_value=runtimes), \
                 patch.object(harness.subprocess, "run") as run, \
                 patch.object(harness.subprocess, "Popen") as popen:
                _, working = harness.android_server(
                    "adb", args, root, {}, root / "server.log")
                command = popen.call_args.args[0]
                self.assertEqual(command[:2], ["adb", "shell"])
                export = f"export LD_LIBRARY_PATH={harness.kAndroidRuntime}"
                self.assertIn(f"{export} && sh -c", command[2])
                run.assert_any_call(
                    ["adb", "push", *map(str, runtimes),
                     harness.kAndroidRuntime], check=True, timeout=60)
                self.assertIn("--listen 127.0.0.1:0", command[2])
                self.assertFalse(any("forward" in call.args[0]
                                     for call in run.call_args_list))
                run.reset_mock()
                harness.android_server("adb", args, root, {},
                                       root / "server.log", deploy=False)
                self.assertEqual(popen.call_args.args[0], command)
                run.assert_not_called()
            self.assertEqual(working, args.working_directory)

    @unittest.skipIf(sys.platform == "win32", "requires a POSIX shell")
    def test_android_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            executable = root / "dsx"
            executable.write_text('#!/bin/sh\nprintf "PID:%s\\n" "$$"\n'
                                  'printf "parent:%s\\n" "$LD_LIBRARY_PATH"\n'
                                  'exec /bin/sh -c \'printf "child:%s\\n" '
                                  '"$LD_LIBRARY_PATH"; '
                                  'if [ "$STATUS" = signal ]; then '
                                  'kill -TERM $$; fi; exit "$STATUS"\'\n')
            executable.chmod(0o755)
            args = argparse.Namespace(working_directory=None, trace=False)
            with patch.object(harness.subprocess, "Popen") as popen:
                harness.android_server("adb", args, root, {},
                                       root / "server.log", deploy=False)
                command = popen.call_args.args[0][2]
            # Execute the remote shell sequence locally with a fixture in place
            # of DSX, checking that spawned servers inherit the loader path.
            command = command.replace("/data/local/tmp", str(root))
            boot = root / "boot"
            boot.write_text("test-boot\n")
            command = command.replace("/proc/sys/kernel/random/boot_id",
                                      str(boot))
            for value, status in (("0", 0), ("7", 7), ("signal", 143)):
                with self.subTest(status=status):
                    result = subprocess.run(["/bin/sh", "-c", command],
                                            capture_output=True, text=True,
                                            timeout=5,
                                            env={"PATH": "/usr/bin:/bin",
                                                 "STATUS": value})
                    self.assertEqual(result.returncode, status, result.stderr)
                    runtime = root / "dsx-runtime"
                    self.assertIn(f"parent:{runtime}\nchild:{runtime}\n",
                                  result.stdout)
                    lines = result.stdout.splitlines()
                    self.assertEqual(lines[0], "DSX_BOOT:test-boot")
                    self.assertTrue(lines[1].startswith("DSX_PID:"))
                    self.assertEqual(lines[2], lines[1].removeprefix("DSX_"))
                    self.assertEqual(lines[-1], f"DSX_EXIT:{status}")


class Upstream(unittest.TestCase):
    def setUp(self):
        source = os.environ.get("LLVM_SOURCE", "llvm-project")
        self.source = pathlib.Path(source).resolve()
        if not (self.source / "lldb/test/API/lit.cfg.py").is_file():
            self.skipTest("set LLVM_SOURCE to validate LLDB's lit integration")

    def test_source_paths(self):
        expected = self.source
        for source in (str(expected), os.path.relpath(expected)):
            with self.subTest(source=source), \
                 patch.dict(os.environ, {"LLVM_SOURCE": source}):
                self.setUp()
                self.assertEqual(self.source, expected)

    def test_logging(self):
        source = self.source / "lldb/packages/Python/lldbsuite/test/lldbtest.py"
        tree = ast.parse(source.read_text())
        base = next(node for node in tree.body
                    if isinstance(node, ast.ClassDef) and node.name == "Base")
        names = {"enableLogChannelsForCurrentTest",
                 "disableLogChannelsForCurrentTest"}
        methods = ast.Module(body=[node for node in base.body
                                   if isinstance(node, ast.FunctionDef) and
                                   node.name in names], type_ignores=[])
        code = compile(methods, str(source), "exec")
        for mode in ("normal", "destroyed", "skip", "setup", "teardown",
                     "partial", "disabled"):
            with self.subTest(mode=mode), \
                 tempfile.TemporaryDirectory() as directory:
                active = set()
                events = []
                result = Mock()
                result.Succeeded.return_value = True
                debugger = Mock()

                def disable(command, output):
                    active.discard(command.removeprefix("log disable "))
                    events.append(command)

                interpreter = debugger.GetCommandInterpreter.return_value
                interpreter.HandleCommand.side_effect = disable
                api = Mock(remote_platform=Mock())
                api.remote_platform.Get.return_value.Success.return_value = False
                api.SBDebugger.Create.return_value = debugger
                api.SBCommandReturnObject.return_value = result
                channels = ([] if mode == "disabled" else
                            ["lldb step", "gdb-remote packets"])
                namespace = {"lldb": api, "os": os,
                             "lldbtest_config": Mock(channels=channels)}
                exec(code, namespace)

                class Case(unittest.TestCase):
                    def setUp(self):
                        self.log_files = []
                        self.hooks = []
                        self.res = result
                        self.ci = Mock()

                        def enable(command, output):
                            channel = command.split()[-2]
                            active.add(channel)
                            if mode == "partial" and channel == "gdb-remote":
                                output.Succeeded.return_value = False

                        self.ci.HandleCommand.side_effect = enable
                        self.enableLogChannelsForCurrentTest()
                        if mode == "skip":
                            self.skipTest("skipped after logging started")
                        if mode == "setup":
                            raise RuntimeError("setup failed")

                    def getLogBasenameForCurrentTest(self):
                        return str(pathlib.Path(directory) / "Incomplete")

                    def addTearDownHook(self, hook):
                        self.hooks.append(hook)

                    def runTest(self):
                        if mode == "destroyed":
                            self.ci.HandleCommand.side_effect = AssertionError(
                                "using the destroyed debugger")

                    def tearDown(self):
                        if mode == "teardown":
                            raise RuntimeError("teardown failed")
                        for hook in reversed(self.hooks):
                            hook()

                for name in names:
                    setattr(Case, name, namespace[name])
                case = Case()
                outcome = unittest.TestResult()
                outcome.stopTest = lambda test: events.append(set(active))
                # A fresh return object must not inherit an enable failure.
                api.SBCommandReturnObject.side_effect = lambda: Mock(
                    Succeeded=Mock(return_value=True))
                case.run(outcome)
                self.assertEqual(outcome.testsRun, 1)
                self.assertEqual(outcome.failures, [])
                self.assertEqual(len(outcome.errors),
                                 int(mode in ("setup", "teardown", "partial")))
                self.assertEqual(len(outcome.skipped), int(mode == "skip"))
                self.assertEqual(events[-1], set())
                if channels:
                    api.SBDebugger.Create.assert_called_once_with(False)
                    api.SBDebugger.Destroy.assert_called_once_with(debugger)
                    self.assertEqual(events[:-1],
                                     ["log disable lldb",
                                      "log disable gdb-remote"])
                else:
                    api.SBDebugger.Create.assert_not_called()

    def test_platform_timeout(self):
        package = self.source / "lldb/packages/Python/lldbsuite/test"
        tree = ast.parse((package / "configuration.py").read_text())
        timeout = next(node.value.value for node in tree.body
                       if isinstance(node, ast.Assign) and
                       any(isinstance(target, ast.Name) and
                           target.id == "packet_timeout"
                           for target in node.targets))
        self.assertEqual(timeout, 60)
        tree = ast.parse((package / "dotest.py").read_text())
        setup = next(node for node in ast.walk(tree)
                     if isinstance(node, ast.If) and
                     isinstance(node.test, ast.Attribute) and
                     node.test.attr == "lldb_platform_url" and
                     isinstance(node.test.value, ast.Name) and
                     node.test.value.id == "configuration")
        code = compile(ast.Module(body=[setup], type_ignores=[]),
                       str(package / "dotest.py"), "exec")
        for failed in (False, True):
            with self.subTest(failed=failed):
                api = Mock()
                events = []
                debugger = api.SBDebugger.Create.return_value
                result = api.SBDebugger.SetInternalVariable.return_value
                result.Fail.return_value = failed
                api.SBDebugger.SetInternalVariable.side_effect = (
                    lambda *args: (events.append("timeout"), result)[1])
                api.SBDebugger.Destroy.side_effect = (
                    lambda *args: events.append("destroy"))
                connected = Mock(Success=Mock(return_value=True))
                api.remote_platform.ConnectRemote.side_effect = (
                    lambda *args: (events.append("connect"), connected)[1])
                namespace = {"lldb": api, "configuration": Mock(
                    lldb_platform_url="connect://localhost:1234",
                    lldb_platform_name="remote-windows",
                    packet_timeout=timeout), "print": Mock()}
                if failed:
                    with self.assertRaises(RuntimeError):
                        exec(code, namespace)
                else:
                    exec(code, namespace)
                api.SBDebugger.Create.assert_called_once_with(False)
                api.SBDebugger.SetInternalVariable.assert_called_once_with(
                    "plugin.process.gdb-remote.packet-timeout", "60",
                    debugger.GetInstanceName())
                api.SBDebugger.Destroy.assert_called_once_with(debugger)
                self.assertEqual(events, ["timeout", "destroy"] +
                                 ([] if failed else ["connect"]))

    def test_simulator_sdk(self):
        source = (self.source / "lldb/packages/Python/lldbsuite/test" /
                  "decorators.py")
        tree = ast.parse(source.read_text())
        function = next(node for node in tree.body
                        if isinstance(node, ast.FunctionDef) and
                        node.name == "apple_simulator_test")
        code = compile(ast.Module(body=[function], type_ignores=[]),
                       str(source), "exec")
        for platform, runtime in (("iphone", "iOS"), ("appletv", "tvOS"),
                                  ("watch", "watchOS")):
            for sdk, available in ((True, True), (True, False), (False, False)):
                with self.subTest(platform=platform, sdk=sdk,
                                  available=available):
                    output = Mock()
                    device = {"isAvailable": available}
                    devices = {"devices": {runtime: [device]}}
                    output.check_output.side_effect = (
                        [b"/SDK", json.dumps(devices).encode()] if sdk else
                        subprocess.CalledProcessError(1, "xcrun"))
                    output.CalledProcessError = subprocess.CalledProcessError
                    output.DEVNULL = subprocess.DEVNULL
                    namespace = {"subprocess": output, "json": json,
                                 "skipTestIfFn": lambda function: function,
                                 "lldbplatformutil": Mock(
                                     getHostPlatform=lambda: "darwin",
                                     getArchitecture=lambda: "arm64")}
                    exec(code, namespace)
                    reason = namespace["apple_simulator_test"](platform)()
                    self.assertEqual(reason is None, sdk and available)
                    calls = output.check_output.call_args_list
                    self.assertEqual(calls[0].args[0],
                                     ["xcrun", "--sdk", platform + "simulator",
                                      "--show-sdk-path"])
                    self.assertEqual(len(calls), 2 if sdk else 1)
                    if sdk:
                        self.assertEqual(calls[1].args[0],
                                         ["xcrun", "simctl", "list", "-j",
                                          "devices"])
        for host, arch in (("linux", "aarch64"), ("windows", "x86_64"),
                           ("darwin", "arm64e")):
            with self.subTest(host=host, arch=arch):
                output = Mock()
                namespace.update(subprocess=output, lldbplatformutil=Mock(
                    getHostPlatform=lambda: host, getArchitecture=lambda: arch))
                exec(code, namespace)
                reason = namespace["apple_simulator_test"]("iphone")()
                self.assertIsNotNone(reason)
                output.check_output.assert_not_called()

    def test_simulator_process_list(self):
        source = (self.source / "lldb/test/API/macosx/simulator" /
                  "TestSimulatorPlatform.py")
        tree = ast.parse(source.read_text())
        expression = next(node for node in ast.walk(tree)
                          if isinstance(node, ast.BinOp) and
                          isinstance(node.left, ast.Constant) and
                          isinstance(node.left.value, str) and
                          "matching process" in node.left.value)
        code = compile(ast.Expression(expression), str(source), "eval")
        pattern = eval(code, {"expected_platform": "ios"})
        for text in ('1 matching process was found on "ios-simulator"',
                     '2 matching processes were found on "ios-simulator"'):
            self.assertRegex(text, pattern)
        self.assertNotRegex('No matching processes were found', pattern)

    def test_windows_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(
                source=self.source, tools=root, arch="i386",
                triple="i686-unknown-windows-msvc", compiler=root / "clang",
                android=False, working_directory=None, exclusions=None,
                platform="remote-windows", tests=".", trace=False)
            with patch.object(harness, "tool",
                              side_effect=lambda name, directory=None: name), \
                 patch.object(harness.subprocess, "check_output",
                              return_value="LLDB fixture"):
                _, config = harness.configuration(args, root)
            command = config.test_format.dotest_cmd
            self.assertEqual(command[command.index("--triple") + 1],
                             "i386-unknown-windows-msvc")
            self.assertEqual(args.triple, "i686-unknown-windows-msvc")

    def test_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(
                source=self.source, tools=root, arch="arm64",
                triple="aarch64-unknown-linux-gnu", compiler=root / "clang",
                android=False, working_directory=None, exclusions=None,
                platform="remote-linux", tests=".", trace=False)
            args.compiler = Mock(spec=pathlib.Path)
            args.compiler.absolute.return_value = root / "clang"
            with patch.object(harness, "tool",
                              side_effect=lambda name, directory=None: name), \
                 patch.object(harness.subprocess, "check_output",
                              return_value="LLDB fixture"):
                settings, config = harness.configuration(args, root)
            command = config.test_format.dotest_cmd
            args.compiler.resolve.assert_not_called()
            self.assertEqual(config.test_compiler, str(root / "clang"))
            self.assertIn("--out-of-tree-debugserver", command)
            self.assertIn("remote-linux", command)
            self.assertIn(str(root / "lldb-test-build.noindex"), command)
            self.assertIn("--triple", command)
            self.assertNotIn("--channel", command)
            self.assertNotIn("-t", command)
            if sys.platform == "win32":
                self.assertIn("LLDB_LAUNCH_FLAG_USE_PIPES=1", command)

            if sys.platform == "darwin":
                args.compiler = None
                apple = root / "Xcode" / "clang"
                with patch.object(harness, "tool",
                                  side_effect=lambda name, directory=None: name), \
                     patch.object(harness.subprocess, "check_output",
                                  return_value=str(apple) + "\n") as output:
                    _, darwin = harness.configuration(args, root)
                output.assert_any_call(["xcrun", "--find", "clang"], text=True,
                                       env=darwin.environment)
                self.assertEqual(darwin.test_compiler, str(apple))
                self.assertEqual(darwin.environment["TOOLCHAINS"],
                                 "com.apple.dt.toolchain.XcodeDefault")

            api = root / "api"
            api.mkdir()
            (api / "TestExample.py").touch()
            (api / "test_helper.py").touch()
            nested = api / "nested"
            nested.mkdir()
            (nested / "TestExcluded.py").touch()
            (nested / "lit.local.cfg").write_text(
                "config.excludes = ['TestExcluded.py']\n")
            config.test_source_root = str(api)
            found = list(harness.tests(args, settings, config))
            self.assertEqual([pathlib.Path(test.getSourcePath()).name
                              for test in found], ["TestExample.py"])
            args.tests = ".,TestExample.py"
            self.assertEqual(len(list(harness.tests(args, settings, config))), 1)
            args.exclusions = root / "exclusions"
            args.exclusions.write_text("skip\n^TestExample\\.py$\n")
            self.assertEqual(list(harness.tests(args, settings, config)), [])

    def test_android_configuration(self):
        for api in (28, 30):
            with self.subTest(api=api), \
                 tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                # Use an independent NDK layout, not the native compiler mock.
                compiler = root / f"ndk/bin/x86_64-linux-android{api}-clang"
                args = argparse.Namespace(
                    source=self.source, tools=root, arch="x86_64",
                    triple="x86_64-unknown-linux-android28", compiler=compiler,
                    android=True, android_api=api, working_directory=None,
                    exclusions=None, platform="remote-android", trace=True)
                tools = lambda name, directory=None: name
                with patch.object(harness, "tool", side_effect=tools), \
                     patch.dict(os.environ, {"LDFLAGS": "-Wl,--build-id"}), \
                     patch.object(harness.subprocess, "check_output",
                                  return_value="LLDB fixture"):
                    _, config = harness.configuration(args, root)
                command = config.test_format.dotest_cmd
                self.assertNotIn("--arch", command)
                self.assertIn("-t", command)
                self.assertEqual(config.test_compiler, str(compiler))
                sys.path.insert(0, str(self.source / "lldb/packages/Python"))
                from lldbsuite.test.dotest_args import create_parser
                parser = create_parser()
                start = next(index for index, value in enumerate(command)
                             if value.endswith("dotest.py")) + 1
                parsed = parser.parse_args(command[start:])
                self.assertEqual(parsed.triple, f"x86_64-linux-android{api}")
                self.assertEqual(parsed.channels,
                                 ["gdb-remote packets", "lldb dyld"])
                self.assertIn(f"API_LEVEL={api}",
                              config.environment["MAKEFLAGS"])
                self.assertIn("ARCH_DIR=x86_64-linux-android",
                              config.environment["MAKEFLAGS"])
                self.assertEqual(config.environment["LDFLAGS"],
                                 "-Wl,--build-id")
                self.assertEqual(config.environment["LLDB_ANDROID_RUNTIME"],
                                 harness.kAndroidRuntime)
                headers = root / "ndk/sysroot/usr/include/x86_64-linux-android"
                self.assertIn(
                    [f'target.clang-module-search-paths="{headers}"'],
                    parsed.settings)

    @unittest.skipIf(sys.platform == "win32", "Android fixtures use GNU make")
    def test_android_recursive_linkage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(
                source=self.source, tools=root, arch="x86_64",
                triple="x86_64-unknown-linux-android30",
                compiler=root / "ndk/bin/x86_64-linux-android30-clang",
                android=True, android_api=30, working_directory=None,
                exclusions=None, platform="remote-android", trace=False)
            environment = dict(os.environ)
            environment.pop("LDFLAGS", None)
            tools = lambda name, directory=None: name
            with patch.dict(os.environ, environment, clear=True), \
                 patch.object(harness, "tool", side_effect=tools), \
                 patch.object(harness.subprocess, "check_output",
                              return_value="LLDB fixture"):
                _, config = harness.configuration(args, root)
            self.assertNotIn("LDFLAGS", config.environment)
            rules = self.source / "lldb/packages/Python/lldbsuite/test/make"
            include = f"include {rules}/Android.rules\n"
            (root / "Makefile").write_text(
                include + "LDFLAGS += -L. -lparent\n"
                "all:\n\t@$(MAKE) --no-print-directory -f child.mk\n")
            (root / "child.mk").write_text(
                include + "all:\n\t@echo $(LDFLAGS)\n")
            result = subprocess.run(
                [config.make, "--no-print-directory",
                 f"TOOLCHAIN_SYSROOT={root}"], cwd=root,
                env=config.environment, capture_output=True, text=True,
                timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(),
                             "-Wl,-rpath," + harness.kAndroidRuntime)
