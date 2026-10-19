import AppCore
import AppKit
import Combine

/// Popup of a camera that can talk (Protect camera with speaker).
struct PopupTalkContent {
    let entryId: UUID
}

/// Talk button (Phase 5, two lines): capsule 40 high, padding 0/18, radius 20, `accent`, mic 16 + 6 +
/// state line 12 pt bold („Sprechen“ → „Verbinde …“ → „Loslassen zum Beenden“) over the fixed hint
/// „Gedrückt halten zum Sprechen“ 10 pt, white 80 %. Talks only while the mouse button is held;
/// releasing ends it, also outside the button or the popup. Width = widest text (never jumps).
/// Compact (popup too narrow for the pill): a 40 pt circle with the microphone only, hint as tooltip.
final class TalkButtonView: NSView {
    static let idleTitle = "Sprechen"
    static let connectingTitle = "Verbinde …"
    static let liveTitle = "Loslassen zum Beenden"
    static let hint = "Gedrückt halten zum Sprechen"

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onAccessibilityPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: TalkButtonView.hint)
    private var isHeld = false
    private let lines: NSStackView
    private var fullConstraints: [NSLayoutConstraint] = []
    private var compactConstraints: [NSLayoutConstraint] = []
    /// Width of the two-line form.
    let fullWidth: CGFloat
    /// Mouse-up anywhere (other apps included) while held: the window may not see it.
    private var releaseMonitors: [Any] = []
    /// While held: checks every 250 ms that the mouse button is still down, so a lost mouse-up
    /// (e.g. swallowed by a modal or another app) never leaves the microphone open.
    private var holdPoll: Timer?
    /// Compact state requested by a relayout while held; applied on release, so the button never
    /// loses „Loslassen zum Beenden“ under the user's finger.
    private var requestedCompact = false

    init() {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let hintFont = NSFont.systemFont(ofSize: 10)
        let texts = [Self.idleTitle, Self.connectingTitle, Self.liveTitle].map { ($0, titleFont) } + [(Self.hint, hintFont)]
        let textWidth = texts.map { NSAttributedString(string: $0.0, attributes: [.font: $0.1]).size().width }.max() ?? 0
        fullWidth = 18 + 16 + 6 + textWidth.rounded(.up) + 18
        lines = NSStackView(views: [label, hintLabel])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20

        icon.image = TemplateIcon.mic.nsImage(size: 16)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = titleFont
        label.textColor = .white
        hintLabel.font = hintFont
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 0
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(lines)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            lines.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        fullConstraints = [
            widthAnchor.constraint(equalToConstant: fullWidth),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
        ]
        compactConstraints = [
            widthAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
        ]
        NSLayoutConstraint.activate(fullConstraints)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(Self.hint)
        update(title: Self.idleTitle, busy: false)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isCompact: Bool {
        get { requestedCompact }
        set {
            requestedCompact = newValue
            if !isHeld { applyCompact() }
        }
    }

    private var appliedCompact = false

    private func applyCompact() {
        guard requestedCompact != appliedCompact else { return }
        appliedCompact = requestedCompact
        lines.isHidden = appliedCompact
        NSLayoutConstraint.deactivate(appliedCompact ? fullConstraints : compactConstraints)
        NSLayoutConstraint.activate(appliedCompact ? compactConstraints : fullConstraints)
    }

    /// `busy` while the talkback session is being opened (70 %).
    func update(title: String, busy: Bool) {
        label.stringValue = title
        toolTip = Self.hint
        setAccessibilityLabel(title)
        alphaValue = busy ? 0.7 : 1
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isHeld else { return }
        isHeld = true
        onPress?()
        let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.release()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
        releaseMonitors = [local, global].compactMap { $0 }
        let poll = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.release() }
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        holdPoll = poll
    }

    override func mouseUp(with event: NSEvent) { release() }

    /// The popup closes or the button leaves its window while held: end like a release.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { release() }
    }

    /// Ends a hold (mouse-up, lost mouse-up, popup closed). Idempotent.
    func release() {
        guard isHeld else { return }
        isHeld = false
        holdPoll?.invalidate()
        holdPoll = nil
        releaseMonitors.forEach(NSEvent.removeMonitor)
        releaseMonitors = []
        applyCompact()
        onRelease?()
    }

    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.accent)
    }
}

