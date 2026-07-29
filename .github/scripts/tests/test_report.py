# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import copy
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import lldb_report
import lldb_results


class Report(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.scope = {"targets": [{"name": "Windows ARM64", "id": "windows"}],
                      "swift": [{"build": "release"}],
                      "shards": [{"name": "python", "tests": "python_api"}],
                      "timeout": "600"}
        self.report = {"run": {"id": 2, "run_number": 2, "head_sha": "commit",
                               "html_url": "https://example.test/2"},
                       "scope": self.scope, "summaries": [], "jobs": [],
                       "problems": []}

    def summary(self, output="Ran 2 tests in 0s\nOK\n", status=0):
        module = lldb_results.outcome(output, status)
        module["module"] = "TestExample.py"
        data = lldb_results.save(self.root, [module], 1,
                                 "Windows ARM64/python/release", completed=True)
        data["llvm"] = "revision"
        return data

    def compare(self, old, new):
        baseline = copy.deepcopy(self.report)
        baseline["summaries"] = [old]
        self.report["summaries"] = [new]
        before = lldb_report.target(baseline, "Windows ARM64", "release")
        after = lldb_report.target(self.report, "Windows ARM64", "release")
        return lldb_report.comparison(after, before, self.scope, self.scope)

    def test_recovery(self):
        old = self.summary("Ran 2 tests in 0s\nFAILED (errors=1)\n", 1)
        self.assertEqual(self.compare(old, self.summary()),
                         ("Fewer failures/errors", "+0 / -1"))

    def test_missing(self):
        row = lldb_report.target(self.report, "Windows ARM64", "release")
        self.assertEqual(row["incomplete"], 1)
        self.assertEqual(row["passed"], 0)
        self.assertIn("Incomplete", lldb_report.render(self.report))

    def test_duplicate(self):
        self.report["summaries"] = [self.summary()] * 2
        row = lldb_report.target(self.report, "Windows ARM64", "release")
        self.assertEqual(row["incomplete"], 1)
        self.assertEqual(row["run"], 0)

    def test_interrupted(self):
        old = self.summary("Ran 2 tests in 0s\nFAILED (errors=1)\n", 1)
        new = self.summary("Collected 2 tests\n", -9)
        self.assertEqual(self.compare(old, new)[0],
                         "Incomplete (not comparable)")

    def test_discovery(self):
        old = self.summary("Ran 2 tests in 0s\nFAILED (errors=1)\n", 1)
        new = self.summary("Ran 1 test in 0s\nOK\n")
        self.assertEqual(self.compare(old, new)[0], "Coverage changed")

    def test_skips(self):
        old = self.summary("Ran 2 tests in 0s\nFAILED (errors=1)\n", 1)
        new = self.summary("Ran 2 tests in 0s\nOK (skipped=1)\n")
        self.assertEqual(self.compare(old, new)[0], "Coverage changed")

    def test_module_swap(self):
        old, new = self.summary(), self.summary()
        new["modules"][0]["module"] = "TestDifferent.py"
        self.assertEqual(self.compare(old, new)[0], "Coverage changed")

    def test_revision(self):
        old, new = self.summary(), self.summary()
        new["llvm"] = "different"
        self.assertEqual(self.compare(old, new)[0], "LLVM changed")
        del new["llvm"]
        self.assertEqual(self.compare(old, new)[0], "Revision unknown")

    def test_failure_swap(self):
        old = self.summary("FAIL: old\nRan 2 tests in 0s\n"
                           "FAILED (failures=1)\n", 1)
        new = self.summary("FAIL: new\nRan 2 tests in 0s\n"
                           "FAILED (failures=1)\n", 1)
        self.assertEqual(self.compare(old, new), ("Mixed", "+0 / +0"))

    def test_uxpass(self):
        old = self.summary()
        new = self.summary("Ran 2 tests in 0s\n"
                           "FAILED (unexpected successes=1)\n", 1)
        self.assertEqual(self.compare(old, new)[0], "Same FAIL/ERROR")
        row = lldb_report.target(self.report, "Windows ARM64", "release")
        self.assertEqual(row["passed"], 1)

    def test_no_coverage(self):
        data = self.summary("Ran 2 tests in 0s\nOK (skipped=2)\n")
        self.report["summaries"] = [data]
        self.assertIn("No coverage", lldb_report.render(self.report))

    def test_scope(self):
        self.report["summaries"] = [self.summary()]
        row = lldb_report.target(self.report, "Windows ARM64", "release")
        result = lldb_report.comparison(row, row, ["full"], ["partial"])
        self.assertEqual(result, ("Scope changed", "+0 / +0"))

    def test_table(self):
        self.report["summaries"] = [self.summary()]
        text = lldb_report.render(self.report, self.report)
        rows = [line for line in text.splitlines() if line.startswith("|")]
        self.assertEqual(len({line.count("|") for line in rows}), 1)
        self.assertIn("Same FAIL/ERROR", text)
        self.assertIn("PASS: **2**", text)

    def test_invalid(self):
        path = self.root / "summary.json"
        for value in ("{", '{"label": "broken"}'):
            path.write_text(value)
            summaries, problems = lldb_report.collect([path])
            self.assertEqual(summaries, [])
            self.assertEqual(len(problems), 1)

    def test_numbers(self):
        data = self.summary()
        for value in (-1, True, "2", 3):
            data["reported"] = value
            path = self.root / "summary.json"
            path.write_text(json.dumps(data))
            summaries, problems = lldb_report.collect([path])
            self.assertEqual(summaries, [])
            self.assertEqual(len(problems), 1)

    def test_previous_failed_run(self):
        run = {"workflow_id": 1, "head_branch": "main",
               "event": "workflow_dispatch", "run_number": 3}
        runs = [{"id": 1, "run_number": 1, "conclusion": "success"},
                {"id": 2, "run_number": 2, "conclusion": "failure"}]
        with patch.object(lldb_report, "api") as api:
            api.side_effect = [[{"workflow_runs": runs}], [{"artifacts": []}]]
            baseline, note = lldb_report.previous("owner/repo", run)
        self.assertIsNone(baseline)
        self.assertIn("Previous run #2", note)
        self.assertIn("actions/runs/2/artifacts", api.call_args.args[1])

    def test_pagination(self):
        with patch.object(lldb_report.subprocess, "run") as run:
            run.return_value.stdout = '[{"jobs": [1]}, {"jobs": [2]}]'
            pages = lldb_report.api("owner/repo", "actions/runs/1/jobs")
        jobs = [job for page in pages for job in page["jobs"]]
        self.assertEqual(jobs, [1, 2])
        self.assertEqual(run.call_args.args[0][:4],
                         ["gh", "api", "--paginate", "--slurp"])

    def test_download(self):
        run = {"workflow_id": 1, "head_branch": "main",
               "event": "workflow_dispatch", "run_number": 3}
        baseline = {"id": 2, "run_number": 2,
                    "html_url": "https://example.test/2"}
        def download(command, **kwargs):
            directory = pathlib.Path(command[-1])
            data = json.dumps({"schema": 1, "run": baseline})
            (directory / "run.json").write_text(data)
        with patch.object(lldb_report, "api") as api, \
             patch.object(lldb_report.subprocess, "run", download):
            api.side_effect = [[{"workflow_runs": [baseline]}],
                               [{"artifacts": [{"name": "lldb-run-summary",
                                                "expired": False}]}]]
            result, note = lldb_report.previous("owner/repo", run)
        self.assertEqual(result["run"]["id"], 2)
        self.assertIn("Compared with [run #2]", note)

    def test_pipeline(self):
        self.summary()
        run = self.report["run"]
        output = self.root / "report"
        environment = {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_RUN_ID": "2",
                       "TIMEOUT": "600"}
        environment.update({key.upper(): json.dumps(self.scope[key]) for key in
                            ("targets", "swift", "shards")})
        with patch.dict(os.environ, environment), \
             patch.object(sys, "argv", ["lldb_report.py", str(self.root),
                                        "--output", str(output)]), \
             patch.object(lldb_report, "api") as api, \
             patch.object(lldb_report, "previous") as previous, \
             patch.object(sys, "stdout", io.StringIO()):
            api.side_effect = [[run], [{"jobs": []}]]
            previous.return_value = None, "No retained baseline"
            lldb_report.main()
        report = json.loads((output / "run.json").read_text())
        self.assertEqual(report["summaries"][0]["counts"]["PASS"], 2)
        text = (output / "summary.md").read_text()
        self.assertIn("No retained baseline", text)

    def test_runner_loss(self):
        self.report["jobs"] = [{"name": "Darwin x64 / languages",
                                "html_url": "https://example.test/job",
                                "status": "completed", "conclusion": "failure",
                                "annotations": [{"message": "The hosted runner "
                                                 "lost communication"}]}]
        text = lldb_report.render(self.report)
        self.assertIn("lost communication", text)
        self.assertIn("Incomplete", text)

    def test_revision_recording(self):
        self.summary()
        script = pathlib.Path(lldb_results.__file__)
        result = subprocess.run([sys.executable, str(script), str(self.root),
                                 "--finalize", "Windows ARM64/python/release",
                                 "--llvm", "actual-artifact-revision"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads((self.root / "summary.json").read_text())
        self.assertEqual(data["llvm"], "actual-artifact-revision")
        self.assertEqual(data["counts"]["PASS"], 2)


if __name__ == "__main__":
    unittest.main()
