# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import collections
import json
import os
import pathlib
import subprocess
import tempfile
import urllib.parse

import lldb_results


def api(repository, endpoint):
    result = subprocess.run(["gh", "api", "--paginate", "--slurp",
                             f"repos/{repository}/{endpoint}"],
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def previous(repository, run):
    query = urllib.parse.urlencode({"branch": run["head_branch"],
                                    "event": run["event"],
                                    "status": "completed", "per_page": 100})
    endpoint = f"actions/workflows/{run['workflow_id']}/runs?{query}"
    runs = [item for page in api(repository, endpoint)
            for item in page["workflow_runs"]
            if item["run_number"] < run["run_number"]]
    if not runs:
        return None, "No earlier completed run on this branch."
    # Compare the immediately preceding run, including failures. Searching
    # backwards for green results or matching counts hides intervening losses.
    baseline = max(runs, key=lambda item: item["run_number"])
    endpoint = f"actions/runs/{baseline['id']}/artifacts?per_page=100"
    artifacts = [item for page in api(repository, endpoint)
                 for item in page["artifacts"]
                 if item["name"] == "lldb-run-summary" and not item["expired"]]
    if len(artifacts) != 1:
        return None, (f"Previous run #{baseline['run_number']} has no retained "
                      "run report (this run establishes a comparison point).")
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(["gh", "run", "download", str(baseline["id"]),
                        "--repo", repository, "--name", "lldb-run-summary",
                        "--dir", directory], check=True, capture_output=True)
        path = pathlib.Path(directory) / "run.json"
        data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != 1 or data["run"]["id"] != baseline["id"]:
        raise ValueError("Previous run report has an incompatible identity")
    note = (f"Compared with [run #{baseline['run_number']}]"
            f"({baseline['html_url']}).")
    return data, note


def collect(paths):
    summaries, problems = [], []
    for path in sorted(paths):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            # Reject malformed numbers rather than turning absent data into 0.
            fields = ("total", "reported", "selected", "attempted", "finished")
            values = [data[key] for key in fields]
            values.extend(data["counts"][key] for key in
                          (*lldb_results.OUTCOMES, "INVALID", "TIMEOUT"))
            if any(type(value) is not int or value < 0 for value in values):
                raise ValueError("invalid count")
            if (data["reported"] > data["total"] or
                sum(data["counts"][key] for key in lldb_results.OUTCOMES)
                    != data["reported"]):
                raise ValueError("inconsistent reported outcomes")
            if not isinstance(data["label"], str):
                raise ValueError("invalid label")
            lldb_results.render(data)
            lldb_results.complete(data)
            summaries.append(data)
        except (OSError, ValueError, KeyError, TypeError) as error:
            problems.append(f"{path.name}: {error}")
    return summaries, problems


def target(report, name, build):
    expected = {f"{name}/{shard['name']}/{build}" for shard in
                report["scope"]["shards"]}
    entries = collections.defaultdict(list)
    for data in report["summaries"]:
        if data["label"] in expected:
            entries[data["label"]].append(data)
    summaries = [values[0] for values in entries.values() if len(values) == 1]
    counts = collections.Counter()
    for data in summaries:
        counts.update(data["counts"])
    passed = sum(lldb_results.complete(data) and
                 data["counts"]["FAIL"] + data["counts"]["ERROR"] == 0
                 for data in summaries)
    failed = sum(lldb_results.complete(data) and
                 data["counts"]["FAIL"] + data["counts"]["ERROR"] > 0
                 for data in summaries)
    return {"counts": counts, "passed": passed, "failed": failed,
            "incomplete": len(expected) - passed - failed,
            "discovered": sum(data["total"] for data in summaries),
            "run": sum(data["reported"] for data in summaries)
                   - counts["UNSUPPORTED"],
            "unreported": sum(data["total"] - data["reported"]
                              for data in summaries),
            "summaries": summaries}


def comparison(current, baseline, scope, oldscope):
    if not current["summaries"] or not baseline["summaries"]:
        return "Missing coverage", "—"
    delta = (f"{current['counts']['FAIL'] - baseline['counts']['FAIL']:+d} / "
             f"{current['counts']['ERROR'] - baseline['counts']['ERROR']:+d}")
    if scope != oldscope:
        return "Scope changed", delta
    revisions = [{data.get("llvm") for data in item["summaries"]}
                 for item in (current, baseline)]
    if not all(revisions) or any(None in values for values in revisions):
        return "Revision unknown", delta
    if revisions[0] != revisions[1]:
        return "LLVM changed", delta
    if current["incomplete"] or baseline["incomplete"]:
        return "Incomplete (not comparable)", delta
    def coverage(item):
        return {(data["label"], module["module"]):
                (module["total"], module["counts"]["UNSUPPORTED"])
                for data in item["summaries"] for module in data["modules"]}
    if coverage(current) != coverage(baseline):
        return "Coverage changed", delta
    def failures(item):
        return {(data["label"], module["module"], test["test"], test["outcome"])
                for data in item["summaries"] for module in data["modules"]
                for test in module["tests"]}
    old, new = failures(baseline), failures(current)
    if new - old:
        return "Mixed" if old - new else "New failures", delta
    changes = [current["counts"][key] - baseline["counts"][key]
               for key in ("FAIL", "ERROR")]
    if any(change > 0 for change in changes):
        return "More failures/errors", delta
    if any(change < 0 for change in changes):
        return "Fewer failures/errors", delta
    return "Same FAIL/ERROR", delta


def render(report, baseline=None, note=""):
    run = report["run"]
    lines = ["## DSX run results", "",
             f"[Run #{run['run_number']}]({run['html_url']}) · "
             f"DSX `{run['head_sha']}`", "", note, "",
             "Shard results enforce pass/fail; this report is informational.",
             "Counts exclude missing summaries (never interpreted as zero).",
             "", "| Platform / Swift | State | Discovered | Run | "
             "FAIL / ERROR | "
             "UXPASS / XFAIL | Shards P / F / incomplete | Unreported | "
             "Invalid / timeout | Δ F / E | Δ Run | Comparison |",
             "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | "
             "---: | ---: | "
             "---: | --- |"]
    totals = collections.Counter()
    for build in report["scope"]["swift"]:
        for item in report["scope"]["targets"]:
            name = item["name"]
            row = target(report, name, build["build"])
            counts = row["counts"]
            totals.update(counts)
            totals.update({key: row[key] for key in
                           ("discovered", "run", "unreported", "passed",
                            "failed", "incomplete")})
            state = ("Incomplete" if row["incomplete"] else
                     "No coverage" if row["run"] == 0 else
                     "Failing" if counts["FAIL"] + counts["ERROR"] else "Clean")
            trend, delta, executions = "No baseline", "—", "—"
            if baseline:
                old = target(baseline, name, build["build"])
                scope = (item, build, report["scope"]["shards"],
                         report["scope"]["timeout"])
                candidates = baseline["scope"]["targets"]
                oldtarget = next((value for value in candidates
                                  if value["id"] == item["id"]), None)
                oldbuild = next((value for value in baseline["scope"]["swift"]
                                 if value == build), None)
                oldscope = (oldtarget, oldbuild, baseline["scope"]["shards"],
                            baseline["scope"]["timeout"])
                trend, delta = comparison(row, old, scope, oldscope)
                if row["summaries"] and old["summaries"]:
                    executions = f"{row['run'] - old['run']:+d}"
            values = [str(row["discovered"]), str(row["run"]),
                      f"{counts['FAIL']} / {counts['ERROR']}",
                      f"{counts['UXPASS']} / {counts['XFAIL']}"]
            if not row["summaries"]:
                values = ["—"] * len(values)
            line = (f"| {name} / {build['build']} | {state} | "
                + " | ".join(values) + " | " +
                f"{row['passed']} / {row['failed']} / {row['incomplete']} | "
                f"{row['unreported']} | "
                f"{counts['INVALID']} / {counts['TIMEOUT']} | "
                f"{delta} | {executions} | {trend} |")
            lines.append(line)
    line = (f"| Total | — | {totals['discovered']} | {totals['run']} | "
        f"{totals['FAIL']} / {totals['ERROR']} | "
        f"{totals['UXPASS']} / {totals['XFAIL']} | "
        f"{totals['passed']} / {totals['failed']} / {totals['incomplete']} | "
        f"{totals['unreported']} | {totals['INVALID']} / {totals['TIMEOUT']} | "
        "— | — | — |")
    lines.append(line)
    lines.extend(("", f"PASS: **{totals['PASS']}**. "
                  f"Unsupported/skipped: **{totals['UNSUPPORTED']}**."))
    if not report["scope"]["targets"] or not report["scope"]["shards"]:
        lines.extend(("", "**No test scope available (check matrix setup).**"))
    lines.extend(("", "Incomplete rows are lower bounds, not clean 0/0. "
                  "Coverage checks include per-module discovery and skips. "
                  "UXPASS is desirable and does not fail the run.", "",
                  "### Build and job failures", ""))
    builds = [job for job in report["jobs"] if
              job["name"].startswith(("DSX ·", "LLDB ·", "Compact SwiftPM"))]
    for prefix in ("DSX ·", "LLDB ·", "Compact SwiftPM"):
        jobs = [job for job in builds if job["name"].startswith(prefix)]
        counts = collections.Counter(job["conclusion"] or job["status"]
                                     for job in jobs)
        lines.append(f"- {prefix.rstrip(' ·')}: " +
                     (", ".join(f"{value} {key}" for key, value in
                                sorted(counts.items())) or "No jobs reported"))
    for job in report["jobs"]:
        if job["conclusion"] in (None, "success", "skipped", "neutral"):
            continue
        lines.append(f"- [{job['name']}]({job['html_url']}): "
                     f"{job['conclusion'] or job['status']}")
        for annotation in job.get("annotations", []):
            message = annotation["message"].replace("\n", "\n  > ")
            lines.extend(("", f"  > {message}", ""))
    if report["problems"]:
        lines.extend(("", "### Reporting problems", "", *report["problems"]))
    lines.extend(("", "<details><summary>Shard counts and failure identities"
                  "</summary>", ""))
    for data in sorted(report["summaries"], key=lambda data: data["label"]):
        lines.extend((f"#### {data['label']}", "",
                      f"LLDB: `{data.get('llvm', 'unknown')}`", "",
                      "```text", lldb_results.render(data).rstrip(), "```", ""))
    lines.append("</details>")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    repository = os.environ["GITHUB_REPOSITORY"]
    run = api(repository, f"actions/runs/{os.environ['GITHUB_RUN_ID']}")[0]
    jobs = [job for page in api(repository,
            f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")
            for job in page["jobs"]]
    summaries, problems = collect(args.directory.rglob("summary.json"))
    for job in jobs:
        if job["conclusion"] in (None, "success", "skipped", "neutral"):
            continue
        try:
            endpoint = f"check-runs/{job['id']}/annotations?per_page=100"
            job["annotations"] = [item for page in api(repository, endpoint)
                                  for item in page]
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            problems.append(f"Job annotations unavailable: {job['name']} "
                            f"({error})")
    scope = {key: json.loads(os.environ[key.upper()]) for key in
             ("targets", "swift", "shards")}
    scope["timeout"] = os.environ["TIMEOUT"]
    expected = {f"{item['name']}/{shard['name']}/{build['build']}"
                for item in scope["targets"] for build in scope["swift"]
                for shard in scope["shards"]}
    for data in summaries:
        if data["label"] not in expected:
            problems.append(f"Unexpected shard summary: {data['label']}")
    report = {"schema": 1, "run": run, "jobs": jobs, "scope": scope,
              "summaries": summaries, "problems": problems}
    try:
        baseline, note = previous(repository, run)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        baseline, note = None, f"Baseline unavailable: {error}"
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "run.json").write_text(json.dumps(report) + "\n",
                                         encoding="utf-8")
    text = render(report, baseline, note)
    (args.output / "summary.md").write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
