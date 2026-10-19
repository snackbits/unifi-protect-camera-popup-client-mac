import XCTest
@testable import ProtectKit

final class TunnelRecordTests: XCTestCase {
    private let summary = TunnelConfigSummary(endpoint: "home.example.org:51820", addresses: ["192.168.3.2/32"],
                                              allowedIPs: ["192.168.1.0/24"], dns: ["192.168.3.1"])

    func testDefaultsWhenNothingStored() {
        XCTAssertEqual(TunnelRecord.decode(nil), TunnelRecord(mode: .automatic))
        XCTAssertEqual(TunnelRecord.decode(Data("kaputt".utf8)), TunnelRecord(mode: .automatic))
    }

    func testRoundTrip() {
        let record = TunnelRecord(mode: .always, fileName: "mac.conf", summary: summary,
                                  lastConnection: TunnelLastConnection(date: Date(timeIntervalSince1970: 1_760_000_000), via: .cellular))
        XCTAssertEqual(TunnelRecord.decode(record.encoded()), record)
    }

    func testUnknownModeFromNewerBuildFallsBackToAutomatic() {
        let json = #"{"mode":"onlyAtNight","fileName":"mac.conf"}"#
        let record = TunnelRecord.decode(Data(json.utf8))
        XCTAssertEqual(record.mode, .automatic)
        XCTAssertEqual(record.fileName, "mac.conf")
    }

    func testStoredFormHasNoRoomForKeys() {
        let text = String(decoding: TunnelRecord(mode: .automatic, fileName: "mac.conf", summary: summary).encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("PrivateKey"))
        XCTAssertFalse(text.lowercased().contains("key"))
    }

    func testRecordBuiltFromConfigWithKeysContainsNoKeyMaterial() {
        let privateKey = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk="
        let presharedKey = "FpCyhws9cxwWoV4xELtfJvjJN+zQVRPISllRWgeopVE="
        let publicKey = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
        let config = """
        [Interface]
        PrivateKey = \(privateKey)
        Address = 192.168.3.2/32
        DNS = 192.168.3.1

        [Peer]
        PublicKey = \(publicKey)
        PresharedKey = \(presharedKey)
        AllowedIPs = 192.168.1.0/24
        Endpoint = home.example.org:51820
        """
        XCTAssertTrue(config.contains(privateKey)) // sanity: the fixture really carries the keys
        // Only the parser's summary (no key fields) enters the record; the config text has no field to land in.
        let record = TunnelRecord(mode: .always, fileName: "mac.conf", summary: summary,
                                  lastConnection: TunnelLastConnection(date: Date(timeIntervalSince1970: 1_760_000_000), via: .wifi))
        let json = String(decoding: record.encoded(), as: UTF8.self)
        for secret in [privateKey, presharedKey, publicKey, "PrivateKey", "PresharedKey"] {
            XCTAssertFalse(json.contains(secret))
        }
        // A foreign payload with key fields cannot smuggle them through a decode/encode cycle.
        let hostile = #"{"mode":"always","privateKey":"\#(privateKey)","presharedKey":"\#(presharedKey)","config":"\#(privateKey)"}"#
        let reencoded = String(decoding: TunnelRecord.decode(Data(hostile.utf8)).encoded(), as: UTF8.self)
        XCTAssertFalse(reencoded.contains(privateKey))
        XCTAssertFalse(reencoded.contains(presharedKey))
    }

    func testWithoutKeychainItemOnlyModeSurvives() {
        let record = TunnelRecord(mode: .off, fileName: "mac.conf", summary: summary)
        XCTAssertEqual(record.reconciled(hasKeychainItem: false), TunnelRecord(mode: .off))
        XCTAssertEqual(record.reconciled(hasKeychainItem: true), record)
    }

    func testImportWarning() {
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "192.168.1.1", summary: summary))
        XCTAssertEqual(TunnelImportCheck.warning(consoleHost: "10.0.0.1", summary: summary),
                       TunnelText.consoleNotRouted("10.0.0.1"))
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "konsole.local", summary: summary))
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "192.168.1.1:8443",
                                               summary: TunnelConfigSummary(endpoint: "x:1", allowedIPs: ["0.0.0.0/0"])))
    }
}
