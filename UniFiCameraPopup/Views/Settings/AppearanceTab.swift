import AppCore
import SwiftUI

/// Einstellungen › Erscheinungsbild (docs/design/popup-miniatur.md, Reiter „Erscheinungsbild“;
/// Mock: docs/design/mockups/einstellungen-erscheinungsbild.html, Vorschlag A).
struct AppearanceTab: View {
    @EnvironmentObject private var settings: SettingsStore
    /// Shared start of the two illustrations, so they run in step from the first frame.
    @State private var animationStart = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                layoutSection
                appearanceSection
                popupSection
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 40)
        }
    }

    // MARK: Popup-Layout

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Popup-Layout")
            Card {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(PopupLayoutMode.allCases, id: \.self) { mode in
                        PopupLayoutOption(mode: mode, selection: $settings.popupLayoutMode, start: animationStart,
                                          mirrored: settings.defaultPosition == .left)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: Darstellung

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Darstellung")
            Card {
                CardRow(title: "Farbschema") {
                    TokenSegmented(
                        selection: $settings.appearance,
                        options: AppearanceMode.allCases.map { (value: $0, title: $0.label) }
                    )
                }
            }
        }
    }

    // MARK: Popup

    private var popupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Popup")
            Card {
                CardRow(
                    title: "Popup-Position",
                    subtitle: "Bildschirmseite für Miniaturen und volle Popups. Der Stapel beginnt oben."
                ) {
                    PopUpField(
                        selection: $settings.defaultPosition,
                        options: PopupPosition.allCases.map { (value: $0, title: $0.label) }
                    )
                }
                CardDivider()
                CardRow(title: "Bildschirm") {
                    PopUpField(
                        selection: $settings.screenTarget,
                        options: ScreenTarget.allCases.map { (value: $0, title: $0.label) }
                    )
                }
                CardDivider()
                sliderRow("Randabstand", value: $settings.edgeMargin, range: 0...120, step: 1,
                          text: "\(Int(settings.edgeMargin)) px")
                CardDivider()
                sliderRow("Automatisch schließen", value: $settings.autoCloseTimeout, range: 0...300, step: 5,
                          text: settings.autoCloseTimeout > 0 ? "\(Int(settings.autoCloseTimeout)) s" : "Aus")
                CardDivider()
                CardToggleRow(
                    title: "Alle aktiven Kameras zeigen",
                    subtitle: "Jede auslösende Kamera bekommt ein eigenes Popup, untereinander gestapelt. Ohne diese Option ersetzt eine neue Kamera das aktuelle Popup.",
                    isOn: $settings.showAllActiveCameras
                )
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .tint(Tokens.accent.color)
                .accessibilityLabel(title)
            Text(text)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

/// One layout choice: illustration (16:10, radius 8) with ring, below it radio, name and description.
/// The whole tile is one button. Selected: ring 2.5 `accent`, otherwise 1 `border`.
private struct PopupLayoutOption: View {
    let mode: PopupLayoutMode
    @Binding var selection: PopupLayoutMode
    let start: Date
    /// Popup-Position „Links“: the illustration shows the popups on the left edge.
    let mirrored: Bool

    private var isOn: Bool { selection == mode }

    private var fixedProgress: Double? {
        #if DEBUG
        SnapshotRenderer.layoutPreviewProgress
        #else
        nil
        #endif
    }

    var body: some View {
        let ring: CGFloat = isOn ? 2.5 : 1
        Button { selection = mode } label: {
            VStack(alignment: .leading, spacing: 8) {
                PopupLayoutPreview(mode: mode, mirrored: mirrored, start: start, fixedProgress: fixedProgress)
                    // box-shadow 0 0 0 <ring>: drawn outside the graphic.
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 + ring)
                            .strokeBorder(isOn ? Tokens.accent.color : Tokens.border.color, lineWidth: ring)
                            .padding(-ring)
                    )
                HStack(alignment: .top, spacing: 8) {
                    radio.padding(.top, 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode.label).fontWeight(.semibold)
                        Text(mode.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.muted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Popup-Layout \(mode.label)")
        .accessibilityHint(mode.summary)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// 15 pt radio: off 1.5 `chipBorder`, on 4.5 `accent`.
    private var radio: some View {
        Circle()
            .strokeBorder(isOn ? Tokens.accent.color : Tokens.chipBorder.color, lineWidth: isOn ? 4.5 : 1.5)
            .frame(width: 15, height: 15)
    }
}

private extension PopupLayoutMode {
    /// Description under the name (docs/design/popup-miniatur.md).
    var summary: String {
        switch self {
        case .miniature: return "Kleine Vorschau am Bildschirmrand, wird groß, wenn die Maus darauf bleibt."
        case .full: return "Popups öffnen sofort in ihrer vollen Größe."
        }
    }
}
