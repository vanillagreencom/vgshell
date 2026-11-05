# Notifications developer reference

Read when changing notification ingestion, actions, persistence or sound suppression. The [manifest](manifest.json) owns entry points, settings, sound events, TUIs and layer rules. [Service.qml](Service.qml) owns live notification state and registers IPC handlers.

## Interface and actions

The service's registration block defines the IPC interface; `status` defines its diagnostic reply. Inbox and History are views of that service, not independent stores. The core owns the notification server while the plugin is enabled.

[NotificationLogic.js](NotificationLogic.js) owns lifetime, duplicate, action and presentation decisions. [Notification action ownership](../../../docs/decisions/D051-notification-actions-reveal-the-sender.md) governs sender reveal and window selection. [Slack notifications](slack.md#developer-details) defines message-link matching for the desktop Slack client.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.notifications invoke status ''
```

</details>

## Hints

`NotificationLogic.readHints` owns the accepted string-hint shapes. An avatar changes the media layout; an icon and tone can supply its outcome badge. Open and page hints describe a file or page target, never a command. A malformed hint is refused whole and logged. A click requesting an open target without an accepted target is also refused.

The core supplies the sending plugin identity and page-reference hint for its own notifications. Page references take precedence over a click hint. Failed opens keep the card and explain the refusal.

`NotificationLogic.actionsFor` derives Open log from an accepted file hint for every sender. A sender need not hold an action-waiting notification process to offer it. The declared [open TUI](tui/open.sh) uses the shared editor route; a busy editor or missing file leaves the card available.

Stored roles pass the same judge as live hints. Keep live and restored cards under that one contract.

## State

[Store.qml](Store.qml) owns the state file and image copies. `NotificationLogic` owns its schema, text and image limits, retention and boot handling. An unreadable or refused state file remains untouched while the service works in memory. Clear history permits starting the file again. A failed write retries on a later change.

A restored toast has no live sender actions. Its reveal path still follows the notification action contract. The panel reads a service snapshot and sends choices back through IPC.

## Sound rule

[SoundRule.qml](SoundRule.qml), [sound-rule-install.sh](sound-rule-install.sh) and the [WirePlumber script](wireplumber/vgs-notification-sounds.lua) own rule installation and version reporting. The installed copy survives the shell's temporary plugin snapshot. The script checks supported user-service paths before writing configuration.

The audio services read configuration at their own start. The plugin does not restart them, because that would interrupt live calls. Disabling the plugin removes its installed rule files; exiting the shell leaves them in place.

[AppSounds.qml](AppSounds.qml) owns the hold writer. A hold applies only while its PipeWire client exists. Losing that client lifts the hold; a replacement writer publishes a new hold. `NotificationLogic.holdMatches` and `appSoundStep` own stream selection and release decisions.

## Look

[Appearance.js](Appearance.js) owns the plugin's values under the shared [appearance contract](../../../docs/architecture/design-system.md#appearance). Toasts draw in the passive layer; the summoned panel takes the keyboard. The manifest declares blur for both layers.

After changing [the edge shader](shaders/edgelight.frag), regenerate its compiled asset from this plugin directory.

<details>
<summary>Show command</summary>

```text
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/edgelight.frag.qsb shaders/edgelight.frag
```

</details>
