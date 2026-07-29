# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import collections
import json
import pathlib
import re
import sys


OUTCOMES = ("PASS", "FAIL", "UXPASS", "XFAIL", "ERROR", "UNSUPPORTED")


def outcome(output: str, status: int, timedout: bool = False) -> dict:
    output = re.sub(r"\x1b\[[0-9;]*m", "", output).replace("\r\n", "\n")
    runs = re.findall(r"^Ran (\d+) tests? in .+$", output, re.MULTILINE)
    collected = re.findall(r"^Collected (\d+) tests?$", output, re.MULTILINE)
    summaries = re.findall(r"^(OK|FAILED)(?: \(([^\n]*)\))?$", output,
                           re.MULTILINE)
    counts = dict.fromkeys(OUTCOMES, 0)
    tests = []
    # LLDB prints FAIL for both addFailure and addError. The unittest
    # summary, not those progress markers, distinguishes their outcomes.
    for kind, name in re.findall(r"^(FAIL|ERROR): (.+)$", output, re.MULTILINE):
        if not name.startswith("LLDB ("):
            record = {"outcome": kind, "test": name}
            if record not in tests:
                tests.append(record)
    valid = len(runs) == 1 and len(summaries) == 1 and int(runs[0]) > 0
    reported = int(runs[0]) if len(runs) == 1 else 0
    total = int(collected[0]) if len(collected) == 1 else reported
    if valid:
        fields = dict(re.findall(r"([a-z ]+)=(\d+)", summaries[0][1]))
        fields = {key.strip(): int(value) for key, value in fields.items()}
        for key, label in (("failures", "FAIL"), ("errors", "ERROR"),
                           ("unexpected successes", "UXPASS"),
                           ("expected failures", "XFAIL"),
                           ("skipped", "UNSUPPORTED")):
            counts[label] = fields.get(key, 0)
        counts["PASS"] = max(0, reported - sum(counts.values()))
        # A crash after an otherwise successful summary is still invalid.
        expected = counts["FAIL"] + counts["ERROR"] + counts["UXPASS"] > 0
        valid = status == int(expected)
        valid = valid and (summaries[0][0] == "FAILED") == expected
    disposition = ("TIMEOUT" if timedout else "INVALID" if not valid else
                   "FAIL" if counts["FAIL"] or counts["ERROR"] else "PASS")
    return {"status": disposition, "exit": status, "total": total,
            "reported": reported, "counts": counts, "tests": tests}


def totals(modules: list[dict]) -> dict:
    counts = collections.Counter(dict.fromkeys(OUTCOMES, 0))
    for module in modules:
        counts.update(module["counts"])
    counts["INVALID"] = sum(m["status"] == "INVALID" for m in modules)
    counts["TIMEOUT"] = sum(m["status"] == "TIMEOUT" for m in modules)
    return dict(counts)


def render(data: dict) -> str:
    counts = data["counts"]
    reported = data.get("reported", data["total"])
    lines = ["LLDB test summary", "", f"  Tests discovered: {data['total']}",
             f"  Tests run:        {reported - counts['UNSUPPORTED']}",
             f"  Tests unreported: {data['total'] - reported}"]
    lines.extend(f"  {key + ':':<18}{counts[key]}" for key in counts)
    lines.extend((f"  Modules finished: {data['finished']}/{data['selected']}",
                  f"  Modules attempted: {data['attempted']}",
                  f"  Modules not run:  {data['selected'] - data['attempted']}"))
    if reported == counts['UNSUPPORTED']:
        lines.extend(("", "No coverage: no reported test executions."))
    failures = [module for module in data["modules"]
                if module["status"] != "PASS"]
    if failures:
        lines.extend(("", "Unsuccessful modules:"))
        for module in failures:
            lines.append(f"  {module['status']}: {module['module']}")
            for key in ("reason", "recovery"):
                if module.get(key):
                    lines.append(f"    {key}: {module[key]}")
            lines.extend(f"    {test['outcome']}: {test['test']}"
                         for test in module["tests"])
    return "\n".join(lines) + "\n"


def save(root: pathlib.Path, modules: list[dict], selected: int,
         label: str, completed: bool = False) -> dict:
    data = {"label": label, "selected": selected, "modules": modules,
            "completed": completed,
            "attempted": sum(m.get("module") != "<harness>" for m in modules),
            "finished": sum(m["status"] in ("PASS", "FAIL") for m in modules),
            "total": sum(module["total"] for module in modules),
            "reported": sum(m.get("reported", m["total"]) for m in modules),
            "counts": totals(modules)}
    # Checkpoint after every module so cancellation retains completed results.
    temporary = root / "summary.tmp"
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    temporary.replace(root / "summary.json")
    (root / "summary.md").write_text("```text\n" + render(data) + "```\n",
                                    encoding="utf-8")
    return data


def finalize(root: pathlib.Path, label: str) -> None:
    path = root / "summary.json"
    data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if data.get("completed"):
        return
    root.mkdir(parents=True, exist_ok=True)
    module = outcome("", 1)
    module.update(module="<harness>", reason="Setup failed or run interrupted")
    modules = data.get("modules", []) + [module]
    save(root, modules, data.get("selected", 0), label, completed=True)


def complete(data: dict) -> bool:
    counts = data["counts"]
    return (data.get("completed", False) and data["selected"] > 0 and
            data["finished"] == data["selected"] == data["attempted"] and
            counts["INVALID"] == 0 and counts["TIMEOUT"] == 0 and
            data.get("reported", data["total"]) == data["total"])


