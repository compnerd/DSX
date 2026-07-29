# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import importlib.util
import io
import json
import os
import pathlib
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


class Harness(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "win32", "Windows DLL bootstrap")
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

    def exercise(self, root, results, *, owned=True, fail_fast=False,
                 recovery=None, dead=False):
        args = argparse.Namespace(
            compiler=root / "clang", source=root, tools=root,
            platform="remote-linux", working_directory=None,
            triple="aarch64-unknown-linux-gnu", arch="aarch64",
            exclusions=None, timeout=1, label="fixture", fail_fast=fail_fast)
        config = Mock(lldb_executable="lldb", test_compiler=str(root / "clang"),
                      environment=os.environ.copy(),
                      python_executable=sys.executable)
        config.test_format.dotest_cmd = ["dotest.py"]
        server = Mock(owned=owned, adb=None, url="connect://127.0.0.1:1234",
                      log=root / "server.log")
        server.process = Mock(returncode=1) if dead else None
        if dead:
            server.process.poll.return_value = 1

        def recover(_):
            if recovery:
                raise RuntimeError(recovery)
            server.url = "connect://127.0.0.1:5678"
            server.log = root / "server-001.log"
            server.process = None

        server.recover.side_effect = recover
        pending = iter(results)

        def execute(command, environment, path, timeout, server=None):
            text, status, timedout = next(pending)
            path.write_text(text)
            return status, timedout

        selected = [Mock(config=config) for _ in results]
        for index, test in enumerate(selected):
            test.getSourcePath.return_value = str(root / f"Test{index}.py")
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
            self.assertEqual(calls.call_count, 2)

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
            with patch.object(harness, "available_port", return_value=1234), \
                 patch.object(harness.subprocess, "run") as run, \
                 patch.object(harness.subprocess, "Popen"):
                _, url, _ = harness.android_server(
                    "adb", args, root, {}, root / "server-001.log", deploy=False)
            self.assertEqual(url, "connect://localhost:1234")
            run.assert_not_called()

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

            with patch.object(harness.subprocess, "run",
                              side_effect=run) as call:
                server.diagnose(path)
                self.assertEqual(call.call_count, 3)
                self.assertEqual(call.call_args_list[0].args[0][1:4],
                                 ["logcat", "-b", "crash"])
            text = path.with_suffix(".android.log").read_text()
            self.assertEqual(text.count("device diagnostic"), 3)

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

    def test_sampling_authorization(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}), \
             patch.object(harness.subprocess, "run") as run:
            run.return_value.stdout = "10 1 S 01:00 client"
            path = pathlib.Path(directory) / "test.log"
            harness.diagnose(Mock(pid=10), path)
            command = run.call_args_list[-1].args[0]
            self.assertEqual(command[:4], ["sudo", "-n", "sample", "10"])

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
                     "deadline=time.monotonic()+15\n"
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
                      f"os.environ.copy(),pathlib.Path({str(root / 'log')!r}),1);"
                      "assert r==(0,False),r")
            try:
                subprocess.run([sys.executable, "-c", driver], check=True,
                               capture_output=True, text=True, timeout=5)
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
            with patch.object(harness, "available_port", return_value=1234), \
                 patch.object(harness, "android_runtime", return_value=root), \
                 patch.object(harness.subprocess, "run") as run, \
                 patch.object(harness.subprocess, "Popen"):
                _, url, working = harness.android_server(
                    "adb", args, root, {}, root / "server.log")
            self.assertEqual(url, "connect://localhost:1234")
            self.assertEqual(working, args.working_directory)
            self.assertFalse(any("forward" in call.args[0]
                                 for call in run.call_args_list))


class Upstream(unittest.TestCase):
    def setUp(self):
        self.source = pathlib.Path(os.environ.get("LLVM_SOURCE", "llvm-project"))
        if not (self.source / "lldb/test/API/lit.cfg.py").is_file():
            self.skipTest("set LLVM_SOURCE to validate LLDB's lit integration")

    def test_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = argparse.Namespace(
                source=self.source, tools=root, arch="arm64",
                triple="aarch64-unknown-linux-gnu", compiler=root / "clang",
                android=False, working_directory=None, exclusions=None,
                platform="remote-linux", tests=".")
            args.compiler = Mock(spec=pathlib.Path)
            args.compiler.absolute.return_value = root / "clang"
            with patch.object(harness, "tool", side_effect=lambda name: name), \
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
            if sys.platform == "win32":
                self.assertIn("LLDB_LAUNCH_FLAG_USE_PIPES=1", command)

            if sys.platform == "darwin":
                args.compiler = None
                apple = root / "Xcode" / "clang"
                with patch.object(harness, "tool",
                                  side_effect=lambda name: name), \
                     patch.object(harness.subprocess, "check_output",
                                  return_value=str(apple) + "\n") as output:
                    _, darwin = harness.configuration(args, root)
                output.assert_any_call(["xcrun", "--find", "clang"], text=True,
                                       env=darwin.environment)
                self.assertEqual(darwin.test_compiler, str(apple))
                self.assertEqual(darwin.environment["TOOLCHAINS"],
                                 "com.apple.dt.toolchain.XcodeDefault")
                args.compiler = root / "clang"

            args.android = True
            args.android_api = 28
            args.platform = "remote-android"
            args.triple = "x86_64-unknown-linux-android28"
            args.arch = "x86_64"
            with patch.object(harness, "tool", side_effect=lambda name: name), \
                 patch.object(harness.subprocess, "check_output",
                              return_value="LLDB fixture"):
                _, android = harness.configuration(args, root)
            command = android.test_format.dotest_cmd
            self.assertNotIn("--arch", command)
            sys.path.insert(0, str(self.source / "lldb/packages/Python"))
            from lldbsuite.test.dotest_args import create_parser
            parser = create_parser()
            start = next(index for index, value in enumerate(command)
                         if value.endswith("dotest.py")) + 1
            parsed = parser.parse_args(command[start:])
            self.assertEqual(parsed.triple, "x86_64-linux-android28")
            self.assertIn("API_LEVEL=28", android.environment["MAKEFLAGS"])
            self.assertIn("ARCH_DIR=x86_64-linux-android",
                          android.environment["MAKEFLAGS"])

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
