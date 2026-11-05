# Slack notification reference

Read when changing Slack enrichment, message links or cached images. User setup belongs in [Notifications](README.md#slack-photos); the [developer reference](developer.md) owns notification actions and persistence.

## Developer details

[NotificationLogic.js](NotificationLogic.js) owns the Slack entry in `ENRICHERS`. Desktop entries and application names identify desktop Slack; the browser origin identifies browser Slack. Sender names, titles and bodies remain external data.

A desktop Slack notification supplies no message ID. The service reads a bounded tail of Slack's notification log and asks `slackMessageLink` for a unique match in the card's workspace and arrival window. No match, several candidates or an unsupported record opens no message link. Browser notifications follow their browser instead.

The parser's record shape comes from Slack 4.52.171. That version qualifies the supported log format; it does not imply support for every Slack log. Keep uncertainty as no link rather than guessing from message text.

## Images

[WorkspaceIcons.qml](WorkspaceIcons.qml) and [slack-cache.js](slack-cache.js) read Slack's local workspace assets without credentials. [SlackPhotos.qml](SlackPhotos.qml) owns the photo and emoji helper run. [slack-photos.js](slack-photos.js) and [slack-emoji.js](slack-emoji.js) own cache records, refresh limits and conversion.

Emoji lookup is scoped to the workspace. Unknown emoji stay text. Image conversion uses the first frame. New assets come from the helper's refresh, not from starting a fetch for each notification.

The [secrets contract](../../../docs/architecture/secrets.md) governs credential use. The helper modules own cache limits and stored data. The [manifest](manifest.json) declares the Slack settings and secret accounts.