/// One announcement in the popup's sound menu: name left, tag (10 pt `muted`) right, gap 8,
/// padding 5/8, radius 5; `accent` with white text under the mouse (like the mute menu).
final class SoundMenuRow: NSView {
    var onClick: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(labelWithString: "")
    private let titleColor: ThemeColor
    private var hovering = false {
        didSet { applyColors() }
    }

    init(name: String, tag tagText: String?, color: ThemeColor = Tokens.fg) {
        titleColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        title.stringValue = name
        title.font = .systemFont(ofSize: 12)
        // Long names wrap (max 2 lines) like the template; the tag stays on the first line.
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2
        title.cell?.wraps = true
        title.cell?.truncatesLastVisibleLine = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        var constraints = [
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ]
        if let tagText {
            tagLabel.stringValue = tagText
            tagLabel.font = .systemFont(ofSize: 10)
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            tagLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(tagLabel)
            tagLabel.sizeToFit()
            title.preferredMaxLayoutWidth = 164 - 8 - tagLabel.frame.width
            constraints += [
                tagLabel.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
                tagLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                tagLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            ]
        } else {
            title.preferredMaxLayoutWidth = 164
            constraints.append(title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8))
        }
        NSLayoutConstraint.activate(constraints)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(tagText.map { "\(name), \($0)" } ?? name)
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
        title.textColor = hovering ? .white : titleColor.nsColor
        tagLabel.textColor = hovering ? NSColor.white.withAlphaComponent(0.85) : Tokens.muted.nsColor
    }
}

/// Sound menu above "Ton abspielen": 180 + 2 × 5 wide, radius 9, `menu`, ring 1 `mainBorder`,
/// shadow 0 10 24 rgba(0,0,0,.4); announcements, separator (1, margin 3/4), "MP3 hinzufügen …" `accText`.
final class SoundMenuView: NSView {
    var onPick: ((Announcement) -> Void)?
    var onAdd: (() -> Void)?
    private let stack = NSStackView()

    init() {
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
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Ton abspielen")
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuilt on every opening, so new announcements appear at once.
    func reload(_ announcements: [Announcement]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for announcement in announcements {
            let row = SoundMenuRow(name: announcement.name, tag: announcement.menuTag)
            row.onClick = { [weak self] in self?.onPick?(announcement) }
            add(row)
        }
        if !announcements.isEmpty {
            let separator = SeparatorView()
            stack.addArrangedSubview(separator)
            stack.setCustomSpacing(0, after: separator)
            NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 180)])
        }
        let add = SoundMenuRow(name: "MP3 hinzufügen …", tag: nil, color: Tokens.accText)
        add.onClick = { [weak self] in self?.onAdd?() }
        self.add(add)
    }

    private func add(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: 180).isActive = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.menu)
        layer?.borderColor = cgColor(Tokens.mainBorder)
    }
}

/// 1 pt `mainBorder` line with 3 pt above/below and 4 pt left/right (template `margin: 3px 4px`).
private final class SeparatorView: NSView {
    private let line = NSView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 7),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        line.layer?.backgroundColor = cgColor(Tokens.mainBorder)
    }
}

/// Error line above the pill: capsule `overlay`, padding 4/9, 11 pt semibold white, 6 s. Click-through.
final class PopupNoticeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Tokens.overlay.light.nsColor.cgColor
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
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `persistent`: stays until `hide()` (otherwise gone after 6 s).
    func show(_ text: String, persistent: Bool = false) {
        label.stringValue = text
        toolTip = text
        setAccessibilityLabel(text)
        isHidden = false
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: text])
        hideWork?.cancel()
        guard !persistent else { return }
        let work = DispatchWorkItem { [weak self] in self?.isHidden = true }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        isHidden = true
    }
}

/// "Ton abspielen" + talk button of one popup, wired to `TalkbackService`.
@MainActor
final class PopupTalkControls {
    let soundButton: CircleIconButton
    let talkButton: TalkButtonView
    private let soundMenu = SoundMenuView()
    private let notice = PopupNoticeView()
    private let entryId: UUID
    /// Called when the sound menu opens (the popup closes its mute menu).
    var onMenuOpened: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private var isClosed = false

