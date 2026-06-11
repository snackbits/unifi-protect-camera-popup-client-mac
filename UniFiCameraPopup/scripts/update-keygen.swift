#!/usr/bin/env swift
import CryptoKit
import Foundation

// Generates a fresh Ed25519 key pair for signing app updates.
//
// - The 32-byte raw PRIVATE key (base64) is written to `update_private_key.txt`
//   next to this script. Keep it secret and never commit it (.gitignore'd).
// - The 32-byte raw PUBLIC key (base64) is baked into `AppConfig.swift`
//   (`updatePublicKey`) so the running app can verify downloaded updates.
//
// Run once:  swift app/UniFiCameraPopup/scripts/update-keygen.swift

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let scriptsDir = scriptURL.deletingLastPathComponent()
let appDir = scriptsDir.deletingLastPathComponent()
let privateKeyFile = scriptsDir.appendingPathComponent("update_private_key.txt")
let appConfigFile = appDir.appendingPathComponent("AppConfig.swift")

if FileManager.default.fileExists(atPath: privateKeyFile.path) {
    FileHandle.standardError.write(Data("""
    Refusing to overwrite an existing private key:
      \(privateKeyFile.path)
    Delete it manually if you really want to rotate the update signing key
    (this invalidates auto-update for all already-installed builds).

    """.utf8))
    exit(1)
}

let privateKey = Curve25519.Signing.PrivateKey()
let privateBase64 = privateKey.rawRepresentation.base64EncodedString()
let publicBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

try Data((privateBase64 + "\n").utf8).write(to: privateKeyFile)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyFile.path)

// Patch AppConfig.swift: replace the value of `updatePublicKey`.
var config = try String(contentsOf: appConfigFile, encoding: .utf8)
let pattern = #"(static let updatePublicKey = ")[^"]*(")"#
guard let regex = try? NSRegularExpression(pattern: pattern) else {
    FileHandle.standardError.write(Data("Failed to build regex\n".utf8))
    exit(1)
}
let range = NSRange(config.startIndex..<config.endIndex, in: config)
let replaced = regex.stringByReplacingMatches(
    in: config,
    range: range,
    withTemplate: "$1\(publicBase64)$2"
)
if replaced == config {
    FileHandle.standardError.write(Data("""
    Could not find `updatePublicKey` in AppConfig.swift to patch.
    Set it manually to:
      \(publicBase64)

    """.utf8))
} else {
    config = replaced
    try Data(config.utf8).write(to: appConfigFile)
}

print("Generated Ed25519 update signing key pair.")
print("  Private key (secret): \(privateKeyFile.path)")
print("  Public key  (baked into AppConfig.swift): \(publicBase64)")
