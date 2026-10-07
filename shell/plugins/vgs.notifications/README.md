# Notifications

Notifications shows application notifications at the top of each screen and keeps them in a panel to read later. Silence keeps new notifications in History without showing them on screen.

![Three notifications on screen](../../../docs/images/plugins/vgs.notifications-toasts.webp)

![The inbox with three notifications](../../../docs/images/plugins/vgs.notifications-inbox.webp)

Screenshots come from `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2. VGS uses a summoned panel to give the list keyboard focus.

## Features

- Super+N opens and closes the panel. Escape closes it too.
- Unread shows the notifications received since the last Mark read. History shows the saved ones.
- Mark read marks the current notifications as read and closes the panel. Clear history removes the saved ones.
- Silence keeps new notifications in History without showing them on screen.
- A normal notification stays on screen for at least the Notification duration. A critical one stays until closed. Pointing at a notification pauses its timer.
- Pointing at a notification shows its actions. A click runs its main action, such as View in Slack, and brings the application's window into view. An action removes the notification from the screen and from the panel. Dismiss, or a right click, removes it from the screen.
- Enter opens the selected notification in the panel. Delete dismisses it.
- A file notification opens the file in your editor, or in the default app for the file.
- Slack notifications show sender initials and workspace icons without setup. Custom emoji appear when Slack has saved their images. See [Slack notifications](slack.md).
- The panel says so when the saved history cannot be read. Clear history starts a new one.
- A message from any VGS plugin is a system notification, which this plugin draws. VGS has no toast of its own.
- With this plugin off, VGS drops plugin messages and writes one line to its log. Only before VGS first shows a notification after it starts can another notification app show them.

## Settings

| Setting | What it changes |
| --- | --- |
| Notification duration | The minimum time a normal notification stays on screen. |
| Slack photos | Whether sender photos load from connected Slack workspaces. |
| Slack custom emoji | Whether custom emoji show in Slack notifications. |

The key is under Keys on the plugin's Settings page. The Requirements section lists the tools that open notification files and prepare Slack icons and emoji, with Install all missing.

## Slack photos

Turn on Slack photos in Settings to add sender photos, workspace icons and custom emoji. Each workspace needs its own Slack app user token.

Select Set up Slack photos in Settings. VGS copies the ready app details and opens Slack Apps. Select Create New App, then From a manifest. Select your workspace and paste the copied text into the JSON field. Review the permissions, then select Create. Under OAuth & Permissions, install the app to the workspace. Copy the User OAuth Token.

Sign in to the workspace in the Slack desktop app. Return to Settings and select Connect beside the workspace. Paste the token into the masked field. VGS stores it in your keyring. Disconnect removes it. The photos load after each connection change. If your workspace requires app approval, ask its administrator to approve the app.

Show details in the setup window displays the app text. The app requests only the permissions needed for photos, workspace icons and custom emoji. It does not read messages or channels.

With Slack photos off, VGS checks whether tokens are present but reads no token and calls no Slack API. Notifications keep sender initials, workspace icons and emoji that Slack has saved.

Developer details: [Developer reference](developer.md).
