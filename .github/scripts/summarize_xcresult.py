"""Summarize an Xcode test result bundle: results, failures and line coverage.

    python summarize_xcresult.py Tests.xcresult [tests-summary.md] [label] [--tsan-log xcodebuild.log]

`label` names the tests in the heading ("UI tests"); it defaults to "tests".
`--tsan-log` reads xcodebuild's output for Thread Sanitizer reports: a race aborts
the test process, so the result bundle only shows a crashed test.

Reads `xcrun xcresulttool get test-results summary` (covers Swift Testing and
XCTest) and `xcrun xccov view --report --json` for the app target's coverage.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from urllib.parse import unquote, urlparse

from summary_output import write_markdown

APP_TARGET = "FPL.app"


def run_json(*args):
    return json.loads(subprocess.run(["xcrun", *args], check=True, capture_output=True, text=True).stdout)


def read_results(bundle):
    summary = run_json("xcresulttool", "get", "test-results", "summary", "--path", bundle, "--compact")
    failures = []
    for failure in summary.get("testFailures", []):
        text = (failure.get("failureText") or "").splitlines()
        failures.append((failure.get("testIdentifierString") or failure.get("testName", "?"),
                         (text[0] if text else "")[:200]))
    return {
        "total": summary.get("totalTestCount", 0),
        "passed": summary.get("passedTests", 0),
        "failed": summary.get("failedTests", 0),
        "skipped": summary.get("skippedTests", 0),
        "failures": failures,
    }


def read_build_errors(bundle):
    """Compiler errors when the build failed before any tests ran, as (location, message)."""
    build = run_json("xcresulttool", "get", "build-results", "--path", bundle, "--compact")
    if build.get("status") != "failed":
        return []
    errors = []
    for error in build.get("errors", []):
        url = error.get("sourceURL")
        location = ""
        if url:
            parsed = urlparse(url)
            path = os.path.relpath(unquote(parsed.path), os.getcwd())
            line = dict(p.split("=") for p in parsed.fragment.split("&") if "=" in p).get("StartingLineNumber")
            # The fragment's line numbers are zero-based.
            location = f"{path}:{int(line) + 1}" if line else path
        errors.append((location, error.get("message", "")[:200]))
    return errors


def read_coverage(bundle):
    """The app target's line coverage and its files, lowest coverage first. None if absent."""
    try:
        report = run_json("xccov", "view", "--report", "--json", bundle)
    except subprocess.CalledProcessError:
        return None
    target = next((t for t in report.get("targets", []) if t.get("name") == APP_TARGET), None)
    if not target:
        return None
    files = sorted(target.get("files", []), key=lambda f: (f["lineCoverage"], f["name"]))
    return target, files


ANSI = re.compile(r"\x1b\[[0-9;]*m")


def read_tsan_reports(log_path):
    """Each Thread Sanitizer report in the log: its summary and the top frame of each access."""
    if not log_path or not os.path.exists(log_path):
        return []
    reports, current = [], None
    with open(log_path, errors="replace") as log:
        for raw in log:
            line = ANSI.sub("", raw).strip()
            if line.startswith("WARNING: ThreadSanitizer:"):
                current = {"summary": line.removeprefix("WARNING: ThreadSanitizer: "), "frames": []}
                in_access = False
            elif current is None:
                continue
            elif line.endswith(":") and not line.startswith("#"):
                # "Modifying access of ... by thread T17:", "Previous write of size 1 ...:",
                # then "Location is heap block ..." and thread creation, which aren't the race.
                in_access = " access " in line or " write of " in line or " read of " in line
            elif in_access and line.startswith("#0 "):
                current["frames"].append(line.removeprefix("#0 "))
            elif line.startswith("SUMMARY: ThreadSanitizer:"):
                current["summary"] = line.removeprefix("SUMMARY: ThreadSanitizer: ")
                reports.append(current)
                current = None
    return reports


def tsan_markdown(reports):
    lines = ["", f"### Thread Sanitizer found {len(reports)} race{'s' if len(reports) != 1 else ''}", ""]
    for report in reports:
        lines.append(f"- {report['summary']}")
        lines += [f"  - `{frame}`" for frame in report["frames"]]
    return "\n".join(lines) + "\n"


def build_failure_markdown(errors):
    lines = ["## ❌ Build failed, tests didn't run", "", "| Where | Error |", "|---|---|"]
    for location, message in errors:
        where = f"`{location}`" if location else ""
        lines.append(f"| {where} | {message.replace('|', chr(92) + '|')} |")
    return "\n".join(lines) + "\n"


def to_markdown(results, coverage, label="tests", tsan_reports=()):
    total = results["total"]
    percent = results["passed"] / total * 100 if total else 0.0
    status = f"❌ {results['failed']} of the {label} failed" if results["failed"] else f"✅ All {label} passed"
    lines = [f"## {status}", "",
             "| Total | Passed | Failed | Skipped | Pass rate |", "|---|---|---|---|---|",
             f"| {total} | {results['passed']} | {results['failed']} | {results['skipped']} | {percent:.1f}% |"]
    if results["failures"]:
        lines += ["", "### Failures", "", "| Test | Error |", "|---|---|"]
        for name, message in results["failures"]:
            lines.append(f"| `{name}` | {message.replace('|', chr(92) + '|')} |")
    if tsan_reports:
        lines.append(tsan_markdown(tsan_reports).rstrip("\n"))
    if coverage:
        target, files = coverage
        lines += ["", f"### Coverage: {target['lineCoverage'] * 100:.1f}% of lines in `{APP_TARGET}` "
                      f"({target['coveredLines']}/{target['executableLines']})", "",
                  "<details><summary>By file, lowest first</summary>", "",
                  "| File | Coverage | Lines |", "|---|---|---|"]
        for f in files:
            lines.append(f"| `{f['name']}` | {f['lineCoverage'] * 100:.1f}% | {f['coveredLines']}/{f['executableLines']} |")
        lines += ["", "</details>"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", nargs="?", default="Tests.xcresult")
    parser.add_argument("markdown_path", nargs="?")
    parser.add_argument("label", nargs="?", default="tests")
    parser.add_argument("--tsan-log")
    args = parser.parse_args()
    bundle, markdown_path, label = args.bundle, args.markdown_path, args.label
    if not os.path.exists(bundle):
        message = f"No result bundle at {bundle}; the build likely failed before tests ran."
        print(message)
        write_markdown(f"## ⚠️ No test results\n\n{message}\n", markdown_path)
        return

    results = read_results(bundle)
    if results["total"] == 0:
        errors = read_build_errors(bundle)
        if errors:
            print("Build failed:")
            for location, message in errors:
                print(f"  {location} {message}")
            write_markdown(build_failure_markdown(errors), markdown_path)
            return
    coverage = read_coverage(bundle)
    print(f"{results['passed']}/{results['total']} passed, {results['failed']} failed, {results['skipped']} skipped")
    for name, message in results["failures"]:
        print(f"  FAILED {name}: {message}")
    reports = read_tsan_reports(args.tsan_log)
    for report in reports:
        print(f"  TSAN {report['summary']}")
    write_markdown(to_markdown(results, coverage, label, reports), markdown_path)


if __name__ == "__main__":
    main()
