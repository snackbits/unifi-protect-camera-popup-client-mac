import XCTest
@testable import AppCore

final class FileChecksumTests: XCTestCase {
    private func temp(_ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("checksum-\(UUID().uuidString)")
        try contents.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testKnownHashes() throws {
        XCTAssertEqual(try FileChecksum.sha256(of: temp(Data("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try FileChecksum.sha256(of: temp(Data())),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testMoreThanOneChunk() throws {
        let big = Data(repeating: 0x61, count: (1 << 20) * 2 + 7)
        let url = try temp(big)
        XCTAssertEqual(try FileChecksum.sha256(of: url), try FileChecksum.sha256(of: temp(big)))
        XCTAssertNotEqual(try FileChecksum.sha256(of: url), try FileChecksum.sha256(of: temp(big.prefix(big.count - 1))))
    }

    func testMatchesNeedsSizeAndHash() throws {
        let url = try temp(Data("abc".utf8))
        let good = VoiceFile(path: "x/abc", size: 3, sha256: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
        XCTAssertTrue(FileChecksum.matches(url, good))
        XCTAssertFalse(FileChecksum.matches(url, VoiceFile(path: "x/abc", size: 4, sha256: good.sha256)))
        XCTAssertFalse(FileChecksum.matches(url, VoiceFile(path: "x/abc", size: 3, sha256: String(repeating: "0", count: 64))))
        XCTAssertFalse(FileChecksum.matches(URL(fileURLWithPath: "/nonexistent"), good))
    }
}
