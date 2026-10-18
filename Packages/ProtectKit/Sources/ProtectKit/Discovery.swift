import Darwin
import Foundation
import SystemConfiguration

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

/// Finds UniFi OS consoles. Broadcast discovery alone is not enough: consoles such as the
/// UDM Pro SE do not answer it, while Protect devices (cameras, UAP bridges) do. So the
/// broadcast answers plus the default gateway become candidates, and only those that answer
/// the console endpoint `/api/system` are returned.
public final class ConsoleDiscovery {
    public init() {}

    public func scan(duration: TimeInterval = 3) async -> [DiscoveredConsole] {
        let broadcast = await Task.detached { Self.blockingScan(duration: duration) }.value
        var candidates = Dictionary(broadcast.map { ($0.ip, $0) }, uniquingKeysWith: { a, _ in a })
        if let gateway = Self.defaultGateway(), candidates[gateway] == nil {
            candidates[gateway] = DiscoveredConsole(ip: gateway, mac: nil, hostname: nil, model: nil)
        }
        let consoles = await withTaskGroup(of: DiscoveredConsole?.self) { group in
            for candidate in candidates.values {
                group.addTask { await ConsoleProbe.probe(candidate) }
            }
            var result: [DiscoveredConsole] = []
            for await console in group { if let console { result.append(console) } }
            return result
        }
        return consoles.sorted { $0.ip < $1.ip }
    }

    /// IPv4 router of the primary network service, e.g. "192.168.1.1".
    static func defaultGateway() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "UniFiCameraPopup" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return dict["Router"] as? String
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

/// Asks a candidate for `/api/system`, which every UniFi OS console serves without login.
/// No credentials are sent, so the console's self-signed certificate is accepted here;
/// pinning starts when the user picks a console and the API key is sent.
enum ConsoleProbe {
    static func probe(_ candidate: DiscoveredConsole) async -> DiscoveredConsole? {
        guard let url = URL(string: "https://\(candidate.ip)/api/system") else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.httpCookieStorage = nil
        let delegate = AcceptAnyCertificate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data, candidate: candidate)
    }

    static func parse(_ data: Data, candidate: DiscoveredConsole) -> DiscoveredConsole? {
        struct System: Decodable {
            struct Hardware: Decodable { let shortname: String? }
            let name: String?
            let mac: String?
            let hardware: Hardware?
        }
        guard let system = try? JSONDecoder().decode(System.self, from: data),
              let shortname = system.hardware?.shortname, !shortname.isEmpty else { return nil }
        let name = system.name.flatMap { $0.isEmpty ? nil : $0 }
        return DiscoveredConsole(
            ip: candidate.ip,
            mac: candidate.mac ?? system.mac.map(Self.formatMAC),
            hostname: name ?? candidate.hostname,
            model: name.map { "\($0) (\(shortname))" } ?? shortname
        )
    }

    static func formatMAC(_ raw: String) -> String {
        let hex = raw.lowercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return raw.lowercased() }
        return stride(from: 0, to: 12, by: 2).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return String(hex[start..<hex.index(start, offsetBy: 2)])
        }.joined(separator: ":")
    }
}

private final class AcceptAnyCertificate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
