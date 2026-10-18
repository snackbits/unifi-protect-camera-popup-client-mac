import AppCore
import Foundation
import ProtectKit

/// Kameras › Ereignisse: runs the rules of each Protect event – independent of popups, mutes and
/// Focus (those only concern popups on this Mac). Same paths as the popup buttons: the webhook via
/// `CameraActionService` (home/away routing of Phase 4, no redirects), the sound via
/// `TalkbackService`. Every run lands in the event log (menu panel).
@MainActor
final class EventRuleService {
    static let shared = EventRuleService()

    private let settings = SettingsStore.shared
    private var debouncer = EventRuleDebouncer()

    private init() {}

    /// Called for every new event (already de-duplicated by event id).
    func handle(_ trigger: ProtectTrigger) {
        let kinds = Set(trigger.kinds.map(\.rawValue))
        let now = Date()
        for mapping in settings.mappings(forProtectCamera: trigger.cameraId) {
            let rules = EventRuleMatcher.matching(
                mapping.eventRules,
                kinds: kinds,
                canPlaySound: TalkbackService.shared.canTalk(mapping),
                soundExists: { SoundStore.shared.settings.announcement(id: $0) != nil }
            )
            for rule in rules where debouncer.shouldRun(entry: mapping.entryId.uuidString, rule: rule.id, at: now) {
                schedule(ruleId: rule.id, entryId: mapping.entryId, delay: rule.delaySeconds)
            }
        }
    }

    private func schedule(ruleId: UUID, entryId: UUID, delay: Int) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
            await run(ruleId: ruleId, entryId: entryId)
        }
    }

    /// Reads the rule again: edits during the delay apply, a removed rule or camera does nothing.
    private func run(ruleId: UUID, entryId: UUID) async {
        guard let mapping = settings.mapping(forEntry: entryId),
              let rule = mapping.eventRules.first(where: { $0.id == ruleId }) else {
            NSLog("Event rule \(ruleId) was removed before it ran")
            return
        }
        let kindLabel = TriggerKind(rawValue: rule.kind)?.label ?? rule.kind
        // Sound and webhook at the same time: the sound starts first, the webhook does not wait for it.
        let sound = startSound(rule, mapping: mapping)
        var failed = sound?.played == false
        if rule.hasWebhook {
            do {
                try await CameraActionService.trigger(Self.request(for: rule))
            } catch {
                failed = true
                NSLog("Event rule webhook failed: \(error.localizedDescription)")
            }
        }
        EventLog.shared.record(
            mapping: mapping,
            kindLabel: EventRuleText.logTitle(
                kindLabel: kindLabel,
                webhook: rule.hasWebhook,
                soundName: sound?.name,
                failed: failed
            ),
            date: Date()
        )
    }

    /// nil = the rule plays nothing here; `played` false = skipped (the camera is busy talking).
    private func startSound(_ rule: EventRule, mapping: WebhookMapping) -> (name: String, played: Bool)? {
        guard let id = rule.soundId, TalkbackService.shared.canTalk(mapping),
              let announcement = SoundStore.shared.settings.announcement(id: id) else { return nil }
        let played = TalkbackService.shared.playAutomatically(announcement, entryId: mapping.entryId)
        if !played {
            TalkbackLog.write("Regel: Ton „\(announcement.name)“ übersprungen – \(mapping.label) sendet gerade")
        }
        return (announcement.name, played)
    }

    /// The rule's webhook as a transient popup button: same request, same routing.
    static func request(for rule: EventRule) -> CameraAction {
        CameraAction(
            title: "Regel",
            url: rule.webhook?.url ?? "",
            method: CameraAction.Method(rawValue: rule.webhook?.method ?? "POST") ?? .post,
            bearerToken: rule.bearerToken
        )
    }
}
