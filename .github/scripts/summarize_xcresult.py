"""Summarize an Xcode test result bundle: results, failures and line coverage.

    python summarize_xcresult.py Tests.xcresult [tests-summary.md]

Reads `xcrun xcresulttool get test-results summary` (covers Swift Testing and
XCTest) and `xcrun xccov view --report --json` for the app target's coverage.
"""
import json
import os
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


def build_failure_markdown(errors):
    lines = ["## ❌ Build failed, tests didn't run", "", "| Where | Error |", "|---|---|"]
    for location, message in errors:
        where = f"`{location}`" if location else ""
        lines.append(f"| {where} | {message.replace('|', chr(92) + '|')} |")
    return "\n".join(lines) + "\n"


def to_markdown(results, coverage):
    total = results["total"]
    percent = results["passed"] / total * 100 if total else 0.0
    status = f"❌ {results['failed']} test(s) failed" if results["failed"] else "✅ All tests passed"
    lines = [f"## {status}", "",
             "| Total | Passed | Failed | Skipped | Pass rate |", "|---|---|---|---|---|",
             f"| {total} | {results['passed']} | {results['failed']} | {results['skipped']} | {percent:.1f}% |"]
    if results["failures"]:
        lines += ["", "### Failures", "", "| Test | Error |", "|---|---|"]
        for name, message in results["failures"]:
            lines.append(f"| `{name}` | {message.replace('|', chr(92) + '|')} |")
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
    bundle = sys.argv[1] if len(sys.argv) > 1 else "Tests.xcresult"
    markdown_path = sys.argv[2] if len(sys.argv) > 2 else None
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
    write_markdown(to_markdown(results, coverage), markdown_path)


if __name__ == "__main__":
    main()
