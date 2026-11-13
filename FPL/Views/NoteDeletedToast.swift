//
//  NoteDeletedToast.swift
//  FPL
//

import SwiftData

extension Toast {
    /// "Note deleted" with Undo, which puts the note back and syncs it.
    @MainActor
    static func noteDeleted(_ deleted: DeletedNote, sync: NoteSync, context: ModelContext) -> Toast {
        Toast("Note deleted", action: Action("Undo") {
            let note = sync.restore(deleted)
            context.insert(note)
            sync.changed(note)
            context.saveNotes("Restored a deleted note")
        })
    }
}
