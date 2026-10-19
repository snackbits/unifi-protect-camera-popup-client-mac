import AppCore
import AppKit
import SwiftUI

// MARK: - Icons

/// Template icons, exported 1:1 from the template's inline SVGs into `Assets.xcassets/Icons`
/// (vector, template rendering: tinted by the surrounding foreground color).
enum TemplateIcon: String, CaseIterable {
    case tabGeneral, tabCameras, tabSound, tabRemote
    case chevronUpDown, chevronRight, chevronDown
    case close, bellSlash, speakerMute, check, play, shieldCheck
    /// Lucide „settings“ (same stroke style as the template icons): popup → camera settings.
    case gear
    case actionDoor, actionBulb, actionHouse, actionBolt
    case fileDownload
    case mic, soundPlay

    func image(size: CGFloat) -> some View {
        Image(rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// AppKit variant for the popup overlays.
    func nsImage(size: CGFloat) -> NSImage? {
        guard let image = NSImage(named: rawValue)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

// MARK: - Containers

/// Rounded group: radius 10 (Allgemein, Ton, Unterwegs) or 9 (Kameras), fill `group`, 1 pt `border`.
struct Card<Content: View>: View {
    var radius: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(Tokens.group.color))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tokens.border.color, lineWidth: 1))
    }
}

/// 1 pt separator between card rows (`border-bottom: 1px solid border`).
struct CardDivider: View {
    var color: ThemeColor = Tokens.border

    var body: some View {
        Rectangle().fill(color.color).frame(height: 1)
    }
}

/// Card row: title fills, trailing controls on the right (gap 10).
struct CardRow<Trailing: View>: View {
    let title: String
    var vertical: CGFloat = 10
    var horizontal: CGFloat = 14
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Card row with switch; optional 11 pt subtitle under the title (gap 2).
struct CardToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var vertical: CGFloat = 10
    var horizontal: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TokenSwitch(isOn: $isOn, label: title)
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Card row with a fixed-width label (Kameras › Erweitert: 110, Unterwegs: 140).
struct FixedLabelRow<Content: View>: View {
    let title: String
    var width: CGFloat = 110
    var vertical: CGFloat = 9
    var horizontal: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: width, alignment: .leading)
            content
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Sheet grid line: 96 pt label column, gap 10.
struct FormLine<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 96, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Section heading: 11 pt semibold, `muted`.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Tokens.muted.color)
    }
}

// MARK: - Buttons

/// Pressed and disabled look shared by the token button styles (template has neither: 70 % / 45 %).
private struct StyledButtonBody<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder var content: Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// Bordered field button ("Ändern …", "Kopieren", "Testen").
struct FieldButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 12
    var vertical: CGFloat = 3
    var horizontal: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(Tokens.fg.color)
                .padding(.vertical, vertical)
                .padding(.horizontal, horizontal)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        }
    }
}

/// Filled accent button ("Sichern", "Übernehmen").
struct AccentButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 13
    var vertical: CGFloat = 5
    var horizontal: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.vertical, vertical)
                .padding(.horizontal, horizontal)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.accent.color))
        }
    }
}

/// Soft accent button filling its width (menu panel "15 Min." / "1 Std.").
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.accText.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tokens.accSoft.color))
        }
    }
}

/// Text link (`<a>` of the template: colored and underlined).
struct LinkButtonStyle: ButtonStyle {
    var color: ThemeColor = Tokens.accText
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(color.color)
                .underline()
        }
    }
}

// MARK: - Controls

/// Switch 32 × 19, radius 10, knob 15 white with 2 pt inset; on `accent`, off `toggleOff`.
struct TokenSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Tokens.accent.color : Tokens.toggleOff.color)
                    .frame(width: 32, height: 19)
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Ein" : "Aus")
        .accessibilityAddTraits(.isButton)
    }
}

/// Segmented control: track `segBg` radius 7 padding 2, 12 pt; segment padding 3/12
/// (or equal widths in a fixed content `width`), active `segOn` radius 5 + shadow, semibold.
struct TokenSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Tokens.fg.color : Tokens.muted.color)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, width == nil ? 12 : 0)
                        .frame(maxWidth: width == nil ? nil : .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOn ? Tokens.segOn.color : Color.clear)
                                .shadow(color: isOn ? Tokens.segShadow.color : .clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(width: width)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Tokens.segBg.color))
    }
}

