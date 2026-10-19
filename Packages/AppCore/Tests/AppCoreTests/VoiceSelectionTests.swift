import XCTest
@testable import AppCore

final class VoiceSelectionTests: XCTestCase {
    private let emotional = PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 7)

    func testIdentifierRoundTrip() {
        XCTAssertEqual(emotional.identifier, "piper:de_DE-thorsten_emotional-medium#7")
        XCTAssertEqual(PiperVoiceRef(identifier: emotional.identifier), emotional)
        XCTAssertEqual(PiperVoiceRef(identifier: "piper:de_DE-thorsten-medium"), .standard)
        for bad in [nil, "", "piper:", "piper:#1", "piper:x#-1", "piper:x#a", "com.apple.voice.premium.de-DE.Anna"] {
            XCTAssertNil(PiperVoiceRef(identifier: bad), bad ?? "nil")
        }
    }

    func testLabels() {
        XCTAssertEqual(PiperVoiceRef.standard.label, "Thorsten · mittel")
        XCTAssertEqual(emotional.label, "Thorsten emotional · mittel · flüsternd")
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-mls-medium", speaker: 11).label, "Unbekannte Stimme")
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-pavoque-low").label, "Unbekannte Stimme")
        // A speaker outside the range falls back to the voice's default.
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 99).resolved?.speaker, 4)
    }

    func testOldMacOSAnnouncementKeepsItsFileAndAsksForRerendering() {
        let old = Announcement(name: "Hallo", kind: .speech, text: "Hallo.",
                               voiceIdentifier: "com.apple.voice.premium.de-DE.Anna", fileName: "a.caf", duration: 1)
        XCTAssertEqual(AnnouncementVoice.of(old), .legacyMacOS)
        XCTAssertEqual(AnnouncementVoice.note(for: old), "macOS (alt) – mit „Übernehmen“ neu erzeugen")
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: old), .standard)
        // Same text, Thorsten selected: still re-renderable.
        XCTAssertTrue(AnnouncementVoice.canApply(old, text: "Hallo.", selection: .standard))
    }

    func testTextAboveTheLimitCannotBeApplied() {
        let entry = Announcement(name: "Neu", kind: .speech, voiceIdentifier: PiperVoiceRef.standard.identifier)
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: String(repeating: "a", count: 1_000), selection: .standard))
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: String(repeating: "a", count: 1_001), selection: .standard))
    }

    func testBundledRecordingCountsAsThorstenMedium() {
        let bundled = SoundSettings.bundledBinGleichDa
        XCTAssertEqual(AnnouncementVoice.of(bundled), .bundledRecording)
        XCTAssertNil(AnnouncementVoice.note(for: bundled))
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: bundled), .standard)
        XCTAssertFalse(AnnouncementVoice.canApply(bundled, text: bundled.text, selection: .standard))
        XCTAssertTrue(AnnouncementVoice.canApply(bundled, text: bundled.text, selection: emotional))
        XCTAssertTrue(AnnouncementVoice.canApply(bundled, text: "Bin gleich da.", selection: .standard))
    }

    func testPiperAnnouncement() {
        let entry = Announcement(name: "X", kind: .speech, text: "Paket bitte abstellen.",
                                 voiceIdentifier: emotional.identifier, fileName: "x.wav", duration: 2)
        XCTAssertEqual(AnnouncementVoice.of(entry), .piper(emotional))
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: entry), emotional)
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: " Paket bitte abstellen. ", selection: emotional))
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: "Paket bitte abstellen.", selection: .standard))
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: "   ", selection: .standard))
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: "Neu", selection: PiperVoiceRef(voiceId: "de_DE-pavoque-low")))
    }

    func testOutOfRangeSpeakerStartsClampedAndNothingToApply() {
        let entry = Announcement(name: "X", kind: .speech, text: "Hallo.",
                                 voiceIdentifier: "piper:de_DE-thorsten_emotional-medium#99", fileName: "x.wav", duration: 1)
        let neutral = PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 4)
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: entry), neutral)
        // Nothing changed in the editor: „Übernehmen“ stays inactive.
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: "Hallo.", selection: AnnouncementVoice.initialSelection(for: entry)))
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: "Hallo.", selection: emotional))
        // A text entry not rendered yet keeps its (clamped) voice too.
        let fresh = Announcement(name: Announcement.newName, kind: .speech, voiceIdentifier: "piper:de_DE-thorsten_emotional-medium#500")
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: fresh), neutral)
    }

    func testRemovedVoiceStillPlaysButAsksForRerendering() {
        let entry = Announcement(name: "X", kind: .speech, text: "Hallo.",
                                 voiceIdentifier: "piper:de_DE-pavoque-low#0", fileName: "x.wav", duration: 1)
        XCTAssertEqual(AnnouncementVoice.note(for: entry), "Diese Stimme gibt es nicht mehr – mit „Übernehmen“ neu erzeugen")
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: entry), .standard)
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: "Hallo.", selection: .standard))
    }

    func testNewTextAndMP3Entries() {
        let fresh = Announcement(name: Announcement.newName, kind: .speech, voiceIdentifier: PiperVoiceRef.standard.identifier)
        XCTAssertEqual(AnnouncementVoice.of(fresh), .none)
        XCTAssertFalse(AnnouncementVoice.canApply(fresh, text: "", selection: .standard))
        XCTAssertTrue(AnnouncementVoice.canApply(fresh, text: "Hallo", selection: .standard))
        let mp3 = Announcement(name: "Gong", kind: .file, fileName: "g.mp3", duration: 3)
        XCTAssertEqual(AnnouncementVoice.of(mp3), .none)
        XCTAssertTrue(AnnouncementVoice.canApply(mp3, text: "Hallo", selection: .standard))
    }
}

