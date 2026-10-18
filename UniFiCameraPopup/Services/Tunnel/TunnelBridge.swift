import Foundation
import ProtectKit
import WGTunnelC

/// Synchronous wrapper around the Go c-archive (`wgtunnel/capi`). The Go side
/// serializes calls with its own mutex. `start`, `rebind` and `reresolve` resolve DNS and may
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
        guard let remote = cPort(target.port) else { throw invalidPort(target.port) }
        let port = WgAddForward(0, target.host, remote)
        guard port > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(port)
    }

    /// Local UDP port on 127.0.0.1 that leads to `ip:port` through the tunnel (talkback).
    static func addUDPForward(ip: String, port: Int) throws -> Int {
        guard let remote = cPort(port) else { throw invalidPort(port) }
        let local = WgAddUDPForward(0, ip, remote)
        guard local > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(local)
    }

    /// Unlocks the UDP forward on 127.0.0.1:`localPort` for the next local sender:
    /// a new talkback session takes it over at once (else only after 3 s of silence).
    static func releaseUDPForward(localPort: Int) throws {
        guard let local = cPort(localPort) else { throw invalidPort(localPort) }
        guard WgReleaseUDPForward(local) == 0 else {
            throw Failure(message: take(WgLastError()) ?? "Weiterleitung nicht freigegeben")
        }
    }

    /// Closes all relayed TCP connections; the local ports stay valid.
    @discardableResult
    static func resetConnections() -> Int {
        Int(WgResetConnections())
    }

    static func rebind() throws {
        if let message = take(WgRebind()) { throw Failure(message: message) }
    }

    /// Looks up the endpoint host names again and moves the peer only when the IP changed
    /// (same network, peer silent). Resolves DNS – call it off the main thread.
    static func reresolve() -> TunnelReresolveResult {
        TunnelReresolveResult.decode(take(WgReresolve()) ?? "")
    }

    static func status() -> TunnelStatus {
        TunnelStatus.decode(take(WgStatus()) ?? "")
    }

    /// A port for the C API; nil outside 1…65535 (`Int32(_:)` would trap on overflow).
    private static func cPort(_ port: Int) -> Int32? {
        ForwardTarget.validPorts.contains(port) ? Int32(port) : nil
    }

    private static func invalidPort(_ port: Int) -> Failure {
        Failure(message: "Ungültiger Port \(port)")
    }

    private static func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { WgFree(pointer) }
        return String(cString: pointer)
    }
}
