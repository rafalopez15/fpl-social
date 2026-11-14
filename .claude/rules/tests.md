---
paths:
  - "FPLTests/**"
  - "FPLUITests/**"
  - "FPL/Support/LaunchOptions.swift"
---

# Tests

- Decoding tests build variants of `ElementDecodingTests`' fixture. **Only `ContractTests` reads `FPLTests/Fixtures/*.json`**, which are real production responses, one per endpoint (manager 1, league 314).
- When the API changes a response on purpose, run `.github/scripts/fetch_contract_fixtures.sh` and commit the fixtures with the app change. A new endpoint gets a fixture and a route in `FixtureServer`.
- UI tests launch with `-uiTesting` (in-memory SwiftData, emptied UserDefaults, no auth) and `-FPLAPIBaseURL` pointing at `FixtureServer`, which serves the fixtures and records `requestedPaths`. Both arguments are Debug only.
- **Read expected values from the fixture files**, never hard-code them, so refreshing fixtures doesn't break tests.
- Tab buttons match three elements: tap with `app.buttons["Notes"].firstMatch`. Cards combine their texts: match with `label CONTAINS`.
- Run UI tests with `-parallel-testing-enabled NO`, as CI does.
- **One Swift Testing test needs `()`**: `-only-testing:"FPLTests/TeamSyncTests/someTest()"`. Without it nothing runs and the run still says TEST SUCCEEDED. For a flaky test, `-test-iterations N` with `-resultBundlePath`, then `xcrun xcresulttool get test-results tests --path <bundle>` shows the failed expectation, which the console doesn't.
- Previews and tests use `NoteSync.preview` and `AccountStore(auth: nil)`.