    init(content talk: PopupTalkContent) {
        entryId = talk.entryId
        soundButton = CircleIconButton(
            icon: .soundPlay,
            iconSize: 16,
            diameter: 34,
            fill: Tokens.pillBtn,
            tint: Tokens.pillFg,
            label: "Ton abspielen"
        )
        talkButton = TalkButtonView()
        soundMenu.isHidden = true

        soundButton.target = self
        soundButton.action = #selector(soundTapped)
        let service = TalkbackService.shared
        let entryId = talk.entryId
        talkButton.onPress = { service.startTalking(entryId: entryId) }
        talkButton.onRelease = { service.stopTalking() }
        talkButton.onAccessibilityPress = { service.toggleTalk(entryId: entryId) }
        soundMenu.onPick = { [weak self] announcement in
            self?.soundMenu.isHidden = true
            service.play(announcement, entryId: entryId)
        }
        soundMenu.onAdd = { [weak self] in
            self?.soundMenu.isHidden = true
            self?.addMP3()
        }

        service.$activity
            .receive(on: RunLoop.main)
            .sink { [weak self] activity in self?.render(activity) }
            .store(in: &cancellables)
        service.$notice
            .dropFirst()
            .compactMap { $0 }
            .filter { $0.entryId == entryId }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in self?.notice.show(notice.text) }
            .store(in: &cancellables)
    }

    /// Menu over the pill (bottom edge on the pill's top edge), 45 pt left of the sound button (template: left 70 in a 470 popup),
    /// at least 10 from the popup edge; notice 8 above the pill, centered.
    func install(in content: NSView, above pill: NSView) {
        content.addSubview(notice)
        content.addSubview(soundMenu)
        let leading = soundMenu.leadingAnchor.constraint(equalTo: soundButton.leadingAnchor, constant: -45)
        // Below the window's own size (500): a hidden menu must never widen the popup.
        leading.priority = NSLayoutConstraint.Priority(490)
        NSLayoutConstraint.activate([
            leading,
            soundMenu.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 10),
            soundMenu.bottomAnchor.constraint(equalTo: pill.topAnchor),
            notice.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            notice.bottomAnchor.constraint(equalTo: pill.topAnchor, constant: -8),
            notice.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -20),
        ])
    }

    /// Two-line talk button while the pill fits into the popup, else the microphone only.
    func fit(popupWidth: CGFloat, circles: Int) {
        talkButton.isCompact = !PopupPillFit.talkButtonFits(popupWidth: popupWidth, circles: circles, talkWidth: talkButton.fullWidth)
    }

    /// true when the click only closed the open menu.
    func closeMenu() -> Bool {
        guard !soundMenu.isHidden else { return false }
        soundMenu.isHidden = true
        return true
    }

    /// Keep the popup open while something is being sent from it.
    var isBusy: Bool { TalkbackService.shared.isActive(entryId: entryId) }

    func popupClosed() {
        isClosed = true
        // Removes the mouse monitors and the hold poll at once (not only when the view leaves its window).
        talkButton.release()
        TalkbackService.shared.popupClosed(entryId: entryId)
        cancellables.removeAll()
    }

    @objc private func soundTapped() {
        // While an announcement plays from this popup, the button stops it.
        if let activity = TalkbackService.shared.activity, activity.entryId == entryId,
           case .announcement = activity.purpose {
            TalkbackService.shared.stopPlayback()
            return
        }
        if soundMenu.isHidden {
            soundMenu.reload(SoundStore.shared.settings.announcements)
        }
        soundMenu.isHidden.toggle()
        if !soundMenu.isHidden { onMenuOpened?() }
    }

    private func addMP3() {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            let added = try SoundStore.shared.addFile(from: url)
            // The modal picker may outlive the popup: then the file is only added.
            guard !isClosed else { return }
            TalkbackService.shared.play(added, entryId: entryId)
        } catch {
            notice.show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func render(_ activity: TalkbackActivity?) {
        let mine = activity?.entryId == entryId ? activity : nil
        switch mine?.purpose {
        case .talk?:
            let live = mine?.phase == .live
            talkButton.update(title: live ? TalkButtonView.liveTitle : TalkButtonView.connectingTitle, busy: !live)
            setSoundActive(false)
        case .announcement?:
            talkButton.update(title: TalkButtonView.idleTitle, busy: false)
            setSoundActive(true)
        case nil:
            talkButton.update(title: TalkButtonView.idleTitle, busy: false)
            setSoundActive(false)
        }
    }

    /// Playing: `accent` fill, white symbol (template has no playing state).
    private func setSoundActive(_ active: Bool) {
        soundButton.isAccented = active
        soundButton.toolTip = active ? "Ansage stoppen" : "Ton abspielen"
    }
}