final class VoiceMenuTests: XCTestCase {
    func testMenuTitlesAndSizes() throws {
        let kerstin = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-kerstin-low"))
        XCTAssertEqual(kerstin.sizeText, "63 MB")
        XCTAssertEqual(kerstin.menuTitle(.notDownloaded), "Kerstin · niedrig – 63 MB laden")
        XCTAssertEqual(kerstin.menuTitle(.downloaded), "Kerstin · niedrig – geladen")
        XCTAssertEqual(PiperVoiceCatalog.defaultVoice.menuTitle(.notDownloaded), "Thorsten · mittel – 63 MB laden")
        XCTAssertEqual(PiperVoiceCatalog.defaultVoice.menuTitle(.downloaded), "Thorsten · mittel – geladen")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-thorsten-high")?.sizeText, "114 MB")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-eva_k-x_low")?.sizeText, "21 MB")
    }

    func testProgressText() throws {
        let kerstin = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-kerstin-low"))
        XCTAssertEqual(kerstin.progressText(received: 23_400_000), "Lade „Kerstin · niedrig“ … 23 von 63 MB")
        XCTAssertEqual(kerstin.progressText(received: -5), "Lade „Kerstin · niedrig“ … 0 von 63 MB")
        XCTAssertEqual(kerstin.progressText(received: 999_000_000), "Lade „Kerstin · niedrig“ … 63 von 63 MB")
    }

    func testDownloadHintNamesSizeAndInternet() throws {
        XCTAssertEqual(PiperVoiceCatalog.defaultVoice.downloadHint,
                       "Die Standardstimme wird beim ersten Anhören oder Übernehmen geladen (63 MB, einmalig, braucht Internet) – danach auf diesem Mac erzeugt, ohne Internet.")
        let kerstin = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-kerstin-low"))
        XCTAssertEqual(kerstin.downloadHint,
                       "Wird beim ersten Anhören oder Übernehmen geladen (63 MB, einmalig, braucht Internet) – danach auf diesem Mac erzeugt, ohne Internet.")
    }

    func testMenuOrderStartsWithTheDefaultVoiceAndLeavesOutPavoque() {
        let ids = PiperVoice.menuOrder.map(\.id)
        XCTAssertEqual(ids.first, "de_DE-thorsten-medium")
        XCTAssertEqual(ids.count, 8)
        XCTAssertFalse(ids.contains("de_DE-pavoque-low"))
        XCTAssertEqual(Set(ids).count, 8)
    }

    func testLicenseText() {
        XCTAssertEqual(PiperVoiceCatalog.defaultVoice.licenseText, "Lizenz der Stimme: CC0 1.0 · Thorsten-Voice (Thorsten Müller)")
    }
}

final class PreferredVoiceTests: XCTestCase {
    private let thorsten = PiperVoiceCatalog.voice(id: PiperVoiceCatalog.defaultVoiceId)!
    private let emotional = PiperVoiceCatalog.voice(id: "de_DE-thorsten_emotional-medium")!

    private func rendered(_ ref: PiperVoiceRef) -> Announcement {
        Announcement(name: "X", kind: .speech, text: "Hallo.", voiceIdentifier: ref.identifier, fileName: "x.wav", duration: 1)
    }

    func testNothingInstalledFallsBackToThorsten() {
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: [], installed: []), .standard)
    }

    func testNoUsageTakesTheFirstInstalledVoice() {
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: [], installed: [emotional]), PiperVoiceRef(voice: emotional))
    }

    func testMostUsedInstalledVoiceWins() {
        let angry = PiperVoiceRef(voiceId: emotional.id, speaker: 0)
        let list = [rendered(.standard), rendered(angry), rendered(angry)]
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: list, installed: [thorsten, emotional]), angry)
    }

    func testMostUsedButNotInstalledIsSkipped() {
        let angry = PiperVoiceRef(voiceId: emotional.id, speaker: 0)
        let list = [rendered(.standard), rendered(angry), rendered(angry)]
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: list, installed: [thorsten]), .standard)
    }

    func testUnrenderedAndBundledEntriesDoNotCount() {
        let angry = PiperVoiceRef(voiceId: emotional.id, speaker: 0)
        let draft = Announcement(name: "Neu", kind: .speech, voiceIdentifier: angry.identifier)
        let list = [draft, draft, SoundSettings.bundledBinGleichDa, rendered(.standard)]
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: list, installed: [thorsten, emotional]), .standard)
    }

    func testTieGoesToTheEarlierInstalledVoice() {
        let angry = PiperVoiceRef(voiceId: emotional.id, speaker: 0)
        let list = [rendered(angry), rendered(.standard)]
        XCTAssertEqual(AnnouncementVoice.preferred(announcements: list, installed: [thorsten, emotional]), .standard)
    }

    func testFallbackOnlyForEntriesWithoutOwnVoice() {
        let angry = PiperVoiceRef(voiceId: emotional.id, speaker: 0)
        let mp3 = Announcement(name: "Gong", kind: .file, fileName: "g.mp3", duration: 2)
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: mp3, fallback: angry), angry)
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: SoundSettings.bundledBinGleichDa, fallback: angry), .standard)
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: rendered(.standard), fallback: angry), .standard)
    }

    func testMoveTakesTheTargetsPlace() {
        let a = Announcement(name: "A", kind: .file), b = Announcement(name: "B", kind: .file), c = Announcement(name: "C", kind: .file)
        var settings = SoundSettings()
        settings.announcements = [a, b, c]
        settings.move(id: c.id, to: a.id)
        XCTAssertEqual(settings.announcements.map(\.name), ["C", "A", "B"])
        settings.move(id: c.id, to: b.id)
        XCTAssertEqual(settings.announcements.map(\.name), ["A", "B", "C"])
    }
}
