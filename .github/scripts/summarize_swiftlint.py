"""Summarize a SwiftLint JSON report, annotate the PR, and fail on any violation.

    python summarize_swiftlint.py swiftlint.json [swiftlint-summary.md]

The Linux SwiftLint image can report a violation twice, so violations are
de-duplicated here and the annotations are printed from this script rather than
SwiftLint's github-actions-logging reporter.
"""
import json
import os
import sys
from collections import Counter

from summary_output import write_markdown


def read_violations(report_path, root):
    with open(report_path, encoding="utf-8") as report:
        raw = json.load(report)
    seen = {}
    for item in raw:
        path = os.path.relpath(item["file"], root) if os.path.isabs(item["file"]) else item["file"]
        key = (path, item["line"], item.get("character") or 0, item["rule_id"])
        seen[key] = {"file": path, "line": item["line"], "column": item.get("character") or 0,
                     "rule": item["rule_id"], "reason": item["reason"]}
    return sorted(seen.values(), key=lambda v: (v["file"], v["line"], v["column"]))


def to_markdown(violations):
    if not violations:
        return "## ✅ SwiftLint: no violations\n"
    lines = [f"## ❌ SwiftLint: {len(violations)} violation(s)", "",
             "| Rule | Count |", "|---|---|"]
    for rule, count in Counter(v["rule"] for v in violations).most_common():
        lines.append(f"| `{rule}` | {count} |")
    lines += ["", "| File | Rule | Reason |", "|---|---|---|"]
    for v in violations[:50]:
        reason = v["reason"].replace("|", r"\|")
        lines.append(f"| `{v['file']}:{v['line']}` | `{v['rule']}` | {reason} |")
    if len(violations) > 50:
        lines.append(f"\n{len(violations) - 50} more in the job log.")
    return "\n".join(lines) + "\n"


def main():
    report_path = sys.argv[1] if len(sys.argv) > 1 else "swiftlint.json"
    markdown_path = sys.argv[2] if len(sys.argv) > 2 else None
    root = os.environ.get("SWIFTLINT_ROOT", os.getcwd())
    if not os.path.exists(report_path):
        message = f"No SwiftLint report at {report_path}; SwiftLint likely failed to run."
        print(message)
        write_markdown(f"## ⚠️ SwiftLint didn't report results\n\n{message}\n", markdown_path)
        sys.exit(1)

    violations = read_violations(report_path, root)
    for v in violations:
        print(f"::error file={v['file']},line={v['line']},col={v['column']}::{v['reason']} ({v['rule']})")
    print(f"{len(violations)} violation(s)")
    write_markdown(to_markdown(violations), markdown_path)
    sys.exit(1 if violations else 0)


if __name__ == "__main__":
    main()
