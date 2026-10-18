# Google Drive developer reference

## A sync

- One systemd user service, `vgs-google-drive.service`, runs every sync: the hourly timer, Sync now in the popover and `start` on the command line all ask for that service, so a sync never runs twice at once. The timer runs hourly while the user is logged in, and once at the next login after a missed hour.
- The hourly sync is no setup step. A `pair-add` on a home with neither unit installs both and enables the timer before it writes the pair, under the state lock, and prints install's `installed=` line after `added=<id>`. A `pair-add` on a home whose units exist calls no `systemctl`. A failed install keeps the pair, exits 0, prints `install=failed <refusal>`, and leaves no unit it wrote, so the status record reads `units` `absent` beside the pair until the next `pair-add` or Set up again installs them. Add a folder pair says so on its screen.
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

A duplicate record holds `mine`, true when the signed-in account, the token's `user` attribute, owns one of the copies, and, when `mine` is false, `owner`, the first copy's owner Drive names. A copy with no owner, as on a shared drive, and a token that names no account never count as the user's. The runner reads the copies' sizes, md5s and owners with one read-only `rclone lsjson --hash --metadata --drive-metadata-owner read` of each folder that holds a doubled name, only in a sync whose download met one.

In the status record each of `conflicts` carries `needs`, `you` or `nothing`, from the table, and `needsYou` counts the `you` rows. The `conflicts` attention reason and its key take only the `you` rows, so a note never notifies.

The plugin's judge, `GoogleDriveLogic.parseStatus`, refuses a record whose `needsYou` is not that count, a row with no `needs`, `mine` on a row that is no doubled name, and `owner` other than on a doubled name that is not `mine`. The published `cloud` value carries `needsYou`, and each of its `pairs` its own `needsYou`. It lists the rows that need the user first before it caps the list, so the cap cuts notes first. Every count a surface shows is a `needsYou`: the bar badge, the headline, the tooltip, the Details sync lines and the Settings chip. Notes are counted only in the popover, on the line they fold into, and no surface calls a note a file to review: `scripts/test-google-drive-logic.js` holds both. Each of its `conflicts` carries:

- `needs`: the record's `you` or `nothing`.
- `localAction`: whether the row has an action on this computer. It is true for a `both-changed`, `removed-locally`, `removed-on-drive` or `renamed` row whose file is here. A doubled name and a file the download could not copy are fixed in Google Drive, so their rows have no action here, whoever owns the copies.
- `copyFolder`: on a `both-changed` row whose local file a download replaced, the folder of the kept copy.

The popover's Show older copy opens `copyFolder` in the file manager, on a row that needs the user and has `localAction`. A note has no action in the popover (`GoogleDriveLogic.conflictRow`).

Each row's line says what happened and what the user does, or that nothing is lost: a doubled name the user owns says how to clear it, one another account owns names that owner when the record does, and a `both-changed` row says whether VGS kept the copy that was here or copied it to Drive.

An earlier runner recorded a doubled name as `duplicate-on-drive`, with no copy facts. The first invocation of this runner drops those records, logging `migration=pair-state ... dropped=duplicate-on-drive`, since reading the copies needs Google Drive and that step runs without it; the next sync that meets the name records it whole. A status record that an earlier runner notified of stays notified across the new attention key.

A pair that another run holds reads `busy` and copies nothing.

## Credentials

- The client id, the client secret and the token live in the keyring alone. No argv, file, log or systemd unit holds one.
- The token is the account's one keyring item, with the Google account's address in its `user` attribute. `probe` reports that address.
- The credential uses the Drive scope `drive`.
- `sign-out` clears the token and marks each pair as needing a sign-in. The client keys and every file stay.

## Files