def aggregate(paths: list[pathlib.Path], states: dict[str, str] = None) -> str:
    prefix = "| Shard | Status |" if states else "| Shard |"
    heading = (prefix + " Discovered | Run | PASS | FAIL | UXPASS | XFAIL | "
               "ERROR | Unsupported | Unreported | Invalid modules | "
               "Timeouts | Not run |")
    lines = ["## LLDB compatibility results", "", heading,
             ("| --- | --- |" if states else "| --- |") + " ---: |" * 12]
    combined = [0] * 12
    untested = []
    labels = set()
    for path in sorted(paths):
        data = json.loads(path.read_text(encoding="utf-8"))
        labels.add(data["label"])
        counts = data["counts"]
        reported = data.get("reported", data["total"])
        values = [data["total"], reported - counts["UNSUPPORTED"]]
        values.extend(counts[key] for key in OUTCOMES)
        values.extend((data["total"] - reported,
                       counts["INVALID"], counts["TIMEOUT"],
                       data["selected"] - data["attempted"]))
        label = data["label"].replace("|", "\\|")
        if states:
            label = label.rsplit("/", 2)[-2]
            label += f" | {states[data['label']]}"
        if values[1] == 0:
            untested.append(data["label"])
        lines.append(f"| {label} | " + " | ".join(map(str, values)) + " |")
        combined = [left + right for left, right in zip(combined, values)]
    for label, state in (states or {}).items():
        if label not in labels:
            label = label.rsplit("/", 2)[-2].replace("|", "\\|")
            lines.append(f"| {label} | {state} |" + " — |" * 12)
    if paths:
        total = "| Total | — | " if states else "| Total | "
        lines.append(total + " | ".join(map(str, combined)) + " |")
    if untested:
        lines.extend(("", "No coverage (no reported executions): " +
                      ", ".join(untested) + "."))
    lines.extend(("", "Unreported tests were collected but have no final "
                  "outcome (they may have started). Invalid/timeouts count "
                  "modules, not fabricated test failures. Missing shards "
                  "have no summary (check setup "
                  "and cancelled jobs). UXPASS does not fail the run."))
    return "\n".join(lines) + "\n"


def platform(paths: list[pathlib.Path], label: str, build: str,
             shards: list[str], result: str) -> tuple[str, bool]:
    expected = {f"{label}/{shard}/{build}": [] for shard in shards}
    problems = []
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            expected[data["label"]].append((path, data))
        except (OSError, ValueError, KeyError, TypeError) as error:
            problems.append(f"Unreadable or unexpected summary: {path} ({error})")
    states = {}
    valid = []
    failures = executions = 0
    for name, entries in expected.items():
        if len(entries) != 1:
            states[name] = "Missing" if not entries else "Duplicate"
            continue
        path, data = entries[0]
        try:
            counts = {key: data["counts"][key]
                      for key in (*OUTCOMES, "INVALID", "TIMEOUT")}
            reported = data.get("reported", data["total"])
            selected, attempted, finished = (data[key] for key in
                                             ("selected", "attempted", "finished"))
            failed = counts["FAIL"] + counts["ERROR"]
            completed = complete(data)
            executions += reported - counts["UNSUPPORTED"]
        except (KeyError, TypeError) as error:
            states[name] = "Invalid summary"
            problems.append(f"Invalid summary: {path} ({error})")
            continue
        states[name] = ("Incomplete" if not completed else
                        "Failing" if failed else "Passed")
        failures += failed
        valid.append(path)
    passed = sum(state == "Passed" for state in states.values())
    failed = sum(state == "Failing" for state in states.values())
    finished = passed + failed
    incomplete = (not shards or finished != len(shards) or bool(problems) or
                  (result != "success" and failures == 0))
    status = ("Failing (incomplete)" if failures and incomplete else
              "Failing" if failures else "Incomplete" if incomplete else
              "No coverage" if executions == 0 else "Clean")
    lines = [f"## {label}", "", f"**{status}**", "",
             f"Shards completed: **{finished}/{len(shards)}** "
             f"({passed} passed, {failed} failed, "
             f"{len(shards) - finished} incomplete).",
             f"Shard jobs: {result}. Swift: {build}.", "",
             "Selected shards: " + ", ".join(shards) + "."]
    details = aggregate(valid, states).replace("## LLDB compatibility results",
                                               "### Shards", 1)
    lines.extend(("Only the selected scope is assessed (not omitted tests).", "",
                  details))
    if problems:
        lines.extend(("", *problems))
    return "\n".join(lines) + "\n", status == "Clean"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--finalize", metavar="LABEL",
                        help="record setup failure or interruption if needed")
    parser.add_argument("--llvm", help="actual LLDB artifact revision")
    parser.add_argument("--target", help="render a target-level status")
    parser.add_argument("--build", help="Swift build identifying shard results")
    parser.add_argument("--shards", help="selected shard records (JSON)")
    parser.add_argument("--job-result", choices=("success", "failure", "cancelled",
                                                "skipped"), default="success")
    args = parser.parse_args()
    if args.finalize:
        finalize(args.directory, args.finalize)
        if args.llvm:
            path = args.directory / "summary.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            data["llvm"] = args.llvm
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    paths = list(args.directory.rglob("summary.json"))
    if args.target:
        if not args.build or not args.shards:
            parser.error("--target requires --build and --shards")
        shards = [shard["name"] for shard in json.loads(args.shards)]
        text, clean = platform(paths, args.target, args.build, shards,
                               args.job_result)
        print(text, end="")
        sys.exit(0 if clean else 1)
    print(aggregate(paths), end="")
