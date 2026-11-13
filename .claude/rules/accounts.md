---
paths:
  - "FPL/Model/Account.swift"
  - "FPL/Networking/AuthService.swift"
  - "FPL/ViewModel/AccountStore.swift"
  - "FPL/Views/SignInView.swift"
  - "FPL/Views/CardOptionsMenu.swift"
  - "FPL/Support/TestUser.swift"
  - "Config/**"
  - "FPLTests/AccountTests.swift"
---

# Accounts

- Supabase Auth through `supabase-swift`'s `Auth` product only. Debug uses **staging**; Release's URL is empty until production has accounts, which hides the Account card (`.unavailable`). The publishable key is public.
- **A staging token only works against a Vercel preview**, so test sign-in with `-FPLAPIBaseURL` set to one. Until FPL-55, codes only reach `fpl.social.test@gmail.com`. Never delete that user.
- **Account requests go through `AccountStore.withAccessToken`:** a 401 refreshes once and retries; a second 401 or failed refresh signs out with "You were signed out". A connection error while refreshing stays signed in.
- `FPLAPIClient.request` adds `Authorization` to `me` and `me/...` routes only, whatever the caller passes.
- After signing in the app calls `GET /api/me` once, which creates the account; if that fails it signs out again.
- Our own sign-out sets the state before telling the SDK, so the SDK's event doesn't show "You were signed out".
- The session lives in the keychain. UI tests run with no auth.

## Test user (Debug only)

- Everything is inside `#if DEBUG`, tests included. It shows only with both credentials in the gitignored `Config/Secrets.xcconfig`, a staging Supabase URL and a non-production API.
- The user exists in staging only; never create it in production. Don't log the credentials.

## Deleting an account

- While `DELETE /api/me` runs the state is `.deleting`: sync requests stop, but the account's notes, waiting changes and cursor stay (`AccountStore.ownerID`), so a failure loses nothing.
- Only a 503 or a request that never left the device proves nothing was deleted. A timeout or dropped connection is `.unconfirmed`; retrying is safe since a second delete is also 204.
- To test, make a throwaway password user on staging and put it in `Secrets.xcconfig`.
