# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import unittest
from unittest.mock import patch

script = pathlib.Path(__file__).resolve().parents[1] / "prepare-simulators.py"
spec = importlib.util.spec_from_file_location("simulators", script)
simulators = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulators)


class Simulators(unittest.TestCase):
    selected = "11111111-1111-1111-1111-111111111111"
    fixture = "22222222-2222-2222-2222-222222222222"

    def setUp(self):
        self.devices = {"ios": self.fixture, "tvos": None}
        self.launch = ("Process 123 exited with status = 0 (0x00000000)\n"
                       f"Current device: {self.selected}: iPhone\n")
        self.sdk = True
        self.failure = False
        self.booted = []
        self.calls = []

    def run_command(self, command, **options):
        self.calls.append(command)
        self.assertEqual(options["env"]["TOOLCHAINS"],
                         "com.apple.dt.toolchain.XcodeDefault")
        self.assertGreater(options["timeout"], 0)
        if command[-1].startswith("script "):
            output = "SIMULATORS=" + json.dumps(self.devices) + "\n"
        elif "--show-sdk-path" in command:
            if not self.sdk:
                return subprocess.CompletedProcess(command, 1, "", "no SDK")
            output = "/Xcode/SDK\n"
        elif "platform process launch" in command:
            output = self.launch
        elif "spawn" in command and self.failure:
            raise subprocess.CalledProcessError(1, command)
        else:
            output = ""
        return subprocess.CompletedProcess(command, 0, output, "")

    def output(self, command, **options):
        self.calls.append(command)
        if "booted" in command:
            return json.dumps({"devices": {"ios": self.booted}})
        return "26.5\n"

    def prepare(self):
        with patch.object(simulators.subprocess, "run",
                          side_effect=self.run_command), \
             patch.object(simulators.subprocess, "check_output",
                          side_effect=self.output), \
             contextlib.redirect_stdout(io.StringIO()):
            simulators.prepare(pathlib.Path("tools"), pathlib.Path("llvm"))

    def spawns(self):
        self.assertFalse(any("bootstatus" in c for c in self.calls))
        return [c[3] for c in self.calls if "spawn" in c]

    def test_distinct_devices(self):
        self.prepare()
        self.assertEqual(self.spawns(), [self.fixture])
        self.assertEqual([c[3] for c in self.calls if "boot" in c],
                         [self.fixture])
        compiler = next(c for c in self.calls if "clang" in c)
        self.assertIn("arm64-apple-ios26.5-simulator", compiler)
        self.assertIn("get_latest_apple_simulator", self.calls[0][-1])

    def test_booted_device(self):
        self.booted = [{"udid": self.fixture}]
        self.prepare()
        self.assertEqual(self.spawns(), [self.fixture])
        self.assertFalse(any("boot" in c for c in self.calls))

    def test_same_device(self):
        self.devices["ios"] = self.selected
        self.prepare()
        self.assertEqual(self.spawns(), [])

    def test_missing_runtime(self):
        self.devices["ios"] = None
        self.prepare()
        self.assertEqual(len(self.calls), 1)

    def test_missing_sdk(self):
        self.sdk = False
        self.prepare()
        self.assertEqual(self.spawns(), [])
        self.assertEqual(len(self.calls), 2)

    def test_tvos(self):
        self.devices = {"ios": None, "tvos": self.fixture}
        self.prepare()
        compiler = next(c for c in self.calls if "clang" in c)
        self.assertIn("appletvsimulator", compiler)
        self.assertIn("arm64-apple-tvos26.5-simulator", compiler)
        self.assertEqual(self.spawns(), [])

    def test_readiness_failure(self):
        self.failure = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare()
        self.assertEqual(self.spawns(), [self.fixture])

    def test_launch_failure(self):
        for output in ("Traceback: launch failed\n",
                       f"Current device: {self.selected}: iPhone\n",
                       "Process 123 exited with status = 0 (0x00000000)\n"):
            with self.subTest(output=output):
                self.launch = output
                with self.assertRaisesRegex(RuntimeError, "not ready"):
                    self.prepare()
        self.assertEqual(self.spawns(), [])

    def test_python_failure(self):
        result = subprocess.CompletedProcess([], 0, "", "Traceback: failed")
        with patch.object(simulators.subprocess, "run", return_value=result), \
             contextlib.redirect_stdout(io.StringIO()), \
             self.assertRaisesRegex(RuntimeError, "availability"):
            simulators.prepare(pathlib.Path("tools"), pathlib.Path("llvm"))

    def test_command_failure(self):
        for error in (subprocess.CalledProcessError(1, ["lldb"]),
                      subprocess.TimeoutExpired(["lldb"], 60)):
            with self.subTest(error=error), \
                 patch.object(simulators.subprocess, "run",
                              side_effect=error), \
                 self.assertRaises(type(error)):
                simulators.prepare(pathlib.Path("tools"), pathlib.Path("llvm"))


if __name__ == "__main__":
    unittest.main()
