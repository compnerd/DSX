# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

"""Warm command-line simulator launch before the timed simulator test module."""

import argparse
import json
import os
import pathlib
import re
import subprocess
import tempfile
import uuid


def prepare(tools, source):
    environment = os.environ | {
        "TOOLCHAINS": "com.apple.dt.toolchain.XcodeDefault",
    }
    lldb = str((tools / "lldb").resolve())
    packages = str((source / "lldb/packages/Python").resolve())
    # Use the fixture's selector for its simctl spawn, not a second copy of it.
    query = (f"script import sys; sys.path.insert(0, {packages!r}); "
             "from lldbsuite.test import lldbutil; import json; "
             "print('SIMULATORS=' + json.dumps({p: "
             "lldbutil.get_latest_apple_simulator(p) "
             "for p in ('ios', 'tvos')}))")
    result = subprocess.run([lldb, "--no-lldbinit", "--batch", "-o", query],
                            env=environment, capture_output=True, text=True,
                            timeout=60)
    print(result.stdout + result.stderr, flush=True)
    result.check_returncode()
    match = re.search(r"^SIMULATORS=(.+)$", result.stdout, re.MULTILINE)
    if match is None:
        # LLDB's `script` command can print a Python exception and exit zero.
        raise RuntimeError("LLDB did not report simulator availability")
    devices = json.loads(match[1])
    for platform, sdk in (("ios", "iphonesimulator"),
                          ("tvos", "appletvsimulator")):
        device = devices[platform]
        if device is None:
            print(f"{platform}: no available runtime (tests retain their skip)",
                  flush=True)
            continue
        device = str(uuid.UUID(device))
        query = ["xcrun", "--sdk", sdk]
        root = subprocess.run(query + ["--show-sdk-path"], env=environment,
                              capture_output=True, text=True, timeout=60)
        if root.returncode:
            print(f"{platform}: SDK unavailable: {root.stderr}", flush=True)
            continue
        version = subprocess.check_output(query + ["--show-sdk-version"],
                                          env=environment, text=True,
                                          timeout=60).strip()
        with tempfile.TemporaryDirectory(prefix="dsx-simulator-") as directory:
            executable = str(pathlib.Path(directory) / "ready")
            triple = f"arm64-apple-{platform}{version}-simulator"
            subprocess.run(query + ["clang", "-target", triple,
                                    "-isysroot", root.stdout.strip(), "-x", "c",
                                    "-", "-o", executable],
                           input="int main(void) { return 0; }\n", text=True,
                           env=environment, check=True, timeout=60)
            # Let LLDB choose its own launch device. It need not be the device
            # selected by lldbutil for the fixture's separate simctl spawn.
            command = [lldb, "--no-lldbinit", "--batch", "-o",
                       f"target create {json.dumps(executable)}", "-o",
                       "platform process launch", "-o", "platform status"]
            result = subprocess.run(command, env=environment,
                                    capture_output=True, text=True, timeout=300)
            print(result.stdout + result.stderr, flush=True)
            result.check_returncode()
            match = re.search(r"^Current device: ([0-9A-Fa-f-]+):",
                              result.stdout, re.MULTILINE)
            if match is None or "exited with status = 0 " not in result.stdout:
                raise RuntimeError(f"{platform}: simulator launch not ready")
            selected = str(uuid.UUID(match[1]))
            # The iOS fixture also uses simctl spawn. Exercise that exact path
            # if it selects another device. Neither path needs SpringBoard or
            # the tvOS system app, so do not wait for UI boot completion.
            if platform == "ios" and selected != device:
                command = ["xcrun", "simctl", "list", "devices", "booted",
                           "--json"]
                result = subprocess.check_output(command, env=environment,
                                                 text=True, timeout=60)
                booted = json.loads(result)["devices"]
                if not any(item["udid"].lower() == device
                           for items in booted.values() for item in items):
                    subprocess.run(["xcrun", "simctl", "boot", device],
                                   env=environment, check=True, timeout=60)
                subprocess.run(["xcrun", "simctl", "spawn", device, executable],
                               env=environment, check=True, timeout=300)
        print(f"{platform}: command-line launch ready", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    arguments = parser.parse_args()
    prepare(arguments.tools, arguments.source)
