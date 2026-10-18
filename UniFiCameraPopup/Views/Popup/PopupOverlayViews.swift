import AppCore
import AppKit

/// What the popup chrome shows (template B). nil in crop selection mode.
struct PopupOverlayContent {
    /// „Klingel · Haustür · 10:41“; nil = „Name und Zeit einblenden“ is off (no chip).
    let chipText: String?
    let cameraName: String
    let muteOptions: [MuteDuration]
    let onMute: (MuteDuration) -> Void
    /// Phase 3: "Ton abspielen" and "Leertaste halten"; nil = camera without speaker.
    var talk: PopupTalkContent? = nil
}

extension NSView {
    /// Resolves a token for this view's appearance; layers keep plain CGColors.
    func cgColor(_ token: ThemeColor) -> CGColor {
        var result = token.light.nsColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = token.nsColor.cgColor
        }
        return result
    }
}

/// "Klingel · Haustür · 10:41": capsule `overlay`, padding 4/9, 11 pt semibold, white. Click-through.
final class OverlayChipView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Tokens.overlay.light.nsColor.cgColor

        label.stringValue = text
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    /// Clicks fall through to the video (click closes, drag pans).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Round icon button: close 24/11, mute 24/13, pill buttons 34/16.
final class CircleIconButton: FirstMouseButton {
    private let fill: ThemeColor
    private let tint: ThemeColor
    private let label: String

    init(icon: TemplateIcon, iconSize: CGFloat, diameter: CGFloat, fill: ThemeColor, tint: ThemeColor, label: String) {
        self.fill = fill
        self.tint = tint
        self.label = label
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        bezelStyle = .regularSquare
        isBordered = false
        title = ""
        image = icon.nsImage(size: iconSize)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        toolTip = label
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// While the webhook runs: half transparent, no second click.
    func showRunning() {
        isEnabled = false
        alphaValue = 0.5
    }

    /// 1.5 s green (ok) or orange (error, message in the tooltip), then back to normal.
    func showResult(error: String?) {
        alphaValue = 1
        contentTintColor = error == nil ? .systemGreen : .systemOrange
        if let error { toolTip = "\(label): \(error)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.contentTintColor = self.tint.nsColor
            self.toolTip = self.label
            self.isEnabled = true
        }
    }

    /// Highlighted state (`accent` fill, white symbol); survives appearance changes.
    var isAccented = false {
        didSet { applyColors() }
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(isAccented ? Tokens.accent : fill)
        contentTintColor = isAccented ? .white : tint.nsColor
    }
}

/// Text with template padding (menu header 4/8, menu item 5/8).
final class PaddedLabel: NSView {
    let label = NSTextField(labelWithString: "")

    init(text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: ThemeColor, vertical: CGFloat = 4, horizontal: CGFloat = 8) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color.nsColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One mute option; `accent` with white text while the mouse is over it.
final class MuteMenuRow: NSView {
    var onClick: (() -> Void)?
    private let content: PaddedLabel
    private var hovering = false {
        didSet { applyColors() }
    }

    init(title: String) {
        content = PaddedLabel(text: title, size: 12, color: Tokens.fg, vertical: 5, horizontal: 8)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = hovering ? cgColor(Tokens.accent) : NSColor.clear.cgColor
        content.label.textColor = hovering ? .white : Tokens.fg.nsColor
    }
}

/// Mute dropdown: 190 + 2 × 5 wide, radius 9, `menu`, ring `mainBorder`, shadow 0 10 24 rgba(0,0,0,.4).
final class PopupMuteMenuView: NSView {
    var onPick: ((MuteDuration) -> Void)?

    init(cameraName: String, options: [MuteDuration]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let header = PaddedLabel(text: "\(cameraName) stummschalten", size: 11, weight: .semibold, color: Tokens.muted)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalToConstant: 190).isActive = true
        for option in options {
            let row = MuteMenuRow(title: "für \(option.longLabel)")
            row.onClick = { [weak self] in self?.onPick?(option) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("\(cameraName) stummschalten")
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.menu)
        layer?.borderColor = cgColor(Tokens.mainBorder)
    }
}

/// Bottom pill: padding 6, gap 8, `pill`, ring `pillRing`, shadow 0 6 18 rgba(0,0,0,.3).
final class ActionPillView: NSView {
    var onAction: ((CameraAction, CircleIconButton) -> Void)?
    private var buttons: [(button: CircleIconButton, action: CameraAction)] = []

    /// `leadingViews` (Ton abspielen, Leertaste halten) come before the user's buttons.
    init(actions: [CameraAction], leadingViews: [NSView] = []) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for view in leadingViews {
            stack.addArrangedSubview(view)
        }
        for action in actions.prefix(WebhookMapping.maxActions) {
            let button = CircleIconButton(
                icon: action.icon.templateIcon,
                iconSize: 16,
                diameter: 34,
                fill: Tokens.pillBtn,
                tint: Tokens.pillFg,
                label: action.trimmedTitle
            )
            button.target = self
            button.action = #selector(tapped(_:))
            stack.addArrangedSubview(button)
            buttons.append((button, action))
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    @objc private func tapped(_ sender: NSButton) {
        guard let entry = buttons.first(where: { $0.button === sender }) else { return }
        onAction?(entry.action, entry.button)
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.pill)
        layer?.borderColor = cgColor(Tokens.pillRing)
    }
}
