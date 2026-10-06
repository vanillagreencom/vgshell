# Four hints any sender may add to a notification

Read before touching the VGS notification hints, a card's hinted icon or click, or the notifications' `open` TUI.

## The approach

Any sender may add four freedesktop string hints, `x-vgs-icon`, `x-vgs-tone`, `x-vgs-open` and `x-vgs-click`, and `vgs.notifications` draws and opens from them without naming the sender. `NotificationLogic.readHints` in `shell/plugins/vgs.notifications/NotificationLogic.js` is the one judge; a hint of another shape is refused whole, and a card never promises a file it cannot open. The hints are stored with the card, so a history card or one restored after a restart draws and clicks as it did live. `vgs.automations` is one sender ([D052](../decisions/D052-automations-engine.md)); any script is another:

```bash
notify-send --app-name=Backup --urgency=critical \
  --hint=string:x-vgs-icon:circle-x --hint=string:x-vgs-tone:danger \
  --hint=string:x-vgs-open:/home/me/backup.log --hint=string:x-vgs-click:open \
  -- "Backup failed" "Exit code 3"
```

## Why

A hint carries a path, never a command, so no notification can make the shell run a program. Data stored with the notification keeps a restored card honest. The open runs in a floating TUI with the path as argv, one key whatever the file, so a second open while one is live is `busy`.

## Rules

- Do send `x-vgs-icon` as a Lucide name, `x-vgs-tone` as `success`, `warning`, `danger` or `info`, `x-vgs-open` as an absolute path of at most 256 characters, and `x-vgs-click` as `open` or `none`; the judge refuses every other shape. `scripts/test-notifications-logic.js` pins each with a control.
- Never send `x-vgs-click: open` without an accepted absolute `x-vgs-open`. `scripts/test-notifications-logic.js` pins it.
- Do open the file through the plugin's `open` TUI with the path as argv; a refused run keeps the card and shows a core toast. `scripts/smoke/rows/notifications.sh` reads the argv from the stand-in terminal.
- Do split `$EDITOR` on white space and fall back to `xdg-open`; refuse an unreadable file. `scripts/test-notifications-open.sh` pins each.
- Do store the four roles in the state file; the judge refuses a stored value the hint judge would. `scripts/test-notifications-logic.js` pins it.

## The canonical example

The `notify-send` line above, and `shell/plugins/vgs.automations/AutomationsLogic.js` for a sender in code. Copy either.

## Revisit when

A core notification capability carries clicks, or a sender needs a hint that is not one of the four.

## Not governed

What a click on an unhinted card does, which is [D051](../decisions/D051-notification-actions-reveal-the-sender.md); the card's layout, which is the plugin's own.
