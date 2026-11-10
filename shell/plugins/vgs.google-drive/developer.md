# Google Drive developer reference

Read when changing sync, conflict status or migration. The [manifest](manifest.json) declares entry points, secrets and TUIs. [bin/google-drive](bin/google-drive) owns pair storage, credentials, scheduler units, sync and status records. Its header defines verbs, paths, replies and exit codes.

## Sync ownership

The hourly timer and Sync now start the same user service. The runner also holds per-pair locks. The plugin never runs rclone itself.

`pairAddVerb` writes the pair list under the state lock and sets up scheduling when both units are absent. A failed scheduler install keeps the pair and reports the failure for retry. Existing units are not reinstalled by adding a pair.

Settings owns `twoWaySync`. [Service.qml](Service.qml) admits the install before its first mode mirror: existing pairs with no saved choice get a one-time Off write through the configure capability. Every saved choice, including On, stays unchanged. One key in the plugin's existing control record tracks admission, including admission with no pairs, so a fresh install keeps the On default when its first pair is added. Admission never infers a release or a choice from per-pair history.

The service's private `service-mode` command mirrors Settings into that control record for the hourly runner. Settings is the only mode-choice interface. The mirror starts no sync, invalidates no baseline and clears no pause. An active pair keeps its pinned route. On uses `runPairTwoWay`; explicit Off uses `runPairCopy`. An unprepared pair stays stopped while On, without a copy fallback. The notification and flyout action open the initialize TUI for the stopped pair, or its chooser when several need setup. The Setup action always opens the chooser; a Settings pair-row action passes that row's pair id.

`initializeVerb` is the only resync entry. The runner holds its existing fd3 flock through identity reads, complete equal-set comparison, preparation planning, rclone's dry-run preview, visible No-default confirmation through the shared TUI library, recheck and explicit initialization. Before consent, `equalSet` plans missing `RCLONE_TEST` access files in both roots and in-folder native-export moves into the pair's `exports/` directory at their relative paths. A move requires an `inventory.json` entry with `export: true`. A historical entry with size -1 or no MD5 permits a move when the local mtime matches the recorded Drive mtime. An entry with known size and MD5 requires matching local size, mtime and MD5. An occupied export destination, changed mtime, unknown copy, duplicate Drive name, one-sided or differing ordinary file, incomplete hash or changed evidence refuses with paths and a plain action.

Declining consent creates no access files and moves no exports. After consent, the runner repeats the comparison and checks the plan, account, roots, settings and evidence before making the planned changes. It never overwrites an export destination or discards a copy. The next comparison must match exactly the planned result before resync. Earlier records do not decide removal or rename intent; the owner reviews those choices and keeps other writers paused.

The successful binding in existing pair state names the signed-in account, both roots and their identities, and the fixed policy. Drive directory identity comes from unique entries in each parent's documented `lsjson --dirs-only` listing; this refuses duplicate folder names and ancestors that `lsjson --stat` alone could select ambiguously. The local identity uses realpath, device and inode. `equalSet` uses complete MD5 listings and rclone's two-direction `check --combined -`, not a new stored per-file baseline. Rclone owns the persistent `bisync/` workdir. `bisync-filters.txt` has fixed bytes from `EXCLUDES`; native-document refresh cannot change it.

On runs bisync with hash rename matching, all three comparison attributes, newer conflict resolution, local backup-dir1, access checks, empty-directory propagation, the 50-percent deletion stop, resilient/recover and max-lock. No normal operation has a resync flag, force or backup-dir2. Drive Trash remains at its default. Supported recovery belongs to rclone; an unsupported history failure preserves evidence and holds for fresh explicit initialization.

Off keeps the two `copy --update` legs and its inventory/export protection. Before its first actual copy call it persists `baseline: null`, even when that call later fails or is killed. An unused off/on toggle leaves the binding usable. A replaced local file in Off retains the earlier unchanged-download disposal rule; On never applies that rule to recovered bytes.

On downloads native exports only into the pair state's `exports/` folder, with an ephemeral native-only allow-list, the existing export formats and local overwrite recovery. It never uploads from there or adds these files to bisync history. A local ordinary path colliding with a current native export name holds before bisync because Drive can import an `.xlsx` onto a same-named Sheet. Genuine Office files remain included. Native export rename/removal can leave an earlier download, as in Off.

## Conflict status

[GoogleDriveLogic.js](GoogleDriveLogic.js) judges the runner's status in `parseStatus` and derives published data in `cloudValue`. `needsYou` counts records that require user action, not every review record. A doubled name's ownership and copy metadata belong to the runner's `duplicateRecords`, not a view's inference.

A conflict key identifies the whole record. Dismiss applies only to a current record needing no user action; `dismissVerb` checks it under the lock. A changed record can reappear with a new key. Dismissed keys survive restart but are retained only for current records, except when the pair list is unreadable.

New records carry an operation tag. Untagged records remain historical copy events; toggling the mode never rewords them into completed deletions. `bisyncRecords` consumes rclone's reported actions and actual backup bytes, not VGS rename matching. Only a successful operation promotes upstream actions to completed notes. A failed operation retains generic partial local recovery and never claims a queued removal completed. Recovery generation age controls the local keep; active undecidable conflict variants remain until settled.

Status names the next route, the pinned active route, initialization readiness, local recovery and export locations. Nonzero bisync preserves lastSuccess; it never uses the copy leg's partial-download success exception. Some files can change before failure. Only an actual pre-mutation refusal, such as the deletion-limit stop, says no synced file changed. Paused automatic runs do no sync, initialization or pruning; an explicit initialization can establish a paused pair without resuming it.

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
