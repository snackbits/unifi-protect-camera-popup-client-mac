import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var webSocketClient: WebSocketClient

    var body: some View {
        Form {
            Section("Server") {
                TextField("WebSocket URL", text: $settings.serverURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("App Token", text: $settings.appToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Label(webSocketClient.status.menuLabel, systemImage: webSocketClient.status.symbolName)
                    Spacer()
                    Button("Neu verbinden") {
                        webSocketClient.reconnect()
                    }
                }
            }

            Section("Popup") {
                Picker("Position", selection: $settings.defaultPosition) {
                    ForEach(PopupPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }

                Picker("Bildschirm", selection: $settings.screenTarget) {
                    ForEach(ScreenTarget.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }

                HStack {
                    Text("Randabstand")
                    Slider(value: $settings.edgeMargin, in: 0...120, step: 1)
                    Text("\(Int(settings.edgeMargin)) px")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("Auto-Schließen")
                    Slider(value: $settings.autoCloseTimeout, in: 0...300, step: 5)
                    Text(settings.autoCloseTimeout > 0 ? "\(Int(settings.autoCloseTimeout)) s" : "Aus")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }

                Picker("Mehrfach-Alarme", selection: $settings.multiAlarmBehavior) {
                    ForEach(MultiAlarmBehavior.allCases) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
            }

            Section("Kameras") {
                ForEach($settings.mappings) { $mapping in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Spacer()
                            Button("Entfernen", role: .destructive) {
                                settings.removeMapping(id: mapping.id)
                            }
                        }

                        TextField("z. B. Eingang", text: $mapping.label)
                            .textFieldStyle(.roundedBorder)
                        TextField("z. B. front-door", text: $mapping.webhookId)
                            .textFieldStyle(.roundedBorder)
                        TextField("RTSP URL", text: $mapping.rtspsURL, prompt: Text("rtsp://user:pass@host:7447/…"))
                            .textFieldStyle(.roundedBorder)

                        if let warning = streamURLWarning(for: mapping.rtspsURL) {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Picker("Position (optional)", selection: Binding<PopupPosition?>(
                            get: { mapping.positionOverride },
                            set: { mapping.positionOverride = $0 }
                        )) {
                            Text("Standard").tag(nil as PopupPosition?)
                            ForEach(PopupPosition.allCases) { position in
                                Text(position.label).tag(Optional(position))
                            }
                        }

                        TextField("Breite (px)", text: dimensionBinding($mapping.width), prompt: Text("480"))
                            .textFieldStyle(.roundedBorder)
                        TextField("Höhe (px)", text: dimensionBinding($mapping.height), prompt: Text("270"))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Kamera hinzufügen") {
                        settings.addMapping()
                    }
                    Spacer()
                }
            }

            Section("System") {
                Toggle("Beim Login starten", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func streamURLWarning(for url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().contains("rtsps://") {
            return "RTSPS wird nicht unterstützt. Bitte rtsp:// verwenden."
        }
        if trimmed.contains(":7441") {
            return "Port 7441 wird nicht unterstützt. Bitte Port 7447 verwenden."
        }
        return nil
    }

    private func dimensionBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: { String(Int(value.wrappedValue)) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty, let parsed = Double(digits) else { return }
                value.wrappedValue = parsed
            }
        )
    }
}
