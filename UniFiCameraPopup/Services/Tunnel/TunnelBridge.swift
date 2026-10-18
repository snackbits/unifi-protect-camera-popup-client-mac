import Foundation
import ProtectKit
import WGTunnelC

/// Synchronous wrapper around the Go c-archive (`wgtunnel/capi`). The Go side
/// serializes calls with its own mutex. `start` and `rebind` resolve DNS and may
/// block for seconds – call them off the main thread.
enum TunnelBridge {
    struct Failure: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ config: String) -> TunnelParseResult {
        TunnelParseResult.decode(take(WgParse(config)) ?? "")
    }

    static func start(_ config: String) throws {
        if let message = take(WgStart(config)) { throw Failure(message: message) }
    }

    static func stop() {
        WgStop()
    }

    /// Local TCP port on 127.0.0.1 that leads to `target` through the tunnel.
    static func addForward(_ target: ForwardTarget) throws -> Int {
        let port = WgAddForward(0, target.host, Int32(target.port))
        guard port > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(port)
    }

    /// Local UDP port on 127.0.0.1 that leads to `ip:port` through the tunnel (talkback).
    static func addUDPForward(ip: String, port: Int) throws -> Int {
        let local = WgAddUDPForward(0, ip, Int32(port))
        guard local > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(local)
    }

    /// Closes all relayed TCP connections; the local ports stay valid.
    @discardableResult
    static func resetConnections() -> Int {
        Int(WgResetConnections())
    }

    static func rebind() throws {
        if let message = take(WgRebind()) { throw Failure(message: message) }
    }

    static func status() -> TunnelStatus {
        TunnelStatus.decode(take(WgStatus()) ?? "")
    }

    private static func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { WgFree(pointer) }
        return String(cString: pointer)
    }
}
