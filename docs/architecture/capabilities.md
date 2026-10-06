# The core lends a capability per instance and releases it with the instance

Read before touching a capability's provider, its lending record, its release, an exclusive capability, or an observation a capability answers.

## The approach

A capability is a core API named in a manifest's `capabilities` and delivered as `shell.<name>`. `shell/Core/PluginLogic.js` owns the name list, `shell/Core/Capabilities.qml` holds one provider per name, made for one instance when the core builds it. Every registration a provider makes returns a disposer, and the instance's build record owns it through one lifetime, `shell/Core/Lifetime.js`, so destroying the instance releases every shortcut, IPC target, subscriber, layer, lock and hold it made. `lock`, `polkit`, `bluetoothAgent` and `panes` are exclusive: the first holder wins, and a second plugin naming one builds once the holder lets go. The session lock, the polkit agent, the notification server and the Bluetooth agent are session-wide objects the core owns and lends ([D012](../decisions/D012-core-owns-lent-objects.md)); the shared `session` capability exposes lock state without lock authority ([D056](../decisions/D056-read-only-session-state.md)). An input observation a capability answers is a read-only snapshot that grants no authority to act ([D090](../decisions/D090-core-input-facts.md)).

## Why

One owner per session-wide object removes the collision class, and one lifetime per instance makes disabling a plugin a complete release that goes on after one disposer throws. The notification server and the polkit agent exist only while a plugin holds them, so a shell without such a plugin claims neither role. Lending `lock` to a reader would grant unlock authority. A snapshot can go stale between the read and the act, so a consumer observes immediately before it sends and refuses a changed target.

## Rules

- Do return a disposer from every registration a provider makes, and keep each resource owner's state, registration and release together. `scripts/test-lifetime.js` pins the lifetime, and `scripts/smoke/rows/capability-release.sh` reads the lending record back after a disable.
- Do land a capability with its name, its provider, a fixture consumer and its smoke rows in one change.
- Never add a dispatcher to the compositor provider; add it to `Dispatch.PLUGIN_DISPATCHERS`. `scripts/test-dispatch.js` pins the list.
- Never let `configure` write a key the manifest's `schema` does not declare, and let it write every entry a pane or service plugin reads. `scripts/test-plugin-logic.js` pins both.
- Do treat `lock`, `polkit`, `bluetoothAgent` and `panes` as exclusive; `PluginLogic.lendRefusal` decides, and at start every surface plugin builds before any service ([D047](../decisions/D047-services-build-after-the-first-bar-frame.md)). `scripts/test-plugin-logic.js` and `scripts/smoke/rows/start-order.sh` pin it.
- Never own a `WlSessionLock` or a polkit agent in a plugin; the core keeps the session locked while the lock plugin is disabled, updated or rebuilt. `scripts/smoke/rows/lock.sh` and `polkit.sh` read it.
- Do lend the Bluetooth agent per counted lease, starting `bluetoothctl` on the first lease and ending it on the last; every line the core writes starts with 17 spaces, and no line that could come from a device in range is accepted as a command or an answer ([D085](../decisions/D085-bluetooth-agent-core-lent-over-bluetoothctl.md)). `scripts/test-bluetooth-agent.js` replays raw transcripts split at every width.
- Never let an observation outlive a failed read; a failure clears the result, and an unrecognised application or an ambiguous overlapping client refuses. `scripts/test-input-facts.js` pins both.
- Never let a notice a plugin offers release with the instance; the user closes it. Do read `requirements.revision` to re-probe setup state after a scan.
- Do lend `idle` as one `IdleMonitor` per watch, since a plugin may not import `Quickshell.Wayland`; `scripts/smoke/rows/capabilities.sh` reads a watch go idle and active again.

## The canonical example

The `session` provider in `shell/Core/SessionLock.qml`: a frozen object with one bindable getter, made per instance, granting nothing. Copy its shape for a shared read-only capability; `shell/Core/BluetoothAgent.qml` for an exclusive one.

## Revisit when

Quickshell releases the notification D-Bus name when its server object is destroyed, a plugin needs a lent object two plugins share at once, or Hyprland exposes atomic target-bound input.

## Not governed

Each capability's members, which is the vgs-plugin skill's `references/api.md`; the passive layer surface, which is [surfaces.md](surfaces.md); the theme runner, which is [theme-capability.md](theme-capability.md).
