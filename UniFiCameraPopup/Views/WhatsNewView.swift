import SwiftUI

/// Shown once after an update: which versions were skipped and what is new.
struct WhatsNewView: View {
    let info: WhatsNewInfo
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Was ist neu")
                    .font(.largeTitle.bold())
                Text("Die App wurde von Version \(info.fromVersion) auf Version \(info.toVersion) aktualisiert.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(info.entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Version \(entry.version)")
                                .font(.headline)
                            ForEach(entry.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 24)
                                    Text(item)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Alles klar", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
