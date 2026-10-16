# Cloud Sync developer reference

## A sync

- One systemd user service, `vgs-cloud-sync.service`, runs every sync: the hourly timer, Sync now in the window and `start` on the command line all ask for that service, so a sync never runs twice at once. The timer runs hourly while the user is logged in, and once at the next login after a missed hour.
- A sync copies each folder pair two ways, and only files that are newer: Drive to this computer, then this computer to Drive.
- Cloud Sync never deletes, moves or mirrors a file on either side.
- A local file that a download replaces is kept under the pair's records, unless it is the copy Cloud Sync made at the last sync. A file that an upload replaces stays in Drive as an earlier revision, under Drive's own retention.
- A Google-native document downloads as an export. A local file at an export's name is never uploaded.
- Cloud Sync removes kept copies and review records after 30 days.
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

- `~/.config/vgshell/cloud-sync/pairs.json`: the folder pairs, `{ pairs: [{ id, label, remote, local }] }`. Add a folder pair and Remove a folder pair change it through `pair-add` and `pair-remove`, which judge every pair. Start the folder pair list again runs `pairs-reset`, which keeps a damaged list beside a new empty list.
- `~/.local/state/vgshell/cloud-sync/status.json`: the status record the plugin's service watches and publishes.
- `~/.local/state/vgshell/cloud-sync/control.json`: the pause record and the attention key last notified, so both survive a restart.
- `~/.local/state/vgshell/cloud-sync/pairs/<id>/`: each pair's state, inventory and conflict copies.
- `~/.local/state/vgshell/cloud-sync/setup.log`: what the setup windows logged.

## The plugin

The plugin's IPC: `vgshell ipc call vgs.cloud-sync invoke <name> ""` with `status`, `sync`, `pause`, `resume`, `refresh` or `open`. The service's header states each answer.

## The cloud-sync command

`bin/cloud-sync` is the runner. Its header states every verb, its output, its exit codes and its refusals.

```text
shell/plugins/vgs.cloud-sync/bin/cloud-sync status
shell/plugins/vgs.cloud-sync/bin/cloud-sync pair-add --definition '{"id": "docs", "label": "Documents", "remote": "Documents", "local": "/home/me/Documents/drive"}'
shell/plugins/vgs.cloud-sync/bin/cloud-sync start
shell/plugins/vgs.cloud-sync/bin/cloud-sync pause
```
