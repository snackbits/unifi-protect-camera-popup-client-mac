// End-to-end check of the C API as the app uses it: start the tunnel against the
// fake home (cmd/home), reach the "console" through a local forward with URLSession,
// reset and rebind, stop. Run via wgtunnel/scripts/smoke.sh.
import Foundation
import WGTunnelC

func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
    guard let p else { return nil }
    defer { WgFree(p) }
    return String(cString: p)
}

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { exit(1) }
}

/// The fake home uses a throwaway self-signed certificate; the app pins instead.
final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { completionHandler(.useCredential, URLCredential(trust: t)) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

let path = CommandLine.arguments[1]
let config = try! String(contentsOfFile: path, encoding: .utf8)

check(take(WgParse("kaputt"))?.contains("\"ok\":false") == true, "WgParse lehnt Unsinn ab")
check(take(WgParse(config))?.contains("\"ok\":true") == true, "WgParse akzeptiert die Home-Konfiguration")
check(take(WgStart(config)) == nil, "WgStart")
let port = WgAddForward(0, "192.168.1.1", 443)
check(port > 0, "WgAddForward -> 127.0.0.1:\(port)")
check(WgAddForward(0, "192.168.1.1", 443) == port, "gleiches Ziel, gleicher Port")

var request = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/proxy/protect/integration/v1/cameras")!)
request.setValue("test", forHTTPHeaderField: "X-API-KEY")
let session = URLSession(configuration: .ephemeral, delegate: TrustAll(), delegateQueue: nil)
let done = DispatchSemaphore(value: 0)
var cameras = -1
session.dataTask(with: request) { data, response, _ in
    if (response as? HTTPURLResponse)?.statusCode == 200,
       let list = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [[String: Any]] {
        cameras = list.count
    }
    done.signal()
}.resume()
_ = done.wait(timeout: .now() + 15)
check(cameras == 2, "HTTPS über den Tunnel: \(cameras) Kameras")

let status = take(WgStatus()) ?? ""
check(status.contains("\"up\":true") && !status.contains("\"lastHandshakeUnix\":0"), "Handshake im Status")
check(WgResetConnections() >= 0, "WgResetConnections")
check(take(WgRebind()) == nil, "WgRebind")
WgStop()
check(take(WgStatus()) == "{\"up\":false}", "WgStop")
print("SMOKE OK")
