import XCTest
import UIKit
@testable import Dose

final class NotesUnitTests: XCTestCase {
    /// A corrupt / undecodable photo blob yields a nil UIImage, so the attachment strip renders nothing
    /// rather than crashing (the audit's corrupt-photo finding; the removable placeholder tile is v1.1).
    func testUndecodablePhotoDataIsNilNotACrash() {
        XCTAssertNil(UIImage(data: Data([0x00, 0x01, 0x02])), "undecodable bytes → nil image (no crash)")
    }

    /// A note is discarded on exit ONLY when it's truly empty — and NOT while a photo is still loading
    /// (the async append would otherwise target a deleted note → silent loss / a write to a dead model).
    func testShouldDiscardOnlyForATrulyEmptyNoteWithNoPendingLoad() {
        // Empty in every dimension, nothing loading → discard.
        XCTAssertTrue(NoteEditorView.shouldDiscard(trimmedText: "", hasTags: false, hasMedicine: false,
                                                   hasPhotos: false, photosLoading: false))
        // Any content keeps it.
        XCTAssertFalse(NoteEditorView.shouldDiscard(trimmedText: "hi", hasTags: false, hasMedicine: false,
                                                    hasPhotos: false, photosLoading: false), "text keeps it")
        XCTAssertFalse(NoteEditorView.shouldDiscard(trimmedText: "", hasTags: true, hasMedicine: false,
                                                    hasPhotos: false, photosLoading: false), "a tag keeps it")
        XCTAssertFalse(NoteEditorView.shouldDiscard(trimmedText: "", hasTags: false, hasMedicine: true,
                                                    hasPhotos: false, photosLoading: false), "a linked medicine keeps it")
        XCTAssertFalse(NoteEditorView.shouldDiscard(trimmedText: "", hasTags: false, hasMedicine: false,
                                                    hasPhotos: true, photosLoading: false), "an attached photo keeps it")
        // FAIL-BEFORE / PASS-AFTER: a text-empty note with a photo still LOADING must be KEPT.
        XCTAssertFalse(NoteEditorView.shouldDiscard(trimmedText: "", hasTags: false, hasMedicine: false,
                                                    hasPhotos: false, photosLoading: true),
                       "a note with a photo still loading must not be discarded")
    }
}
