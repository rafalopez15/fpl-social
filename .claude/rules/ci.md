---
paths:
  - ".github/**"
  - ".swiftlint.yml"
  - "FPLTests/.swiftlint.yml"
  - "FPL.xcodeproj/**"
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
