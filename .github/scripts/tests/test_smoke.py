# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import importlib.util
import pathlib
import unittest
from unittest.mock import MagicMock, mock_open, patch

path = pathlib.Path(__file__).resolve().parents[1] / "smoke-dsx.py"
spec = importlib.util.spec_from_file_location("smoke", path)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class Smoke(unittest.TestCase):
    def setUp(self):
        self.server = MagicMock()
        self.server.__enter__.return_value = self.server
        self.server.poll.return_value = None
        self.client = MagicMock()
        self.client.__enter__.return_value = self.client

    def launch(self, command, stdout, stderr):
        self.assertEqual(command[-1], "127.0.0.1:0")
        self.assertIs(stdout, stderr)
        stderr.write(b"Listening on port 1234\n")
        stderr.flush()
        return self.server

    def runcheck(self):
        with patch.object(smoke.subprocess, "Popen", self.launch), \
                patch.object(smoke.socket, "create_connection",
                             return_value=self.client), \
                patch("builtins.open", mock_open(read_data=b"MZ")):
            smoke.check(["dsx"])

    def test_exchange(self):
        bodies = (b"triple:693338362d77696e646f7773;ptrsize:4;endian:little;",
                  b"file_size:200;file_path:647378;", b"F1", b"F2;MZ", b"F0",
                  b"F0")
        packet = b"".join(b"+$" + body + b"#%02x" % (sum(body) & 0xff)
                          for body in bodies)
        self.client.recv.side_effect = [bytes([byte]) for byte in packet]
        self.runcheck()
        self.client.sendall.assert_any_call(b"+$qHostInfo#9b")
        self.client.sendall.assert_any_call(b"+")
        self.server.terminate.assert_called_once()
        self.server.wait.assert_called_once()

    def test_module_crash(self):
        body = b"triple:693338362d77696e646f7773;ptrsize:4;endian:little;"
        packet = b"+$" + body + b"#%02x" % (sum(body) & 0xff)
        self.client.recv.side_effect = [packet, b""]
        with self.assertRaisesRegex(RuntimeError, "closed before its reply"):
            self.runcheck()
        self.server.terminate.assert_called_once()

    def test_permissions_crash(self):
        bodies = (b"triple:693338362d77696e646f7773;ptrsize:4;endian:little;",
                  b"file_size:200;file_path:647378;", b"F1", b"F2;MZ", b"F0")
        self.client.recv.side_effect = [
            b"+$" + body + b"#%02x" % (sum(body) & 0xff) for body in bodies
        ] + [b""]
        with self.assertRaisesRegex(RuntimeError, "closed before its reply"):
            self.runcheck()
        self.server.terminate.assert_called_once()

    def test_read_failure(self):
        bodies = (b"triple:693338362d77696e646f7773;ptrsize:4;endian:little;",
                  b"file_size:200;file_path:647378;", b"F1", b"F-1,5")
        self.client.recv.side_effect = [
            b"+$" + body + b"#%02x" % (sum(body) & 0xff) for body in bodies
        ]
        with self.assertRaisesRegex(RuntimeError, "Invalid file prefix"):
            self.runcheck()

    def test_invalid(self):
        for reply in (b"", b"+$OK#9a", b"+$ptrsize:4;endian:little;#00"):
            with self.subTest(reply=reply):
                self.client.recv.return_value = reply
                with self.assertRaises(RuntimeError):
                    self.runcheck()
                self.assertTrue(self.server.terminate.called)

    def test_crash(self):
        self.server.poll.return_value = 3221225477
        with self.assertRaisesRegex(RuntimeError, "3221225477"):
            self.runcheck()
        self.client.sendall.assert_not_called()
        self.server.terminate.assert_not_called()

    def test_timeout(self):
        with patch.object(smoke.subprocess, "Popen", return_value=self.server):
            with self.assertRaisesRegex(RuntimeError, "startup timed out"):
                smoke.check(["dsx"], timeout=0)
        self.server.terminate.assert_called_once()
