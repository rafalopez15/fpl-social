---
paths:
  - ".github/**"
  - ".swiftlint.yml"
  - "FPLTests/.swiftlint.yml"
  - "FPL.xcodeproj/**"
  - ".gitleaks.toml"
  - ".gitleaksignore"
---

# CI

- `swift.yml`: SwiftLint `--strict` on Linux (pinned `ghcr.io/realm/swiftlint:0.65.1`; locally `docker run --rm -v "$PWD":/work -w /work ghcr.io/realm/swiftlint:0.65.1 swiftlint lint --strict`), then on macOS the unit tests under Thread Sanitizer, the UI tests and a Release build, then one PR comment found by `<!-- ios-ci-report -->`.
- **Fix SwiftLint violations rather than disabling rules.** A rule that doesn't fit changes `.swiftlint.yml` in its own commit with a reason.
- **Warnings as errors:** set `FPL_WARNINGS_AS_ERRORS=YES`, never `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the command line, which also reaches the Swift packages and conflicts with their `-suppress-warnings`.
- Thread Sanitizer is set on the command line because the scheme isn't committed. `TEST_RUNNER_TSAN_OPTIONS=halt_on_error=1` makes a race fail its test.
- Test steps pass `-parallel-testing-enabled NO`. Builds pass `COMPILER_INDEX_STORE_ENABLE=NO` and `-clonedSourcePackagesDirPath SourcePackages`, cached on `Package.resolved`. Don't cache DerivedData.
- Keep macOS to the one build-and-test job: it costs about 10 times Linux minutes.
- `contract.yml` runs daily at 07:00 UTC: it fetches production's responses and runs only `ContractTests`. A 503 and the picks 404 before the season keep the committed fixture with a warning; other errors fail.
- Pin actions by full commit hash with the release as a comment.

## Secret scan

- `gitleaks.yml` (check **Gitleaks**) scans the full history on every PR and push to `main`, with no path filter so the required check always runs. Its binary is pinned by `GITLEAKS_VERSION` and `GITLEAKS_SHA256`, bumped together by hand; keep them in step with fplAPI's.
- `.gitleaks.toml` adds a `supabase-secret-key` rule to the defaults, and allows the Supabase publishable key only in `project.pbxproj` (`condition = "AND"`: a path alone would skip the whole file).
- **On a finding, rotate the secret first**: the repo is public. On a PR branch, rewrite the branch to drop the commit. Once on `main`, add the fingerprint (`<commit>:<file>:<rule>:<line>`, from the job log) to `.gitleaksignore` after rotating.
- A false positive gets the narrowest allowlist in `.gitleaks.toml` (path plus value regex, with `condition = "AND"`) or its fingerprint. Never turn a rule off.
- Locally: `git fetch --prune`, then `docker run --rm -v "$PWD":/repo:ro -w /repo --entrypoint sh ghcr.io/gitleaks/gitleaks:v8.30.1 -c "git config --global --add safe.directory '*' && gitleaks git --redact ."`. `gitleaks git` scans every ref, so without the prune a deleted branch's leftover ref, such as a test PR's fake secrets, is flagged. `gitleaks dir` also reads gitignored files, so it flags `Config/Secrets.xcconfig`; that never reaches CI.
