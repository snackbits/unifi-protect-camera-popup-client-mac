import Foundation

/// Build-time configuration baked into the app.
///
/// These values are compiled into the binary and are not exposed to or
/// editable by the end user. Adjust them here before distributing a build.
enum AppConfig {
    /// WebSocket endpoint of the relay server (TLS via nginx).
    static let serverURL = "wss://unifi-protect-camera-popup-server.snackbits.dev/ws"

    /// Bearer token the app uses to authenticate the WebSocket connection.
    static let appToken = "fc4hx4g267g34gr3i4gtcjgx76gr347irc3i4tgi7gtc94710z43x1tt67cgf7jrhfxznngcsfjuzegbfa"

    /// Build identifier, rewritten by `scripts/build-release.sh` on every release.
    /// Must match the server's `versionId`; otherwise the server rejects the
    /// connection and the app shows an "outdated version" warning.
    static let buildVersionId = "c6f54545-255c-4c04-a3ae-d0cf59661f4d"

    /// Base URL UniFi Protect posts webhooks to. The full path is
    /// `<webhookBaseURL>/<installationId>/<webhook-slug>`.
    static let webhookBaseURL = "http://159.69.76.60:3847/webhook"

    /// Placeholder used when displaying the webhook URL template.
    static let webhookSlugPlaceholder = "<WEBHOOK-SLUG>"

    static func webhookURL(installationId: String, slug: String = AppConfig.webhookSlugPlaceholder) -> String {
        let safeSlug = slug.isEmpty ? webhookSlugPlaceholder : slug
        return "\(webhookBaseURL)/\(installationId)/\(safeSlug)"
    }
}
