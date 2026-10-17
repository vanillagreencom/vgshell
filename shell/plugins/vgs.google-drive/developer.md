# Google Drive developer reference

## A sync

- One systemd user service, `vgs-google-drive.service`, runs every sync: the hourly timer, Sync now in the window and `start` on the command line all ask for that service, so a sync never runs twice at once. The timer runs hourly while the user is logged in, and once at the next login after a missed hour.
- A sync copies each folder pair two ways, and only files that are newer: Drive to this computer, then this computer to Drive.
- The runner never deletes, moves or mirrors a file on either side.
- A local file that a download replaces is kept under the pair's records, unless it is the copy the runner made at the last sync. A file that an upload replaces stays in Drive as an earlier revision, under Drive's own retention.
- A Google-native document downloads as an export. A local file at an export's name is never uploaded.
- The runner removes kept copies and review records after 30 days.
- A sync removes a review record whose file is on neither Drive nor this computer, unless the record holds a kept copy of the file.

## Conflicts

| Record | Meaning | Result |
| --- | --- | --- |
| `both-changed` | The file changed on this computer and on Drive since the last sync, or a new pair holds a different file on each side. | The newer file is on both sides. An older local file is kept under the pair's records. An older Drive file is an earlier revision in Drive. |
| `removed-locally` | The file was removed on this computer. | The file returns from Drive. |
| `removed-on-drive` | The file was removed on Drive. | The file returns to Drive. |
| `renamed` | Drive's object id shows that the file has a new name. | Both names exist: the old name returns to Drive. |
| `unreadable-on-drive` | The download of the file failed, such as for a shortcut whose target is gone. The record holds rclone's reason; the window gives it in plain words. | The file is not copied and keeps its last baseline. The rest of the pair is synced. |
| `duplicate-on-drive` | Drive holds two files with this name in one folder. | One of them is copied. |

The last two records stand only while the last download met the file: a sync where the file copies removes its record, and the 30-day removal does not apply to them.

A pair that another run holds reads `busy` and copies nothing.

## Credentials

- The client id, the client secret and the token live in the keyring alone. No argv, file, log or systemd unit holds one.
- The token is the account's one keyring item, with the Google account's address in its `user` attribute. `probe` reports that address.
- The credential uses the Drive scope `drive`.
- `sign-out` clears the token and marks each pair as needing Connect. The client keys and every file stay.

## Files

- `~/.config/vgshell/google-drive/pairs.json`: the folder pairs, `{ pairs: [{ id, label, remote, local }] }`. Add a folder pair and Remove a folder pair change it through `pair-add` and `pair-remove`, which judge every pair. Start the folder pair list again runs `pairs-reset`, which keeps a damaged list beside a new empty list.
- `~/.local/state/vgshell/google-drive/status.json`: the status record the plugin's service watches and publishes.
- `~/.local/state/vgshell/google-drive/control.json`: the pause record and the attention key last notified, so both survive a restart.
- `~/.local/state/vgshell/google-drive/pairs/<id>/`: each pair's state, inventory and conflict copies.
- `~/.local/state/vgshell/google-drive/setup.log`: what the setup windows logged.
- `~/.local/state/vgshell/google-drive/rename-keyring.held`: present while the keyring step of the rename below waits for an unlocked keyring.

The plugin had another name before Google Drive. The runner's first invocation on a home that holds that name's directories or units moves them here under the state lock, after it disables that name's timer and waits out its running sync. It copies each keyring item to the `vgs-google-drive` service with the token's `user` attribute, checks the copy and clears the old item. It installs the units under this name when the old ones were installed, then removes the old unit files. A locked keyring holds the keyring step alone, which logs `migration=held` and finishes at a later invocation. The runner's `the rename` section names the old paths.

## The plugin

The plugin's IPC: `vgshell ipc call vgs.google-drive invoke <name> ""` with `status`, `sync`, `pause`, `resume`, `refresh` or `open`. The service's header states each answer.

## The google-drive command

`bin/google-drive` is the runner. Its header states every verb, its output, its exit codes and its refusals.

```text
shell/plugins/vgs.google-drive/bin/google-drive status
shell/plugins/vgs.google-drive/bin/google-drive pair-add --definition '{"id": "docs", "label": "Documents", "remote": "Documents", "local": "/home/me/Documents/drive"}'
shell/plugins/vgs.google-drive/bin/google-drive start
shell/plugins/vgs.google-drive/bin/google-drive pause
```
