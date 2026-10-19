import XCTest
@testable import AppCore

final class SecretVaultTests: XCTestCase {
    func testSetReadRemove() {
        var vault = SecretVault()
        XCTAssertTrue(vault.isEmpty)
        vault.set("key", service: "api", account: "default")
        vault.set("b", service: "rule", account: "2")
        vault.set("a", service: "rule", account: "1")
        XCTAssertEqual(vault.value(service: "api", account: "default"), "key")
        XCTAssertEqual(vault.accounts(service: "rule"), ["1", "2"])
        vault.set("new", service: "api", account: "default")
        XCTAssertEqual(vault.value(service: "api", account: "default"), "new")
        vault.remove(service: "rule", account: "1")
        vault.remove(service: "rule", account: "2")
        XCTAssertEqual(vault.accounts(service: "rule"), [])
        XCTAssertNil(vault.entries["rule"])
        vault.remove(service: "missing", account: "x")
        XCTAssertNil(vault.value(service: "missing", account: "x"))
    }

    func testRoundTripKeepsMultilineSecrets() throws {
        var vault = SecretVault()
        let config = "[Interface]\nPrivateKey = abc=\nAddress = 10.0.0.2/32\n\n[Peer]\nEndpoint = \"x\":51820\n"
        vault.set(config, service: "wg", account: "default")
        vault.set("ö-token", service: "action", account: UUID().uuidString)
        let decoded = try XCTUnwrap(SecretVault.decode(vault.encoded()))
        XCTAssertEqual(decoded, vault)
        XCTAssertEqual(decoded.value(service: "wg", account: "default"), config)
        XCTAssertEqual(vault.encoded(), decoded.encoded())
    }

    func testForeignDataIsNotAVault() {
        XCTAssertNil(SecretVault.decode(Data("not json".utf8)))
        XCTAssertNil(SecretVault.decode(Data("[1,2]".utf8)))
        XCTAssertEqual(SecretVault.decode(Data("{}".utf8)), SecretVault())
        XCTAssertEqual(SecretVault.decode(Data(#"{"a":{}}"#.utf8)), SecretVault())
    }
}
