# Google Drive developer reference

Read when changing sync, conflict status or migration. The [manifest](manifest.json) declares entry points, secrets and TUIs. [bin/google-drive](bin/google-drive) owns pair storage, credentials, scheduler units, sync and status records. Its header defines verbs, paths, replies and exit codes.

## Sync ownership

The hourly timer and Sync now start the same user service. The runner also holds per-pair locks. The plugin never runs rclone itself.

`pairAddVerb` writes the pair list under the state lock and sets up scheduling when both units are absent. A failed scheduler install keeps the pair and reports the failure for retry. Existing units are not reinstalled by adding a pair.

Sync copies newer files in both directions without deleting, moving or mirroring either side. A replaced local file is retained unless it is the copy made at the last sync; Drive retains its own earlier revisions. Native-document exports are not uploaded as local originals. The runner owns retention and conflict classification.

## Conflict status

[GoogleDriveLogic.js](GoogleDriveLogic.js) judges the runner's status in `parseStatus` and derives published data in `cloudValue`. `needsYou` counts records that require user action, not every review record. A doubled name's ownership and copy metadata belong to the runner's `duplicateRecords`, not a view's inference.

A conflict key identifies the whole record. Dismiss applies only to a current record needing no user action; `dismissVerb` checks it under the lock. A changed record can reappear with a new key. Dismissed keys survive restart but are retained only for current records, except when the pair list is unreadable.

`conflictRow` owns local actions. A kept copy can offer its folder; duplicate and unreadable Drive objects require action in Drive. A local file opens through the core's file route. A missing file keeps its row and explains the failure.

## Credentials and migration

Credentials stay in the keyring. The token's `user` attribute identifies the signed-in account. Sign out clears the token and marks pairs as needing sign-in; client keys and synced files remain.

`migrateRenameIfNeeded` owns the previous-name migration. Keep its state lock, ordered moves and `rename.pending` retry record. It does not replace a destination already present or delete an old credential before checking its copy, including the token's account attribute.

For an enabled plugin, an active old sync, a failed timer disable or unreadable service state holds the invocation with exit 75. The old timer remains enabled while that sync runs. A later incomplete step, such as a locked keyring, keeps its retry record and permits the normal verb; unresolved old credentials read locked or unavailable, never absent.

For a disabled plugin, the manifest's migration entry follows the [startup migration contract](../../../.agents/skills/vgs-plugin/references/api.md#startup-migrations). It stops and disables old and partial units before taking the state lock, starts no sync and enables no timer. Failed stop or incomplete keyring work returns failure for retry. Temporary service overrides are removed on success and failure.

## IPC and runner

[Service.qml](Service.qml) defines IPC replies. It watches the completed status record and publishes it for the widget and panel. The runner's header is the command contract.

<details>
<summary>Show command</summary>

```text
shell/plugins/vgs.google-drive/bin/google-drive status
```

</details>
