# Final-fix report

## Dropped by the OLD build (base 288af11 PersistedSettings/WebhookMapping/CameraAction)
- Settings: protectHost, protectCertificateFingerprint, protectConsoleName, muteSchedule, muteShort, muteLong, appearance (muteUntil is still written by both).
- Mapping: protectCameraId, triggers, webhookTriggerEnabled, chimeOnOpen.
- Action: icon, confirmBeforeRun.
All are now persisted additionally under UserDefaults key `settingsExtensionsV2`.

## Changes
1. AppCore `SettingsExtensions` (+ tests: round trip, missing, garbled, per-field tolerance, prune of stale ids). SettingsStore: overlay at load (extension wins; legacy muteUntil still merged via MuteSchedule.migrated), write both blobs in persist(); main blob and legacy keys unchanged. Stale mapping/action ids are ignored at overlay (ids not present are never looked up) and dropped on the next persist.
2. DurationField: commit() in .onDisappear.
3. AppDelegate: NSWorkspace.didWakeNotification and NSSystemClockDidChange -> pruneMutes + scheduleMuteExpiryRefresh.
4. Export: muteSchedule and muteUntil nil; import no longer restores mutes (only prunes current ones).

## Verification
- AppCore swift test: 37 tests, 0 failures. ProtectKit: 52 tests, 0 failures.
- Debug build: BUILD SUCCEEDED.
- `--render-snapshots`: exit 0, 20 files; `defaults export` before/after identical (cmp).
- Not unit-tested: SettingsStore overlay itself (app target has no test target); logic is thin, merge-relevant parts tested in AppCore.
