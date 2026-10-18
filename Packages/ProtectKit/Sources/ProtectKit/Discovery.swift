import Darwin
import Foundation

public struct DiscoveredConsole: Equatable, Hashable, Sendable {
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let model: String?

    public init(ip: String, mac: String?, hostname: String?, model: String?) {
        self.ip = ip; self.mac = mac; self.hostname = hostname; self.model = model
    }

    public var displayName: String { model ?? hostname ?? ip }
}

public enum DiscoveryPacket {
    public static let request: [UInt8] = [0x01, 0x00, 0x00, 0x00]

    public static func parse(_ bytes: [UInt8], sourceIP: String) -> DiscoveredConsole? {
        guard bytes.count > 4, bytes[0] == 0x01, bytes[1] == 0x00 else { return nil }
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        guard length > 0, bytes.count >= 4 + length else { return nil }

        var mac: String?
        var hostname: String?
        var shortModel: String?
        var model: String?
        var i = 4
        let end = 4 + length
        while i + 3 <= end {
            let type = bytes[i]
            let len = Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
            let start = i + 3
            guard start + len <= end else { return nil }
            let value = Array(bytes[start..<start + len])
            switch type {
            case 0x01 where len == 6, 0x02 where len == 10:
                mac = value.prefix(6).map { String(format: "%02x", $0) }.joined(separator: ":")
            case 0x0B: hostname = String(decoding: value, as: UTF8.self)
            case 0x0C: shortModel = String(decoding: value, as: UTF8.self)
            case 0x14, 0x15: model = String(decoding: value, as: UTF8.self)
            default: break
            }
            i = start + len
        }
        return DiscoveredConsole(ip: sourceIP, mac: mac, hostname: hostname, model: model ?? shortModel)
    }
}

/// Broadcasts a discovery request and collects answers for `duration` seconds.
public final class ConsoleDiscovery {
    public init() {}

    public func scan(duration: TimeInterval = 3) async -> [DiscoveredConsole] {
        await Task.detached { Self.blockingScan(duration: duration) }.value
    }

    private static func blockingScan(duration: TimeInterval) -> [DiscoveredConsole] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(10001).bigEndian
        dest.sin_addr.s_addr = INADDR_BROADCAST

        let request = DiscoveryPacket.request
        func send() {
            _ = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var found: [String: DiscoveredConsole] = [:]
        let deadline = Date().addingTimeInterval(duration)
        var lastSend = Date.distantPast
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            if Date().timeIntervalSince(lastSend) > 1 { send(); lastSend = Date() }
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLen)
                }
            }
            guard n > 0 else { continue }
            let ip = String(cString: inet_ntoa(from.sin_addr))
            if let console = DiscoveryPacket.parse(Array(buffer[0..<n]), sourceIP: ip) {
                found[ip] = console
            }
        }
        return found.values.sorted { $0.ip < $1.ip }
    }
}
