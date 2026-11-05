# Update pipeline reference

Read when changing update execution or source admission. The [manifest](manifest.json) declares the all-source and single-source TUIs. Both use [tui/pipeline.sh](tui/pipeline.sh); its header defines invocation, source order, paths and exits. [bin/facts](bin/facts) translates runner JSON for the pipeline.

## Transaction boundaries

One lock protects the update run. A busy run leaves the active run's log intact. Low disk space and snapshot failure warn without refusing the update.

The plan and shared review preparation precede the snapshot and Updates' credential session. A missing AUR helper is a separate reviewed prerequisite transaction whose credentials end before that preparation.

A snapshot precedes package replacement when a configured tool and elevation route are available. The pipeline drops its shared sudo session before the AUR phase. That phase uses its own credential guard and drops any cached credential on completion, failure or interruption.

The pipeline takes package plans and execution from the shared package owner. Its start-confirmation option does not answer package-manager or review questions. It prints orphan and reboot decisions instead of asking them in that mode.

## Outcomes and transcript

A source-step failure records its cause and permits later independent sources. A failed or declined system step skips AUR work and the VGS rebuild that depends on it. A declined or failed AUR transaction does not grant a rebuild permission to retry packages it left out. Interruption stops the run; the header distinguishes source failures from other fatal failures.

The terminal remains attached to both output streams. Cause extraction reads marked ranges from the shared TUI transcript, rather than splitting output through another pipe. An unavailable transcript range reports that the output could not be read; it does not invent a package failure cause.

The pipeline owns the rebuild-failure record consumed by [the check service](developer.md#sources). Its writer defines the record and ties it to the installed version and helper outcome. The log and diagnostic functions own their file paths.

## Third-party review

The [package-review contract](../../../docs/architecture/commands-are-data.md#package-review) owns consent and common admission. Updates retains each source's prepared effective configuration through execution. Each upgrade or named rebuild consumes its exact bound authority once. Completion or cancellation removes unused authority.

A missing, stale, consumed or unreadable binding stops before mutation. Review does not start again inside a credential session. A supported custom AUR command uses common admission; unsupported commands require explicit continuation with unavailable review and receive no package-skipping or clean verdict.

Updates owns source order, snapshots, hook masking, results, orphan decisions and reboot decisions. The common package owner supplies agent detection, review settings, prompts and verdict parsing.

## Completion

The pipeline's reboot decision reads changed packages and the core's running-kernel and compositor checks. Choosing reboot follows the core power route so Jarvis can save work. The pipeline does not hold the system awake.

The service observes completed TUI runs and checks again under [its cadence rules](developer.md#cadence). Source failures remain failures even when later sources succeed.
