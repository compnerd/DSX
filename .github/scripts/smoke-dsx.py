# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import pathlib
import re
import socket
import subprocess
import tempfile
import time


def exchange(client: socket.socket, payload: bytes, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    client.sendall(b"+$" + payload + b"#%02x" % (sum(payload) & 0xff))
    reply = bytearray()
    while b"#" not in reply or len(reply.split(b"#", 1)[1]) < 2:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("DSX reply timed out")
        client.settimeout(remaining)
        part = client.recv(4096)
        if not part:
            raise RuntimeError("DSX closed before its reply")
        reply.extend(part)
        if len(reply) > 65536:
            raise RuntimeError("DSX sent an unbounded reply")
    start = reply.index(b"$") + 1
    body, checksum = reply[start:].split(b"#", 1)
    if sum(body) & 0xff != int(checksum[:2], 16):
        raise RuntimeError("DSX sent an invalid checksum")
    client.sendall(b"+")
    return bytes(body)


def check(command: list[str], timeout: float = 15) -> None:
    with tempfile.TemporaryDirectory() as directory, \
            tempfile.TemporaryFile() as log:
        with subprocess.Popen(command + ["platform", "--server", "--listen",
                                         "127.0.0.1:0"], stdout=log,
                              stderr=log) as server:
            try:
                deadline = time.monotonic() + timeout
                while True:
                    log.seek(0)
                    output = log.read().decode("utf-8", errors="replace")
                    status = server.poll()
                    if status is not None:
                        raise RuntimeError(f"DSX exited ({status}): {output}")
                    port = re.search(r"Listening on port (\d+)", output)
                    if port:
                        break
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"DSX startup timed out: {output}")
                    time.sleep(0.05)
                with socket.create_connection(("127.0.0.1", int(port[1])),
                                              timeout=timeout) as client:
                    body = exchange(client, b"qHostInfo", timeout)
                    if b"ptrsize:" not in body or b"endian:" not in body:
                        raise RuntimeError(f"Invalid qHostInfo reply: {body!r}")
                    fields = dict(field.split(b":", 1)
                                  for field in body.split(b";")
                                  if b":" in field)
                    triple = fields[b"triple"]
                    path = str(pathlib.Path(command[0]).resolve()).encode()
                    path = path.hex().encode()
                    body = exchange(client, b"qModuleInfo:" + path + b";" +
                                    triple, timeout)
                    if b"file_size:" not in body or b"file_path:" not in body:
                        raise RuntimeError(f"Invalid qModuleInfo: {body!r}")
                    body = exchange(client, b"vFile:open:" + path + b",0,0",
                                    timeout)
                    if not re.fullmatch(rb"F[0-9a-fA-F]+", body):
                        raise RuntimeError(f"Invalid vFile:open: {body!r}")
                    descriptor = body[1:]
                    body = exchange(client, b"vFile:pread:" + descriptor +
                                    b",2,0", timeout)
                    with open(command[0], "rb") as executable:
                        expected = b"F2;" + executable.read(2)
                    if body != expected:
                        raise RuntimeError(f"Invalid file prefix: {body!r}")
                    body = exchange(client, b"vFile:close:" + descriptor,
                                    timeout)
                    if body != b"F0":
                        raise RuntimeError(f"Invalid vFile:close: {body!r}")
                    fixture = pathlib.Path(directory) / "permissions"
                    fixture.touch()
                    path = str(fixture).encode().hex().encode()
                    body = exchange(client, b"qPlatform_chmod:1c0," + path,
                                    timeout)
                    if body != b"F0":
                        raise RuntimeError(f"Invalid qPlatform_chmod: {body!r}")
            finally:
                if server.poll() is None:
                    server.terminate()
                try:
                    server.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=pathlib.Path)
    args = parser.parse_args()
    check([str(args.executable.resolve())])
    print("DSX startup, module query, executable read and permissions passed")
