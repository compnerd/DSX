# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import collections
import json
import pathlib
import re


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


def aggregate(paths: list[pathlib.Path]) -> str:
    heading = ("| Shard | Discovered | Run | PASS | FAIL | UXPASS | XFAIL | "
               "ERROR | Unsupported | Unreported | Invalid modules | "
               "Timeouts | Not run |")
    lines = ["## LLDB compatibility results", "", heading,
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | "
             "---: | ---: | ---: | ---: | ---: |"]
    combined = [0] * 12
    untested = []
    for path in sorted(paths):
        data = json.loads(path.read_text(encoding="utf-8"))
        counts = data["counts"]
        reported = data.get("reported", data["total"])
        values = [data["total"], reported - counts["UNSUPPORTED"]]
        values.extend(counts[key] for key in OUTCOMES)
        values.extend((data["total"] - reported,
                       counts["INVALID"], counts["TIMEOUT"],
                       data["selected"] - data["attempted"]))
        label = data["label"].replace("|", "\\|")
        if values[1] == 0:
            untested.append(data["label"])
        lines.append(f"| {label} | " + " | ".join(map(str, values)) + " |")
        combined = [left + right for left, right in zip(combined, values)]
    if paths:
        lines.append("| Total | " + " | ".join(map(str, combined)) + " |")
    if untested:
        lines.extend(("", "No coverage (no reported executions): " +
                      ", ".join(untested) + "."))
    lines.extend(("", "Unreported tests were collected but have no final "
                  "outcome (they may have started). Invalid/timeouts count "
                  "modules, not fabricated test failures. Missing shards "
                  "have no summary (check setup "
                  "and cancelled jobs). UXPASS does not fail the run."))
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--finalize", metavar="LABEL",
                        help="record setup failure or interruption if needed")
    args = parser.parse_args()
    if args.finalize:
        finalize(args.directory, args.finalize)
    print(aggregate(list(args.directory.rglob("summary.json"))), end="")
