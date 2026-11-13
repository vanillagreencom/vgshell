# Update pipeline reference

Read when changing update execution or source admission. The [manifest](manifest.json) declares the all-source and single-source TUIs. Both use [tui/pipeline.sh](tui/pipeline.sh); its header defines invocation, source order, paths and exits. [bin/facts](bin/facts) translates runner JSON for the pipeline.

## Transaction boundaries

One lock protects the update run. A busy run leaves the active run's log intact. Low disk space and snapshot failure warn without refusing the update.

The plan and effective package configurations precede the snapshot and Updates' credential session. A missing AUR helper reviews its fetched clone before building it. Its credentials end before Updates starts its session.

A snapshot precedes package replacement when a configured tool and elevation route are available. The pipeline drops its shared sudo session before the AUR phase. That phase uses its own credential guard and drops any cached credential on completion, failure or interruption.

The pipeline takes package plans and execution from the shared package owner. Its start-confirmation option does not answer package-manager or review questions. It prints orphan and reboot decisions instead of asking them in that mode.

## Outcomes and transcript

No part's failure ends the run. A source-step failure records its cause and permits later independent sources. A failed or declined system step, or a failed paru install, skips AUR work and the VGS rebuild that depends on it. A refused password skips every step that needs it and leaves the others running. A declined AUR transaction never grants rebuild permission. After a failed build, the package owner must prove that every failed package is outside VGS's dependency build order before the rebuild proceeds. Unknown evidence keeps the rebuild skipped. Interruption stops the run. The error trap is for faults of the pipeline itself and still prints the result list so far; the header distinguishes source failures from these faults.

The cause reader owns each result sentence. A refusal that gives only its key reads as a sentence without it, and the key goes to the diagnostics log. pacman's known English errors map to VGS's sentences. The package owner's review sentence takes precedence over paru's file-manager error. Every line a step printed passes through `PackageReview.failureLines` before it reaches a result line or the outcome file ([secrets.md](../../../docs/architecture/secrets.md)).

The terminal remains attached to both output streams. The outer TUI relay compacts source-build output after recording it, naming the full log while retaining questions on screen. Cause extraction reads marked ranges from the original shared TUI transcript, rather than the compact display. An unavailable transcript range reports that the output could not be read; it does not invent a package failure cause.

The pipeline owns the outcome file the [service](developer.md#cadence) reads. Its header defines the file. One writer, the outer process's exit trap, writes it from the facts the run leaves in its private folder, so a credential session's traps cannot replace it. The log and diagnostic functions own their file paths.

## Third-party review

The [package-review contract](../../../docs/architecture/commands-are-data.md#package-review) owns consent and review. The package owner runs the agent during paru's file-manager review, after Updates ends its credential session. paru builds the clones it handed to that review. Updates retains no receipt or later binding.

A supported custom AUR command uses the same reviewed argv. An unsupported command requires explicit continuation with unavailable review. yay retains its own review menus.

Updates owns source order, snapshots, hook masking, results, orphan decisions and reboot decisions. The common package owner supplies agent detection, review settings, prompts and verdict parsing.

## Completion

The pipeline's reboot decision reads changed packages and the core's running-kernel and compositor checks. Choosing reboot follows the core power route so Jarvis can save work. The pipeline does not hold the system awake.

The service observes completed TUI runs and checks again under [its cadence rules](developer.md#cadence). Source failures remain failures even when later sources succeed.
