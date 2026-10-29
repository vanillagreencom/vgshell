# Google Drive developer reference

## A sync

- One systemd user service, `vgs-google-drive.service`, runs every sync: the hourly timer, Sync now in the popover and `start` on the command line all ask for that service, so a sync never runs twice at once. The timer runs hourly while the user is logged in, and once at the next login after a missed hour.
- Adding a folder pair sets up hourly sync automatically when both units are absent. An install failure keeps the pair and leaves no newly written unit; status reports `units` `absent`, and Add a folder pair explains the failure. The next add or Set up again retries setup. Existing units are not reinstalled by an add. [`bin/google-drive::pairAddVerb`](bin/google-drive) owns the state lock, install order and output contract.
- Every invocation but `install` rewrites stale units, units an earlier runner wrote, to name itself. Units that stay stale, because the user manager refused the rewrite, read `units` `stale`, and Set up again (`tui/setup.sh`) runs `install`.
- A sync copies each folder pair two ways, and only files that are newer: Drive to this computer, then this computer to Drive.
- The runner never deletes, moves or mirrors a file on either side.
- A local file that a download replaces is kept under the pair's records, unless it is the copy the runner made at the last sync. A file that an upload replaces stays in Drive as an earlier revision, under Drive's own retention.
- A Google-native document downloads as an export. A local file at an export's name is never uploaded.
- The runner removes kept copies and review records after 30 days.
- A sync removes a review record whose file is on neither Drive nor this computer, unless the record holds a kept copy of the file.

## Conflicts

| Record | Meaning | Result | Needs |
| --- | --- | --- | --- |
| `both-changed` | The file changed on this computer and on Drive since the last sync, or a new pair holds a different file on each side. | The newer file is on both sides. An older local file is kept under the pair's records. An older Drive file is an earlier revision in Drive. | you |
| `removed-locally` | The file was removed on this computer. | The file returns from Drive. | nothing |
| `removed-on-drive` | The file was removed on Drive. | The file returns to Drive. | nothing |
| `renamed` | Drive's object id shows that the file has a new name. | Both names exist: the old name returns to Drive. | nothing |
| `unreadable-on-drive` | The download of the file failed, such as for a shortcut whose target is gone. The record holds rclone's reason; the popover gives it in plain words. | The file is not copied and keeps its last baseline. The rest of the pair is synced. | nothing for a dangling shortcut, else you |
| `duplicate-identical` | Drive holds two or more files with this name in one folder, each with an md5, all with the same md5 and size. | One of them is copied. | nothing |
| `duplicate-different` | Drive holds two or more files with this name in one folder that are not all the same, Google-native documents included, which have no md5. | One of them is copied. | you when `mine`, else nothing |

The unreadable and duplicate records stand only while the last download met the file: a sync where the file copies removes its record, and the 30-day removal does not apply to them.

A duplicate record holds `mine`, true when the signed-in account, the token's `user` attribute, owns one of the copies, and, when `mine` is false, `owner`, the first copy's owner Drive names. A copy with no owner, as on a shared drive, and a token that names no account never count as the user's. Only a sync whose download meets a doubled name reads that folder's copy metadata, read-only. [`bin/google-drive::duplicateRecords`](bin/google-drive) owns the listing contract.

In the status record each of `conflicts` carries `needs`, `you` or `nothing`, from the table, and `needsYou` counts the `you` rows. The `conflicts` attention reason and its key take only the `you` rows, so a row that needs no action never notifies.

Each row also carries `key`, 16 hex digits of a hash of its whole record: the pair, the kind, the path, `since`, the kept copy, the rename target, rclone's reason, `mine`, `owner` and, for a doubled name, `version`, a hash of each Drive copy's md5, size and modification time from the folder listing the runner reads. A change to any of these, or a record that goes and comes back with a new `since`, makes a new key.

The plugin's judge, `GoogleDriveLogic.parseStatus`, refuses a record whose `needsYou` is not that count, a row with no `needs` or `key`, a `dismissed` that is not a list of keys, `mine` on a row that is no doubled name, and `owner` other than on a doubled name that is not `mine`. The published `cloud` value carries `needsYou`, and each of its `pairs` its own `needsYou`. It leaves out each dismissed row, then lists the rows that need the user first before it caps the list, so the cap cuts the rows that need no action first; `conflictCount` counts the rows it did not leave out. Every count a surface shows is a `needsYou`: the bar badge, the headline, the tooltip, the Details sync lines and the Settings chip. The rows that need no action are counted only in the popover, on the line they fold into, "2 files need no action · nothing was lost", and no surface counts them as files that need the user: `scripts/test-google-drive-logic.js` holds both. Each of its `conflicts` carries:

- `key`: the record's key.
- `needs`: the record's `you` or `nothing`.
- `localAction`: whether the row has an action on this computer. It is true for a `both-changed`, `removed-locally`, `removed-on-drive` or `renamed` row whose file is here. A doubled name and a file the download could not copy are fixed in Google Drive, so their rows have no action here, whoever owns the copies.
- `localPath`: the record's path of the file on this computer, on every row but a file the download could not copy with no earlier copy here.
- `copyFolder`: on a `both-changed` row whose local file a download replaced, the folder of the kept copy.

The popover's Show older copy opens `copyFolder` in the file manager, on a row that needs the user and has `localAction`. Each row that needs no action offers Dismiss instead (`GoogleDriveLogic.conflictRow`), and a row that needs the user never does, since its fix is still the user's. Each row's file name, in both lists, is a link while the row carries `localPath`: a click opens that file through the core's file route, `shell.tui.edit`: a text file in the core editor, any other file in its default application. The popover closes once the file opened. A file that is no longer on this computer opens nothing, and its row says "This file is no longer on this computer." and stays. A row with no `localPath` draws its name as plain text.

