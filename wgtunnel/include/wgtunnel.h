// C API of the Go c-archive built from wgtunnel/capi (see capi.go).
// Hand-written so Swift compiles before the archive exists; keep in sync with capi.go.
// Every returned char* is owned by the caller and must be released with WgFree.
#ifndef WGTUNNEL_H
#define WGTUNNEL_H

#ifdef __cplusplus
extern "C" {
#endif

/// {"ok":true,"summary":{...}} or {"ok":false,"error":"..."}.
char *WgParse(const char *config);
/// NULL on success, otherwise an error message.
char *WgStart(const char *config);
/// Closes the tunnel and every forward listener and relayed connection.
void WgStop(void);
/// Local port on 127.0.0.1, or -1 (see WgLastError). Same remote -> same port.
/// remoteHost must be (or resolve to) an address inside the peer's AllowedIPs.
int WgAddForward(int localPort, const char *remoteHost, int remotePort);
/// UDP; remoteHost must be an IP literal inside AllowedIPs. One local sender at
/// a time: others are dropped until it was silent for 3 s or a reset ran.
int WgAddUDPForward(int localPort, const char *remoteHost, int remotePort);
/// Number of relayed TCP connections closed (listeners stay open); also
/// unlocks every UDP forward for the next local sender.
int WgResetConnections(void);
/// NULL on success, otherwise an error message.
char *WgRebind(void);
/// JSON status, {"up":false} when stopped.
char *WgStatus(void);
/// Last error of WgAddForward/WgAddUDPForward, or NULL.
char *WgLastError(void);
void WgFree(char *p);

#ifdef __cplusplus
}
#endif

#endif