/// Plain text field in a bordered `field` box (settings: 12 pt 4/7 r5; sheet: 13/12 pt 5/8 r6).
struct TokenTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 12
    var vertical: CGFloat = 4
    var horizontal: CGFloat = 7
    var radius: CGFloat = 5
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(Tokens.fg.color)
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
        .background(RoundedRectangle(cornerRadius: radius).fill(Tokens.field.color))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
    }
}

/// "15 | Minuten ⌃⌄": number input (34 wide, right aligned, tabular) + unit pop-up in one box.
struct DurationField: View {
    @Binding var duration: MuteDuration
    let accessibilityLabel: String
    @State private var text = ""
    @FocusState private var focused: Bool
    @StateObject private var anchor = ViewAnchor()

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 34)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
                .accessibilityLabel(accessibilityLabel)
            Rectangle().fill(Tokens.chipBorder.color).frame(width: 1)
            Button(action: chooseUnit) {
                HStack(spacing: 5) {
                    Text(duration.unit.label)
                    TemplateIcon.chevronUpDown.image(size: 9)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .background(AnchorView(anchor: anchor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityLabel), Einheit")
            .accessibilityValue(duration.unit.label)
        }
        .font(.system(size: 12))
        .foregroundStyle(Tokens.fg.color)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        .onAppear { text = String(duration.value) }
        .onDisappear { commit() }
        .onChange(of: duration) { newValue in
            if !focused { text = String(newValue.value) }
        }
    }

    private func commit() {
        if let value = MuteDuration.parseValue(text) {
            duration = duration.withValue(value)
        }
        text = String(duration.value)
    }

    private func chooseUnit() {
        guard let view = anchor.view else { return }
        let units = MuteDuration.Unit.allCases
        MenuPresenter.popUp(
            titles: units.map(\.label),
            selectedIndex: units.firstIndex(of: duration.unit),
            in: view
        ) { index in
            duration.unit = units[index]
        }
    }
}

/// "▸ Erweitert" / "▾ Erweitert": 12 pt, chevron 10, gap 5; collapsed `muted`, expanded `fg` semibold.
struct DisclosureButton: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 5) {
                (expanded ? TemplateIcon.chevronDown : TemplateIcon.chevronRight).image(size: 10)
                Text(title).font(.system(size: 12, weight: expanded ? .semibold : .regular))
            }
            .foregroundStyle(expanded ? Tokens.fg.color : Tokens.muted.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
    }
}

/// The template's striped stand-in for a camera picture:
/// `repeating-linear-gradient(135deg, #2A2D36 0 band, #30343E band 2·band)`.
struct StripePlaceholder: View {
    var band: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Tokens.stripeA.color))
            // Bands are measured along the 135° gradient line; lines of equal color satisfy x + y = c.
            let step = band * 2.squareRoot()
            var start = step
            while start < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: start, y: 0))
                path.addLine(to: CGPoint(x: start + step, y: 0))
                path.addLine(to: CGPoint(x: start + step - size.height, y: size.height))
                path.addLine(to: CGPoint(x: start - size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Tokens.stripeB.color))
                start += step * 2
            }
        }
        .accessibilityHidden(true)
    }
}

/// Slider of Einstellungen › Ton: track 180 × 4 radius 2 `toggleOff`, fill `accent` up to the value,
/// knob 16 white centered on the fill end, shadow 0 1 3 rgba(0,0,0,.35). 2/3 = template (fill 120, knob x 112).
struct VolumeSlider: View {
    @Binding var value: Double
    let label: String
    private let width: CGFloat = 180

    var body: some View {
        let clamped = min(1, max(0, value))
        let fill = CGFloat(clamped) * width
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tokens.toggleOff.color).frame(width: width, height: 4)
            RoundedRectangle(cornerRadius: 2).fill(Tokens.accent.color).frame(width: fill, height: 4)
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: Color.black.opacity(0.35), radius: 1.5, y: 1)
                .offset(x: min(width - 16, max(0, fill - 8)))
        }
        .frame(width: width, height: 16)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            value = Double(min(1, max(0, drag.location.x / width)))
        })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((clamped * 100).rounded())) Prozent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, clamped + 0.05)
            case .decrement: value = max(0, clamped - 0.05)
            @unknown default: break
            }
        }
    }
}
