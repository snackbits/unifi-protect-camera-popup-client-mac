import XCTest
@testable import AppCore

final class MuteScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGlobalMuteCoversEveryCamera() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        XCTAssertTrue(schedule.isGloballyMuted(at: now.addingTimeInterval(899)))
        XCTAssertTrue(schedule.isMuted(entry: "A", at: now.addingTimeInterval(899)))
        XCTAssertFalse(schedule.isMuted(entry: "A", at: now.addingTimeInterval(900)))
        XCTAssertEqual(schedule.globalEnd(at: now), now.addingTimeInterval(900))
    }

    func testCameraMuteOnlyAffectsThatCamera() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        XCTAssertTrue(schedule.isMuted(entry: "A", at: now.addingTimeInterval(60)))
        XCTAssertFalse(schedule.isMuted(entry: "B", at: now.addingTimeInterval(60)))
        XCTAssertFalse(schedule.isGloballyMuted(at: now))
        XCTAssertEqual(schedule.cameraMuteEnd(entry: "A", at: now), now.addingTimeInterval(3600))
        XCTAssertNil(schedule.cameraMuteEnd(entry: "B", at: now))
    }

    func testNewLengthReplacesOldMute() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        XCTAssertEqual(schedule.cameraMuteEnd(entry: "A", at: now), now.addingTimeInterval(900))
    }

    // Review Focus 2
    func testSurvivesRestartAndExpiresWhileQuit() throws {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        schedule.mute(entry: "A", for: 3600, from: now)

        let reloaded = try JSONDecoder().decode(MuteSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(reloaded, schedule)
        XCTAssertTrue(reloaded.isMuted(entry: "B", at: now.addingTimeInterval(600)))

        let later = now.addingTimeInterval(7200)
        XCTAssertFalse(reloaded.isMuted(entry: "A", at: later))
        XCTAssertFalse(reloaded.isGloballyMuted(at: later))
        XCTAssertTrue(reloaded.activeCameraMutes(at: later).isEmpty)
        XCTAssertNil(reloaded.nextExpiry(after: later))

        var pruned = reloaded
        pruned.prune(at: later)
        XCTAssertEqual(pruned, MuteSchedule())
    }

    // Review Focus 3
    func testPruneDropsRemovedCameras() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "B", for: 3600, from: now)
        schedule.prune(at: now, validEntries: ["B"])
        XCTAssertEqual(schedule.activeCameraMutes(at: now).map(\.entry), ["B"])
    }

    func testActiveMutesSortedByEnd() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "B", for: 900, from: now)
        XCTAssertEqual(schedule.activeCameraMutes(at: now).map(\.entry), ["B", "A"])
    }

    func testNextExpiryIsEarliestFutureEnd() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 3600, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        XCTAssertEqual(schedule.nextExpiry(after: now), now.addingTimeInterval(900))
        XCTAssertEqual(schedule.nextExpiry(after: now.addingTimeInterval(1000)), now.addingTimeInterval(3600))
    }

    func testClearing() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        schedule.mute(entry: "B", for: 900, from: now)
        schedule.clear(entry: "A")
        XCTAssertFalse(schedule.cameras.keys.contains("A"))
        schedule.clearGlobal()
        XCTAssertNil(schedule.globalUntil)
        schedule.clearAll()
        XCTAssertEqual(schedule, MuteSchedule())
    }

    // Review Focus 1
    func testLegacyMigrationKeepsGlobalMute() throws {
        let legacyEnd = now.addingTimeInterval(600)
        XCTAssertEqual(MuteSchedule.migrated(stored: nil, legacyGlobalUntil: legacyEnd).globalUntil, legacyEnd)
        XCTAssertEqual(MuteSchedule.migrated(stored: nil, legacyGlobalUntil: nil), MuteSchedule())
        let stored = MuteSchedule(cameras: ["A": legacyEnd])
        XCTAssertEqual(MuteSchedule.migrated(stored: stored, legacyGlobalUntil: nil), stored)
        let broken = try JSONDecoder().decode(MuteSchedule.self, from: Data(#"{"globalUntil":"kaputt","cameras":7}"#.utf8))
        XCTAssertEqual(broken, MuteSchedule())
    }

    // The installed old app still writes only `muteUntil`: the later end wins.
    func testMigrationTakesLaterOfStoredAndLegacyGlobalEnd() {
        let early = now.addingTimeInterval(300)
        let late = now.addingTimeInterval(900)
        let cameras = ["A": early]
        let storedEarly = MuteSchedule(globalUntil: early, cameras: cameras)
        let storedLate = MuteSchedule(globalUntil: late, cameras: cameras)

        XCTAssertEqual(MuteSchedule.migrated(stored: storedEarly, legacyGlobalUntil: late).globalUntil, late)
        XCTAssertEqual(MuteSchedule.migrated(stored: storedLate, legacyGlobalUntil: early).globalUntil, late)
        XCTAssertEqual(MuteSchedule.migrated(stored: MuteSchedule(cameras: cameras), legacyGlobalUntil: late).globalUntil, late)
        XCTAssertEqual(MuteSchedule.migrated(stored: storedEarly, legacyGlobalUntil: late).cameras, cameras)
    }
}