Each row's line says what happened and what the user does, or that nothing is lost: a doubled name the user owns says how to remove it from the list, one another account owns names that owner when the record does, and a `both-changed` row says whether VGS kept the copy that was here or copied it to Drive.

An earlier runner recorded a doubled name as `duplicate-on-drive`, with no copy facts. The first invocation of this runner drops those records, logging `migration=pair-state ... dropped=duplicate-on-drive`, since reading the copies needs Google Drive and that step runs without it; the next sync that meets the name records it whole. A status record that an earlier runner notified of stays notified across the new attention key.

A pair that another run holds reads `busy` and copies nothing.

### Dismissed rows

Dismiss hides a row that needs no user action until its record changes. [`bin/google-drive::dismissVerb`](bin/google-drive) owns the locked update and refuses a key that names no current row, `dismiss=unknown`, or a row that needs the user, `dismiss=needs-you`. The row leaves the popover, and the fold line goes with the last row. There is no undo or list of dismissed rows. The record stays, so a change shows it again under a new key. A status write retains only dismissed keys for current rows, so an old dismissal never hides a later record and the list cannot outgrow the rows. An unreadable pair list drops no keys.

A `control.json` with no `dismissed`, as every one before dismissals, dismisses nothing, so it needs no converter step. A doubled name recorded before records held `version` gets one at the next sync that lists its copies, which changes its key; that sync carries a dismissal of the earlier key to the new one, since only the version was added.

## Credentials

- The client id, the client secret and the token live in the keyring alone. No argv, file, log or systemd unit holds one.
- The token is the account's one keyring item, with the Google account's address in its `user` attribute. `probe` reports that address.
- The credential uses the Drive scope `drive`.
- `sign-out` clears the token and marks each pair as needing a sign-in. The client keys and every file stay.

## Files

- `~/.config/vgshell/google-drive/pairs.json`: the folder pairs, `{ pairs: [{ id, label, remote, local }] }`. Add a folder pair and Remove a folder pair change it through `pair-add` and `pair-remove`, which judge every pair. Start the folder pair list again runs `pairs-reset`, which keeps a damaged list beside a new empty list.
- `~/.local/state/vgshell/google-drive/status.json`: the status record the plugin's service watches and publishes. Its `units` is `installed`, both units as install writes them now; `absent`, neither; or `stale`, anything else. Each of its `pairs` carries the pair's `remote`, the Drive folder, and `local`, the folder on this computer. The service watches the file only after its first `status` call, which writes the record whole.
- `~/.local/state/vgshell/google-drive/control.json`: the pause record, the attention key last notified and the dismissed row keys, so all three survive a restart.
- `~/.local/state/vgshell/google-drive/pairs/<id>/`: each pair's state, inventory and conflict copies.
- `~/.local/state/vgshell/google-drive/setup.log`: what the setup windows logged. `setup.before-rename.log` beside it holds the earlier name's log when a setup window had begun this one before the rename below.
- `~/.local/state/vgshell/google-drive/rename.pending`: present from the rename's first move until its last step ends. It names each keyring account still held under the earlier name.

The runner migrates the plugin's earlier name in place before a normal verb. [`bin/google-drive::migrateRenameIfNeeded`](bin/google-drive), including its `the rename` section, owns the old paths and ordered moves. Keep the migration under the state lock and keep `rename.pending` until every step finishes. Never replace a file held under both names. Never clear an old keyring item until its copy under `vgs-google-drive`, including the token's `user` attribute, is checked. Replace installed units and clear their old failed state without losing the retry record.

An enabled plugin must leave the earlier timer enabled while an earlier sync runs, including a sync that starts during timer disable. A failed disable or an unreadable service state also holds the invocation with `migration=held` and exit 75. The plugin retries status and probe every 15 seconds; its Google Drive sync row on Details reads Waiting with the runner's reason until migration can proceed.

A step that cannot finish, such as the keyring step while the keyring is locked, logs `migration=held` and lets the verb go on. Every later invocation takes the state lock and retries the steps left. Until then, `probe`, a sync, Sign in and Sign out read an account still under the earlier name as locked, or as unreadable after a failed copy, never as missing.

For a disabled plugin, the root `migrate` entry calls the runner's internal `migrate disabled` verb under the [startup migration contract](../../../.agents/skills/vgs-plugin/references/api.md#startup-migrations). It stops and disables the old and partially installed units before taking the state lock. It never starts a sync or enables a timer. A failed stop or incomplete keyring move returns failure and keeps the data and retry records for the next shell start.

The migration must remove its temporary service overrides after the stop on success and failure.

A locked keyring item at the probe prevents a store call. If the collection locks between the read and the store, the store can show one unlock prompt. The old item stays until the copy is checked, so this race loses no data.

## The plugin

The plugin's IPC: `vgshell ipc call vgs.google-drive invoke <name> ""` with `status`, `sync`, `pause`, `resume` or `refresh`, and `vgshell ipc call vgs.google-drive invoke dismiss <key>`. The service's header states each answer.

## The google-drive command

`bin/google-drive` is the runner. Its header states every verb, its output, its exit codes and its refusals.

```text
shell/plugins/vgs.google-drive/bin/google-drive status
shell/plugins/vgs.google-drive/bin/google-drive pair-add --definition '{"id": "docs", "label": "Documents", "remote": "Documents", "local": "/home/me/Documents/drive"}'
shell/plugins/vgs.google-drive/bin/google-drive start
shell/plugins/vgs.google-drive/bin/google-drive pause
```
