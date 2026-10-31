# Notifications developer reference

## Interface

The service registers `vgs.notifications:inbox`. The manifest binds it to `SUPER+N` in the generated Hyprland layer. The IPC entry is `vgshell ipc call vgs.notifications invoke <name> <arg>`.

| IPC name | Argument | Reply |
|---|---|---|
| `inbox` | none | toggles the Inbox; `ok` |
| `history` | none | opens the History; `ok` |
| `close` | none | closes the panel; `ok` |
| `mark-read` | none | as the button: every notification is read, every toast on screen leaves into the History, and the panel closes; `ok` |
| `clear-history` | none | as the button; `ok` |
| `silence` | `on`, `off`, `toggle`, or empty to read it | Do Not Disturb: `on` or `off`, or `refused: silence=<arg> want=on\|off\|toggle` |
| `sound` | `on`, `off`, `toggle`, or empty to read it | `on` or `off`, or `refused: sound=<arg> want=on\|off\|toggle` |
| `dismiss-all` | none | dismisses every toast; `ok`, or `none` with none on screen |
| `dismiss-latest`, `invoke-latest` | none | dismisses, or clicks, the newest toast; `ok` or `none` |
| `status` | none | one JSON line: `sound`, `silence`, `appSounds` (`held`, `hold`, `writer`; null with Sound on and Do Not Disturb off), `soundRule` (`phase`, `version`), `panel`, `store` (`state`, `problem`), `onScreen`, `history`, `held`, `readBefore`, `duplicates` (`keptDesktop`, `keptBrowser`) |

The core's notification server takes the `org.freedesktop.Notifications` name while the plugin is enabled. Another notification daemon must not run beside it.

A normal toast stays for at least the Notification duration. A low priority toast uses the shorter of that time and five seconds. A sender can ask for more time, up to thirty seconds. A critical toast stays until closed. A toast that shows plays the `notification` sound event only with Sound on and Do Not Disturb off. Toasts do not expire while the panel is open. When a notification leaves the screen, for any reason, History keeps it, transient or not, and new toasts can replace older ones on a full screen. A newer copy of the same notification, the same id sent again or one message sent by both a sender's app and its web client, takes the older copy's place and leaves the one entry.

The file-opening TUI records its refusal keys in `$XDG_STATE_HOME/vgshell/notifications/diagnostics.log`, or `~/.local/state/vgshell/notifications/diagnostics.log` when the variable is unset. The terminal shows a plain explanation. A run outside the presenter keeps its keyed refusal on stderr. Editor output passes through unchanged.

Slack notifications from a browser open that browser. A notification from the Slack app carries no link to its message, so View also opens the link VGS builds from Slack's own log: [Slack notifications](slack.md#developer-details).

Notification action ownership and window selection: [D051](../../../docs/decisions/D051-notification-actions-reveal-the-sender.md).

## Hints

