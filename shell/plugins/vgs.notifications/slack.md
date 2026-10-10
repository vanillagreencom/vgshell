# Slack notifications

Slack notifications show sender initials, workspace icons and custom emoji. See [Notifications](README.md) for the panel and its controls.

## Senders and workspaces

A direct message shows its sender. A group message shows several senders. More people appear as a count beside the faces. If the notification includes a picture, it can replace the first sender's initials.

A workspace icon appears beside the title when Slack has saved it. Otherwise, the notification keeps its original title. Slack notifications from a browser use the same display. If VGS cannot identify the workspace, it keeps the original title and sender initials.

## Messages

A click on a Slack notification, or View, opens its message in the Slack app, in the workspace it came from. If VGS cannot tell which message a notification belongs to, it only brings Slack into view. Slack notifications from a browser open that browser.

## Custom emoji

A custom emoji appears as an image when Slack has saved it for that workspace. An unknown emoji stays as text. Emoji from another workspace stay as text.

Open Notifications in Plugins to change Slack custom emoji. Switch it off to show emoji names as text. If an image tool is missing, select Install all missing under Requirements.

New images appear after VGS reads Slack's saved images again. A notification does not start this work itself. Animated emoji show their first frame.

Set up sender photos from Notifications in Settings. See [Slack photos](README.md#slack-photos).

## Developer details

`NotificationLogic.js` owns the Slack rule in `ENRICHERS`. It matches Slack by desktop entry or application name. Browser messages match `app.slack.com` at the start of the body. External names, titles and message bodies remain sender data.

Slack's notification carries no message id, and Slack 4.52.171 can lose the click that View delivers. So a choice that opens a Slack card also reads the last 1 MiB of Slack's log, `$XDG_CONFIG_HOME/Slack/logs/default/browser.log`, where Slack writes one record for each notification with its team, channel and message ids. `slackMessageLink` in `NotificationLogic.js` builds the `slack://` link from the one record of the card's workspace that Slack wrote at most 500 ms before the card arrived, and `xdg-open` hands the link to Slack. No such record, or more than one, opens no link. The record format is Slack's own, read from Slack 4.52.171; a record of another form opens no link. The read uses no credentials, and VGS logs no id.

Workspace icons come from Slack's local cache. This uses no credentials. The emoji helper uses ImageMagick and stores images under `$XDG_CACHE_HOME/vgshell/notifications/slack-photos/<team id>/`. It stores no messages or tokens. Cache rules, refresh times and limits: [secrets.md](../../../docs/architecture/secrets.md).
