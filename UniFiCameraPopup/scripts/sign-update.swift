#!/usr/bin/env swift
import CryptoKit
import Foundation

// Signs an update archive with the Ed25519 private key and prints the
// base64-encoded signature (over the raw bytes of the archive) to stdout.
//
// Usage: swift sign-update.swift <path-to-archive.zip> [path-to-private-key.txt]
//
// The signature is verified inside the app via CryptoKit using the matching
// public key baked into AppConfig.swift.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: sign-update.swift <archive> [private-key-file]\n".utf8))
    exit(1)
}

let archivePath = args[1]
let scriptURL = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath()
let defaultKeyFile = scriptURL.deletingLastPathComponent().appendingPathComponent("update_private_key.txt")
let keyFile = args.count >= 3 ? URL(fileURLWithPath: args[2]) : defaultKeyFile

guard let keyText = try? String(contentsOf: keyFile, encoding: .utf8) else {
    FileHandle.standardError.write(Data("Cannot read private key: \(keyFile.path)\nRun update-keygen.swift first.\n".utf8))
    exit(1)
}

guard let keyData = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("Invalid private key contents in \(keyFile.path)\n".utf8))
    exit(1)
}

guard let archiveData = FileManager.default.contents(atPath: archivePath) else {
    FileHandle.standardError.write(Data("Cannot read archive: \(archivePath)\n".utf8))
    exit(1)
}

guard let signature = try? privateKey.signature(for: archiveData) else {
    FileHandle.standardError.write(Data("Signing failed\n".utf8))
    exit(1)
}

print(signature.base64EncodedString())