Any sender may add six freedesktop string hints, `x-vgs-avatar`, `x-vgs-icon`, `x-vgs-tone`, `x-vgs-open`, `x-vgs-click` and `x-vgs-page`, and the plugin draws a card's icon in the tone, draws a page reference's words as a link, and opens the page or the file on a click without naming the sender. `x-vgs-avatar` names a Lucide avatar; when present, `x-vgs-icon` and `x-vgs-tone` become the smaller filled outcome badge in the shared media slot. Without an avatar, the card keeps its ordinary icon size. `readHints` in `NotificationLogic.js` is the one judge and holds each hint's accepted shape; a hint of another shape is refused whole and the service logs its name, and `x-vgs-click: open` without an accepted `x-vgs-open` is refused, so a card never promises a file it cannot open. A click on a card whose `x-vgs-page` names a file leaves the card when the core's file route reports the file opened (`shell.surfaces.openPage`'s `done`); a file that is gone ("This file is no longer on this computer.") or an editor busy with another file keeps the card and a transient notification says why, as a refused `x-vgs-open` does (`openOutcome`). `scripts/test-notifications-logic.js` pins each shape with a control. `vgs.automations` is one sender ([D052](../../../docs/decisions/D052-automations-engine.md)); `AutomationsLogic.js` is the sender to copy.

The core adds `x-vgs-plugin`, the sending plugin's id, to every `shell.notify.send` message; a critical message carrying it shows under Do Not Disturb, as a critical bare `notify-send` does, and no card keeps it. It adds `x-vgs-page` when the message holds a page reference, `[words](page:<plugin id>/<tab>)`: the message carries the words and the hint the reference. A click on that card, Enter in the inbox and invoke-latest open the page through `shell.surfaces.openPage`, ahead of `x-vgs-click`; a refused open keeps the card.

A hint carries a path, never a command, so no notification can make the shell run a program. The roles are stored with the card, and the store's judge refuses a stored value the hint judge would, so a history card or one restored after a restart draws and clicks as it did live. A click opens the file through the plugin's `open` floating TUI with the path as its argument, under one key whatever the file, so a second open while one is live is `busy`; a refused run keeps the card and sends a transient notification through `shell.notify.send` that says why. The TUI uses the shared editor helper: `$VISUAL`, then `$EDITOR`, then a choice of installed editors. It refuses an unreadable file; `scripts/test-notifications-open.sh` pins each.

A card whose `x-vgs-open` the judge accepts shows Open log beside Dismiss: on a toast while the pointer is on it, and on its Inbox row, where the arrow keys and Enter reach it. Open log opens the file as a click on an `open` card does, through the same `open` TUI, whatever the card's `x-vgs-click`. `actionsFor` in `NotificationLogic.js` draws it from the hint for every sender. A sender offers no freedesktop action for it: `notify-send --action` waits until the user picks one, and holds the sender running that long.

## State

`$XDG_STATE_HOME/vgshell/notifications/` (`~/.local/state/vgshell/notifications/`) holds `state.json`, with Sound, Do Not Disturb, the last Mark all read, the toasts on screen and the history, and `images/`, the copies of the images the stored notifications show, since a sender deletes its own files once a notification closes. The history keeps a notification for 24 hours and at most the newest 100, the oldest going first, and a panel lists every one it shows. A sender's text is stored up to 512 characters of summary and 4096 of body, and an image up to 5 MiB, so the directory holds at most 120 entries and two images each. The file names the kernel's boot id, `/proc/sys/kernel/random/boot_id`; the first start after a reboot empties the toasts and the history and keeps Sound, Do Not Disturb and Mark all read. A boot id the service cannot read is logged as `notifications: boot id unreadable: file=<path> error=<error>` and keeps the service in memory, writing nothing, until it starts again.

The file is written whole at the end of each change. After a restart or a rebuild, the toasts that were on screen show again with a whole lifetime and no live actions, and the ones whose time ran out meanwhile go into the history. The notifications the service held are dismissed on the server as it goes, so their inbox rows raise the sender's window alone ([D051](../../../docs/decisions/D051-notification-actions-reveal-the-sender.md)). The panel reads rows from the service through the plugin IPC and sends choices back to the service, so the service remains the only owner of notification state. A file the service cannot read or does not accept is logged as `notifications: state refused: file=<path> reason=<defect>` or `state unreadable`, shown in the panel's subtitle and in `status`, and left as it is: the service keeps working in memory until Clear history starts the file over. A write that fails is logged and tried again with the next change.

## Sound rule

`wireplumber/vgs-notification-sounds.lua` is a WirePlumber script that holds an app's notification sound silent before WirePlumber links its stream. When the service starts, `SoundRule.qml` copies the script to `$XDG_DATA_HOME/wireplumber/scripts/vgs-notification-sounds.lua` and writes `$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d/90-vgs-notification-sounds.conf`, which names that copy by its absolute path and the version VGS computes from its text. The copy is needed because the shell loads the plugin from a snapshot under the session's runtime directory, which WirePlumber does not find after the next login. If WirePlumber does not run the rule at that version, VGS restarts `wireplumber.service` once for it and records the version in `sound-rule-restarted` beside `state.json`. One `pw-dump -m` watcher follows the rule’s metadata entry changes and object removals in order as WirePlumber restarts or loads it late. `status` reports the install's `phase`: `running` while the rule reports this version, `absent` while it is not loaded after its one restart, or `failed` with one `notifications: sound rule:` line in the log. Disabling the plugin removes the fragment, the copy and the marker. A shell that exits keeps them.

The script owns the PipeWire metadata `vgs-notification-sounds`. It publishes `version` on subject 0. While Sound is off or Do Not Disturb is on, `AppSounds.qml` writes `hold` there: the pid of its one `pw-cli` writer, the apps of the notifications the service keeps or arms and the roles `notification` and `event`. The rule acts only while that writer's PipeWire client exists, lifts what it holds when the writer goes, and refuses a hold that names a writer already gone. The shell starts the writer again after an exit it did not cause and writes the hold again for each new writer and each time the rule comes back. A mute that waits on a rule that is not loaded logs `notifications: app sounds: rule=not-loaded` at warn. `holdMatches` and `appSoundStep` in `NotificationLogic.js` decide which streams it held and which the shell frees. A sound VGS plays itself is freed as its own.

## Look

`Appearance.js` holds every value the notifications draw with, as the `appearance` table [docs/decisions/D023](../../../docs/decisions/D023-plugin-owned-appearance.md) sets out, except the glass. The theme reaches it through `scheme.mode`, `palette.accent` and `motion.scale` alone, so a theme's palette, fonts and metrics leave the glass as it is. The accent lights the edge reflection of a critical toast. With the motion scale at 0 nothing animates and the edge lights stand still.

The edge light, the bead and the pills are the plugin's own files, drawn from its own table: a plugin imports no other plugin's files. The header's icons are the `IconButton` of `qs.Ui`, which draws the shared tokens. The glass is VGlass, `GlassSurface` of `qs.Ui` over `Theme.glass`, handed the table's own fill, rounding and the `tight` shadow ([D023](../../../docs/decisions/D023-plugin-owned-appearance.md)). The edge light and the toast's spin to a circle show only while a card draws glass; without it a toast fades in and out as a plain panel.

Where a card's text and media sit: the `media` slot of `Appearance.js`, one size for every card.

The toast stack draws on the core's passive layer, `vgs:layer` ([vgs-plugin `references/api.md` § Passive layer content](../../../.agents/skills/vgs-plugin/references/api.md#passive-layer-content)). The Inbox and History draw as the plugin's summoned `panel`, because the passive layer does not take keyboard focus; summoned with `SUPER+N`, the panel is the summon host's `vgs:panel` layer, and a press beside it over a window or the desktop closes it; a press on the bar leaves it open. A window that takes the keyboard closes it; a layer that takes it, such as a capture's selector or another panel, leaves it open beneath, so a capture shows it. Hyprland blurs what is behind the glass only when a layer rule asks it to. The manifest declares one rule for each layer, and the Hyprland layer writes them as:

```lua
hl.layer_rule({ name = "vgs.notifications:layer", match = { namespace = "^vgs:layer$" }, blur = true, ignore_alpha = 0.6 })
hl.layer_rule({ name = "vgs.notifications:panel", match = { namespace = "^vgs:panel$" }, blur = true, ignore_alpha = 0.6 })
```

`hyprland.lua` runs the layer from the line `vgshell hypr wire` keeps first in it, so your own settings after that line win. To change the rule, call `hl.layer_rule` with its name and new values after the line; `enabled = false` turns it off.

## Shader

The edge reflection is `shaders/edgelight.frag`, compiled to `shaders/edgelight.frag.qsb` beside it. After an edit to the source, Qt 6's `qsb` compiles it again from this directory:

```text
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/edgelight.frag.qsb shaders/edgelight.frag
```
