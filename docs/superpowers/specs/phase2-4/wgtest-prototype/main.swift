import Foundation

// Accepts the fake console's self-signed cert. A real app must pin the console certificate.
final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { completionHandler(.useCredential, URLCredential(trust: t)) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

func takeString(_ p: UnsafeMutablePointer<CChar>?) -> String? {
    guard let p else { return nil }
    defer { WgFree(p) }
    return String(cString: p)
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app.conf"
guard let cfg = try? String(contentsOfFile: path, encoding: .utf8) else { print("config fehlt: \(path)"); exit(2) }

// Error path first: invalid config must come back as a message, not a crash.
if let e = takeString(cfg.replacingOccurrences(of: "[Peer]", with: "[Peers]").withCString({ WgStart(UnsafeMutablePointer(mutating: $0)) })) {
    print("erwarteter Fehler: \(e)")
}
if let e = takeString(cfg.withCString({ WgStart(UnsafeMutablePointer(mutating: $0)) })) { print("WgStart: \(e)"); exit(1) }
let port = "192.168.1.1".withCString { WgAddForward(0, UnsafeMutablePointer(mutating: $0), 443) }
guard port > 0 else { print("forward: \(takeString(WgLastError()) ?? "?")"); exit(1) }
print("Forward 127.0.0.1:\(port) -> 192.168.1.1:443")

var req = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/proxy/protect/integration/v1/cameras")!)
req.setValue("test", forHTTPHeaderField: "X-API-KEY")
let session = URLSession(configuration: .ephemeral, delegate: TrustAll(), delegateQueue: nil)
let sem = DispatchSemaphore(value: 0)
let t0 = Date()
session.dataTask(with: req) { data, resp, err in
    if let err { print("Fehler: \(err)") }
    else {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let cams = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [[String: Any]] ?? []
        print(String(format: "HTTP %d in %.1f ms, %d Kameras:", code, Date().timeIntervalSince(t0) * 1000, cams.count))
        for c in cams {
            let spk = (c["featureFlags"] as? [String: Any])?["hasSpeaker"] as? Bool ?? false
            print("  \(c["name"] ?? "?") id=\(c["id"] ?? "?") hasSpeaker=\(spk)")
        }
    }
    sem.signal()
}.resume()
sem.wait()
print("Status: \(takeString(WgStatus()) ?? "nil")")
WgStop()
print("nach Stop: \(takeString(WgStatus()) ?? "nil")")
