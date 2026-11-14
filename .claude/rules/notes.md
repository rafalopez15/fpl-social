---
paths:
  - "FPL/Model/Note.swift"
  - "FPL/Model/SyncedNote.swift"
  - "FPL/ViewModel/NoteSync.swift"
  - "FPL/Views/NotesView.swift"
  - "FPL/Views/NoteEditorView.swift"
  - "FPL/Views/PlayerNotesView.swift"
  - "FPL/Views/NoteDeletedToast.swift"
  - "FPL/Views/TransferPromptView.swift"
  - "FPL/Model/Mention.swift"
  - "FPL/ViewModel/PlayerSuggestions.swift"
  - "FPLTests/MentionTests.swift"
  - "FPLTests/NoteSyncTests.swift"
---

# Notes

## Saving and sync

- **Every write site calls `NoteSync`:** `added` after inserting, `changed` after an edit or undo, `deleting` before `context.delete`. Then `modelContext.saveNotes(_:)`, which saves at once and logs a failure. Saving never waits on the network.
- New `Note` fields are optional, so the SwiftData store migrates.
- The newer `updatedAt` wins (`NoteSync.apply`), against both the stored note and any change still waiting. Postgres keeps microseconds and the encoder sends milliseconds: compare with what was sent, not exact dates.
- Flushing stops at the first failure a retry could fix (offline, 503, signed out); a 404 or 422 drops that change so it can't block the rest.
- Signing out removes the account's notes, waiting changes and cursor. Device-only notes (`accountID` nil) stay.
- Undo (`NoteSync.restore`) keeps the sync id and sets `updatedAt` to now, so it beats the delete.
- Text is capped at 5,000 code points (`Note.maxTextLength`), counted as the API does.

## Behaviour

- **Past gameweeks' notes are read-only** (`Note.isLocked`), except a skipped transfer note with empty text. Swipe to delete still works on them: it's the only fix for a mistake.
- Deleting shows `Toast.noteDeleted` with Undo, which re-inserts a copy with the same gameweek, dates, players and sync id. No confirmation alert.
- Players are stored as `NotePlayer` (id and `webName`) so notes show without the player list.
- A note is about a player when he's linked or is in its transfer (`Note.isAbout`), not when named in the text.
- Notes match transfers on gameweek and both players (`Note.forTransfer`), never time: the API builds some chip-week rows.

## Linking players with @

- Typing `@` and part of a name shows up to five players in a bar above the keyboard (`safeAreaInset`, not a keyboard toolbar, which didn't show in the sheet). Picking one writes `@Name ` in place of what was typed and links him as a chip. The bar's `@` button types an `@`.
- **The chips are the links; the text is just text.** Deleting `@Saka` doesn't unlink him, and the chip's × does. Notes still save plain text, so sync and the API are unchanged.
- Mentions are highlighted where notes are read (`Mention.highlighted`: accent, bold), only for `@` plus a linked player's exact `webName`. Not while typing.
- Suggestions (`PlayerSuggestions`): your squad first, then total points, then name, matching the start of any name with case and accents folded (`ode` finds Ødegaard, `gross` finds Groß). Players already linked or who left the league are left out.
- Players come from `/api/elements`, reusing `LinkedTeamStore.players` when loaded. Never `ElementViewModel`, which loads one position at a time. After a failed load only Retry tries again, not each keystroke.
- No suggestions on locked or transfer notes (`canLinkPlayers`).

## Transfer prompt

- `LinkedTeamStore.checkForTransfers()` runs on launch, linking and becoming active, and prompts for transfers after `transfersSeenUntil` (per team). Linking sets it to now.
- Later and Save both save one note per transfer; swipe to dismiss is off so none are lost.
- To test without real transfers, link manager 1 and launch with `-transfersSeenUntilByTeam "<dict><key>1</key><date>2026-10-28T00:00:00Z</date></dict>"`.
