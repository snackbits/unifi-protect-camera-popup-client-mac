import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private static let signature: OSType = 0x5543_504B // "UCPK"
    private static let sequenceTimeout: TimeInterval = 2

    private struct SequenceBinding {
        let step2KeyCode: UInt16
        let entryId: UUID
    }

    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var immediateActions: [UInt32: UUID] = [:]
    private var sequenceActions: [UInt32: CameraHotkey.HotkeyStep] = [:]
    private var sequenceBindings: [CameraHotkey.HotkeyStep: [SequenceBinding]] = [:]
    private var handlerRef: EventHandlerRef?
    private var onHotkey: ((UUID) -> Void)?
    private var nextHotkeyID: UInt32 = 1

    private var pendingSequenceBindings: [SequenceBinding] = []
    private var sequenceMonitors: [Any] = []
    private var persistentMonitors: [Any] = []
    private var sequenceTimer: Timer?

    private init() {}

    func start(onHotkey: @escaping (UUID) -> Void) {
        self.onHotkey = onHotkey
        installHandlerIfNeeded()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSequenceMonitoring()
            }
        }
    }

    func stop() {
        cancelPendingSequence()
        removePersistentMonitors()
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onHotkey = nil
    }

    func sync(mappings: [WebhookMapping]) {
        cancelPendingSequence()
        removePersistentMonitors()
        unregisterAll()

        var usedHotkeys = Set<CameraHotkey>()
        var groupedSequenceBindings: [CameraHotkey.HotkeyStep: [SequenceBinding]] = [:]

        for mapping in mappings {
            guard let hotkey = mapping.hotkey?.normalized() else { continue }
            guard usedHotkeys.insert(hotkey).inserted else {
                NSLog("Duplicate hotkey \(hotkey.displayString) for camera \(mapping.label); skipping.")
                continue
            }

            if hotkey.isSequence, hotkey.steps.count >= 2 {
                let prefix = hotkey.steps[0]
                let binding = SequenceBinding(step2KeyCode: hotkey.steps[1].keyCode, entryId: mapping.entryId)
                groupedSequenceBindings[prefix, default: []].append(binding)
            } else if let step = hotkey.steps.first {
                registerImmediate(step: step, entryId: mapping.entryId)
            }
        }

        sequenceBindings = groupedSequenceBindings

        if AccessibilityHelper.isTrusted {
            installPersistentSequenceMonitors()
        } else {
            for (prefix, _) in groupedSequenceBindings {
                registerSequencePrefix(prefix)
            }
        }
    }

    private func refreshSequenceMonitoring() {
        guard !sequenceBindings.isEmpty else { return }

        let usesPersistent = !persistentMonitors.isEmpty
        let shouldUsePersistent = AccessibilityHelper.isTrusted

        if usesPersistent != shouldUsePersistent {
            sync(mappings: SettingsStore.shared.mappings)
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotkeyID = EventHotKeyID()
                let error = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard error == noErr else { return error }

                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handleCarbonHotkey(id: hotkeyID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        if status != noErr {
            NSLog("Failed to install hotkey handler: \(status)")
        }
    }

    private func handleCarbonHotkey(id: UInt32) {
        Task { @MainActor in
            if let entryId = immediateActions[id] {
                fireHotkey(entryId: entryId)
                return
            }

            guard let prefix = sequenceActions[id],
                  let bindings = sequenceBindings[prefix],
                  !bindings.isEmpty else {
                return
            }

            beginPendingSequence(bindings: bindings)
        }
    }

    private func installPersistentSequenceMonitors() {
        guard persistentMonitors.isEmpty, !sequenceBindings.isEmpty else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.handlePersistentKeyDown(event)
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            persistentMonitors.append(global)
        } else {
            NSLog("Persistent global hotkey monitor unavailable; grant Accessibility access.")
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            persistentMonitors.append(local)
        }
    }

    private func removePersistentMonitors() {
        for monitor in persistentMonitors {
            NSEvent.removeMonitor(monitor)
        }
        persistentMonitors = []
    }

    private func handlePersistentKeyDown(_ event: NSEvent) {
        guard event.type == .keyDown else { return }

        if !pendingSequenceBindings.isEmpty {
            handleSequenceSecondKey(event)
            return
        }

        let step = CameraHotkey.step(from: event)
        guard let bindings = sequenceBindings[step], !bindings.isEmpty else { return }
        beginPendingSequence(bindings: bindings)
    }

    private func beginPendingSequence(bindings: [SequenceBinding]) {
        cancelPendingSequence()
        pendingSequenceBindings = bindings

        if persistentMonitors.isEmpty {
            armTemporarySequenceMonitors()
        }

        sequenceTimer = Timer(timeInterval: Self.sequenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cancelPendingSequence()
            }
        }
        RunLoop.main.add(sequenceTimer!, forMode: .common)
    }

    private func armTemporarySequenceMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.handleSequenceSecondKey(event)
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            sequenceMonitors.append(global)
        } else {
            NSLog("Sequence second key monitor unavailable; grant Accessibility access.")
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            sequenceMonitors.append(local)
        }
    }

    private func handleSequenceSecondKey(_ event: NSEvent) {
        guard !pendingSequenceBindings.isEmpty else { return }

        if event.keyCode == 53 {
            cancelPendingSequence()
            return
        }

        let keyCode = UInt16(event.keyCode)
        if let match = pendingSequenceBindings.first(where: { $0.step2KeyCode == keyCode }) {
            cancelPendingSequence()
            fireHotkey(entryId: match.entryId)
        }
    }

    private func fireHotkey(entryId: UUID) {
        onHotkey?(entryId)
    }

    private func cancelPendingSequence() {
        pendingSequenceBindings = []
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        for monitor in sequenceMonitors {
            NSEvent.removeMonitor(monitor)
        }
        sequenceMonitors = []
    }

    private func registerImmediate(step: CameraHotkey.HotkeyStep, entryId: UUID) {
        let hotkeyID = nextHotkeyID
        nextHotkeyID += 1

        guard let ref = registerCarbonHotKey(step: step, hotkeyID: hotkeyID) else { return }
        hotkeyRefs[hotkeyID] = ref
        immediateActions[hotkeyID] = entryId
    }

    private func registerSequencePrefix(_ prefix: CameraHotkey.HotkeyStep) {
        let hotkeyID = nextHotkeyID
        nextHotkeyID += 1

        guard let ref = registerCarbonHotKey(step: prefix, hotkeyID: hotkeyID) else { return }
        hotkeyRefs[hotkeyID] = ref
        sequenceActions[hotkeyID] = prefix
    }

    private func registerCarbonHotKey(step: CameraHotkey.HotkeyStep, hotkeyID: UInt32) -> EventHotKeyRef? {
        var carbonID = EventHotKeyID(signature: Self.signature, id: hotkeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(step.keyCode),
            step.carbonModifiers,
            carbonID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            NSLog("Failed to register hotkey step: \(status)")
            return nil
        }
        return ref
    }

    private func unregisterAll() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        immediateActions.removeAll()
        sequenceActions.removeAll()
        sequenceBindings.removeAll()
    }
}