- `~/.config/vgshell/google-drive/pairs.json`: the folder pairs, `{ pairs: [{ id, label, remote, local }] }`. Add a folder pair and Remove a folder pair change it through `pair-add` and `pair-remove`, which judge every pair. Start the folder pair list again runs `pairs-reset`, which keeps a damaged list beside a new empty list.
- `~/.local/state/vgshell/google-drive/status.json`: the status record the plugin's service watches and publishes. Its `units` is `installed`, both units as install writes them now; `absent`, neither; or `stale`, anything else. Each of its `pairs` carries the pair's `remote`, the Drive folder, and `local`, the folder on this computer. The service watches the file only after its first `status` call, which writes the record whole.
- `~/.local/state/vgshell/google-drive/control.json`: the pause record and the attention key last notified, so both survive a restart.
- `~/.local/state/vgshell/google-drive/pairs/<id>/`: each pair's state, inventory and conflict copies.
- `~/.local/state/vgshell/google-drive/setup.log`: what the setup windows logged. `setup.before-rename.log` beside it holds the earlier name's log when a setup window had begun this one before the rename below.
- `~/.local/state/vgshell/google-drive/rename.pending`: present from the rename's first move until its last step ends. It names each keyring account still held under the earlier name.

The plugin had another name before Google Drive. For an enabled plugin, the runner's first invocation on a home that holds that name's directories or units runs the rename under the state lock, before its normal verb:

1. While that name's service runs a sync, the runner refuses the invocation with `migration=held` and exit 75, and leaves that name's timer enabled, so the hourly sync goes on under the earlier units. The plugin's service asks for the status and the probe again every 15 seconds while the runner answers 75; the first call after the sync ends runs the rename. Until then, the Google Drive sync row on the plugin page's Details tab reads Waiting and gives the reason from the runner's `migration=held` line. A failed disable and an `is-active` answer that names no state also refuse with exit 75.
2. Once no sync runs, the runner disables that name's timer. If the timer started a sync just before the disable, the runner enables the timer again and refuses as in step 1.
3. The runner writes `rename.pending`, then moves the directories here. A file that both names hold stays and logs `migration=held`.
4. It copies each keyring item to the `vgs-google-drive` service with the token's `user` attribute, checks the copy and clears the old item.
5. When the old units were installed, it installs the units under this name, removes the old unit files and reloads the user manager. It then clears the failed state the manager can keep for the old units, so `systemctl --user --failed` does not list them.
6. When every step finished, it removes `rename.pending`.

A step that cannot finish, such as the keyring step while the keyring is locked, logs `migration=held` and lets the verb go on. Every later invocation takes the state lock and retries the steps left. Until then, `probe`, a sync, Sign in and Sign out read an account still under the earlier name as locked, or as unreadable after a failed copy, never as missing. The runner's `the rename` section names the old paths.

For a disabled plugin, the root `migrate` entry calls the runner's internal `migrate disabled` verb under the [startup migration contract](../../../.agents/skills/vgs-plugin/references/api.md#startup-migrations). It stops and disables the old and partially installed units before taking the state lock. It never starts a sync or enables a timer. A failed stop or incomplete keyring move returns failure and keeps the data and retry records for the next shell start.

The migration must remove its temporary service overrides after the stop on success and failure.

A locked keyring item at the probe prevents a store call. If the collection locks between the read and the store, the store can show one unlock prompt. The old item stays until the copy is checked, so this race loses no data.

## The plugin

The plugin's IPC: `vgshell ipc call vgs.google-drive invoke <name> ""` with `status`, `sync`, `pause`, `resume` or `refresh`. The service's header states each answer.

## The google-drive command

`bin/google-drive` is the runner. Its header states every verb, its output, its exit codes and its refusals.

```text
shell/plugins/vgs.google-drive/bin/google-drive status
shell/plugins/vgs.google-drive/bin/google-drive pair-add --definition '{"id": "docs", "label": "Documents", "remote": "Documents", "local": "/home/me/Documents/drive"}'
shell/plugins/vgs.google-drive/bin/google-drive start
shell/plugins/vgs.google-drive/bin/google-drive pause
```
