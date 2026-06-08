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
                    Text("Breite")
                    Slider(value: $settings.defaultWidth, in: 240...1280, step: 10)
                    Text("\(Int(settings.defaultWidth)) px")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("Höhe")
                    Slider(value: $settings.defaultHeight, in: 135...720, step: 10)
                    Text("\(Int(settings.defaultHeight)) px")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
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
                        TextField("Bezeichnung", text: $mapping.label)
                        TextField("Webhook ID", text: $mapping.webhookId)
                        TextField("RTSPS URL", text: $mapping.rtspsURL)

                        Picker("Position (optional)", selection: Binding<PopupPosition?>(
                            get: { mapping.positionOverride },
                            set: { mapping.positionOverride = $0 }
                        )) {
                            Text("Standard").tag(nil as PopupPosition?)
                            ForEach(PopupPosition.allCases) { position in
                                Text(position.label).tag(Optional(position))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    settings.removeMappings(at: offsets)
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
}
