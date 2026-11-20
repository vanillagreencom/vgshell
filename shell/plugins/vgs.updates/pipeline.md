# Update pipeline reference

Read when changing update execution or source admission. The [manifest](manifest.json) declares the all-source and single-source TUIs. Both use [tui/pipeline.sh](tui/pipeline.sh); its header defines invocation, source order, paths and exits. [bin/facts](bin/facts) translates runner JSON for the pipeline.

## Transaction boundaries

One lock protects the update run. A busy run leaves the active run's log intact. Low disk space and snapshot failure warn without refusing the update.

The plan precedes the snapshot and Updates' credential session. Package steps keep the system's and helper's own configuration. A missing AUR helper reviews its fetched clone before building it, after the system upgrade and after Updates ends its session.

A snapshot precedes package replacement when a configured tool and elevation route are available. Update all reads what pacman, the AUR and each file source have pending through the package owner's check; another primary's system step always runs, since only pacman's check is known to read fresh package lists. A run that replaces no package takes no snapshot and asks no password. The system step runs whenever another package step runs, since each of those needs the system upgrade first. The pipeline drops its shared sudo session before the AUR phase. That phase uses its own credential guard and drops any cached credential on completion, failure or interruption.

The pipeline takes package plans and execution from the shared package owner. Its start-confirmation option does not answer package-manager or review questions. It keeps orphaned packages and prints the reboot decision in that mode.

Orphan clean-up follows the system and file sources before the shared credential session ends. pacman's removal confirmation is its only question. The package owner's build-tool judgement keeps declared tools out of removal ([D128](../../../docs/decisions/D128-keep-declared-build-tools.md)); tools installed by later AUR builds are judged at the next run. An unread orphan list or build-tool read skips only clean-up. A declined removal keeps the packages without failing the run.

## Outcomes and transcript

No part's failure ends the run. A source-step failure records its cause and permits later independent sources. A failed or declined system step, or a system plan or check that could not be read, skips the file sources, AUR work, the VGS rebuild and orphan removal, each with its result line. A failed paru install skips AUR work and the VGS rebuild that depends on it. A refused password skips every step that needs it and leaves the others running. A declined AUR transaction never grants rebuild permission. After a failed build, the package owner must prove that every failed package is outside VGS's dependency build order before the rebuild proceeds. Unknown evidence keeps the rebuild skipped. Interruption stops the run. The error trap is for faults of the pipeline itself and still prints the result list so far; the header distinguishes source failures from these faults.

The cause reader owns each result sentence. A refusal that gives only its key reads as a sentence without it, and the key goes to the diagnostics log. pacman's known English errors map to VGS's sentences. The package owner's review outcome is the cause of a failed step and the whole result of a step it skipped. Each package result line the owner prints joins the result list, whatever the step's status. A paru step that ends 0 with output VGS cannot read has an unknown result, and no later step counts on it. Every line a step printed passes through `PackageReview.failureLines` before it reaches a result line or the outcome file ([secrets.md](../../../docs/architecture/secrets.md)).

The terminal remains attached to both output streams. The outer TUI relay compacts source-build output after recording it, naming the full log while retaining questions on screen. Cause extraction reads marked ranges from the original shared TUI transcript, rather than the compact display. An unavailable transcript range reports that the output could not be read; it does not invent a package failure cause.

The pipeline owns the outcome file the [service](developer.md#cadence) reads. Its header defines the file. One writer, the outer process's exit trap, writes it from the facts the run leaves in its private folder, so a credential session's traps cannot replace it. The log and diagnostic functions own their file paths.

## Third-party review

The [package-review contract](../../../docs/architecture/commands-are-data.md#package-review) owns consent and review. The package owner runs the agent during paru's file-manager review, after Updates ends its credential session. paru builds the clones it handed to that review. Updates retains no receipt or later binding.

A supported custom AUR command uses the same reviewed argv. An unsupported command requires explicit continuation with unavailable review; a No reads as a declined step. yay retains its own review menus.

Updates owns source order, snapshots, results, orphan decisions and reboot decisions. The common package owner supplies agent detection, review settings, prompts and verdict parsing. The reboot-notice system step alone changes CachyOS's hook policy.

## Completion

The pipeline asks about reboot only for packages this run changed that the reboot rules name. An unread check warns once and adds a non-failed result line. Choosing Reboot runs `vgshell power reboot`, which calls `systemctl reboot` immediately; it does not ask Jarvis to save work first. The shell restart follows the reboot question when a VGS package changed, unless Reboot succeeded. Restart and Reset select an existing Hyprland session even from a terminal outside the desktop. An unreachable desktop leaves the update finished and says the shell restarts at the next login; a restart failure still counts as a failed part. The pipeline records its end before the question and updates that record with the restart result. The pipeline does not hold the system awake.

Each failed or stopped outcome stores its title separately from the sentence that explains the next step. A restart-only outcome expires after a newer shell start or boot; other failures and stopped runs remain until the next run. The service reads older outcomes through the in-place converter before judging the current format ([D107](../../../docs/decisions/D107-format-change-ships-its-migration.md)).

The service observes completed TUI runs and checks again under [its cadence rules](developer.md#cadence). Source failures remain failures even when later sources succeed.
