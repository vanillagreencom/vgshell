# Notifications developer reference

## Interface

The service registers `vgs.notifications:inbox`. The manifest binds it to `SUPER+N` in the generated Hyprland layer. The IPC entry is `vgshell ipc call vgs.notifications invoke <name> <arg>`.

| IPC name | Argument | Reply |
|---|---|---|
| `inbox` | none | toggles the Inbox; `ok` |
| `history` | none | opens the History; `ok` |
| `close` | none | closes the panel; `ok` |
| `mark-read` | none | as the button; `ok` |
| `clear-history` | none | as the button; `ok` |
| `silence` | `on`, `off`, `toggle`, or empty to read it | `on` or `off`, or `refused: silence=<arg> want=on\|off\|toggle` |
| `dismiss-all` | none | dismisses every toast; `ok`, or `none` with none on screen |
| `dismiss-latest`, `invoke-latest` | none | dismisses, or clicks, the newest toast; `ok` or `none` |
| `status` | none | one JSON line: `silence`, `panel`, `store` (`state`, `problem`), `onScreen`, `history`, `held`, `readBefore`, `duplicates` (`keptDesktop`, `keptBrowser`) |

The core's notification server takes the `org.freedesktop.Notifications` name while the plugin is enabled. Another notification daemon must not run beside it.

A normal toast stays for at least the Notification duration. A low priority toast uses the shorter of that time and five seconds. A sender can ask for more time, up to thirty seconds. A critical toast stays until closed. Toasts do not expire while the panel is open. When a notification leaves the screen, History keeps it, and new toasts can replace older ones on a full screen.

The file-opening TUI records its refusal keys in `$XDG_STATE_HOME/vgshell/notifications/diagnostics.log`, or `~/.local/state/vgshell/notifications/diagnostics.log` when the variable is unset. The terminal shows a plain explanation. A run outside the presenter keeps its keyed refusal on stderr. Editor and `xdg-open` output passes through unchanged.

Slack notifications from a browser open that browser. Slack does not provide a link to the message in its notifications, so an old Slack notification can bring Slack into view without opening the message.

Notification action ownership and window selection: [D051](../../../docs/decisions/D051-notification-actions-reveal-the-sender.md).

## Hints

Any sender may add four freedesktop string hints, `x-vgs-icon`, `x-vgs-tone`, `x-vgs-open` and `x-vgs-click`, and the plugin draws a card's icon in the tone and opens the file on a click without naming the sender. `readHints` in `NotificationLogic.js` is the one judge and holds each hint's accepted shape; a hint of another shape is refused whole and the service logs its name, and `x-vgs-click: open` without an accepted `x-vgs-open` is refused, so a card never promises a file it cannot open. `scripts/test-notifications-logic.js` pins each shape with a control. `vgs.automations` is one sender ([D052](../../../docs/decisions/D052-automations-engine.md)); `AutomationsLogic.js` is the sender to copy.

A hint carries a path, never a command, so no notification can make the shell run a program. The roles are stored with the card, and the store's judge refuses a stored value the hint judge would, so a history card or one restored after a restart draws and clicks as it did live. A click opens the file through the plugin's `open` floating TUI with the path as its argument, under one key whatever the file, so a second open while one is live is `busy`; a refused run keeps the card and shows a core toast. The TUI splits `$EDITOR` on white space, falls back to `xdg-open`, and refuses an unreadable file; `scripts/test-notifications-open.sh` pins each.

## State

`$XDG_STATE_HOME/vgshell/notifications/` (`~/.local/state/vgshell/notifications/`) holds `state.json`, with Silence, the last Mark read, the toasts on screen and the history, and `images/`, the copies of the images the stored notifications show, since a sender deletes its own files once a notification closes. The history keeps the newest 100 notifications and a panel shows at most 40 of them. A sender's text is stored up to 512 characters of summary and 4096 of body, and an image up to 5 MiB, so the directory holds at most 120 entries and two images each.

The file is written whole at the end of each change. After a restart or a rebuild, the toasts that were on screen show again with a whole lifetime and no live actions, and the ones whose time ran out meanwhile go into the history. The notifications the service held are dismissed on the server as it goes, so their inbox rows raise the sender's window alone ([D051](../../../docs/decisions/D051-notification-actions-reveal-the-sender.md)). The panel reads rows from the service through the plugin IPC and sends choices back to the service, so the service remains the only owner of notification state. A file the service cannot read or does not accept is logged as `notifications: state refused: file=<path> reason=<defect>` or `state unreadable`, shown in the panel's subtitle and in `status`, and left as it is: the service keeps working in memory until Clear history starts the file over. A write that fails is logged and tried again with the next change.

## Look

`Appearance.js` holds every value the notifications draw with, as the `appearance` table [docs/decisions/D023](../../../docs/decisions/D023-plugin-owned-appearance.md) sets out. The theme reaches it through `scheme.mode`, `palette.accent` and `motion.scale` alone, so a theme's palette, fonts and metrics leave the glass as it is. The accent lights the edge reflection of a critical toast and the Silence switch. With the motion scale at 0 nothing animates and the edge lights stand still.

The glass, the edge light, the pills and the switch are the plugin's own files, drawn from its own table: a plugin imports no other plugin's files.

Where a card's text and media sit, and how the media slot's tier is chosen: `mediaTier` in `NotificationLogic.js` and the media rows of `Appearance.js`.

The toast stack draws on the core's passive layer, `vgs:layer` ([overview.md § Hosts and surfaces](../../../docs/architecture/overview.md#hosts-and-surfaces)). The Inbox and History draw as the plugin's summoned `panel`, because the passive layer does not take keyboard focus; summoned with `SUPER+N`, the panel is the summon host's `vgs:panel` layer, and a press beside it over a window or the desktop closes it; a press on the bar leaves it open. Hyprland blurs what is behind the glass only when a layer rule asks it to. The manifest declares one rule for each layer, and the Hyprland layer writes them as:

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
