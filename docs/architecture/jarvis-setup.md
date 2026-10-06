# Local voice setup

Covers: shell/plugins/vgs.jarvis/setup-local, shell/plugins/vgs.jarvis/requirements-local*.lock, shell/plugins/vgs.jarvis/LocalRuntime.qml, shell/plugins/vgs.jarvis/tui/setup-local.sh, scripts/test-jarvis-setup.py, scripts/fixtures/jarvis-setup/, scripts/smoke/rows/jarvis-setup.sh

The declared `setup-local` TUI gives Settings and the launcher the same setup path. [D033](../decisions/D033-floating-tuis-are-core.md) owns its presentation. [D033](../decisions/D033-floating-tuis-are-core.md) keeps the complete plugin available through shell restarts.

## Inputs and boundary

[`artifacts.json`](../../shell/plugins/vgs.jarvis/artifacts.json) remains the only model, provider, tier and runtime-version declaration. Setup calls `measure-local::manifest`, `verify`, `clip` and `run`. The installed interpreter runs the real bundled synthetic-clip oracle before setup publishes readiness. [The local input contract](jarvis-local.md) and [D066](../decisions/D066-pinned-local-speech-and-bounded-inputs.md) define that oracle and its limits.

The shipped lock covers Python packages and their transitive dependencies with exact versions and wheel hashes. Its native CPU entries project the artifact declaration. CUDA setup projects the pinned wheel URL and hash from that declaration onto the common lock. The selected wheels target Linux x86_64 and the declaration's Python ABI. The installer permits no source builds or unhashed packages. PyPI release JSON supplies the transitive lock data. [uv's environment interface](https://docs.astral.sh/uv/pip/environments/) supplies explicit venv selection.

Each tier declares a one-line `description` and its `downloadBytes`. That figure is the sum of the pinned model archives' HTTP Content-Length, PyPI's wheel size for every hash in the tier's lock, the CUDA wheel's Content-Length for a CUDA tier, and uv 0.12.23's managed CPython 3.12.15 `install_only_stripped` archive, read on 2026-10-04. JSON takes no comment, so the provenance lives here.

uv creates a managed Python environment under the plugin's data root. Its interpreter download, cache, models and environment remain there. The marker binds the actual interpreter and installed package bytes, not a promise that a native CPU wheel behaves like the separately measured CUDA build. Each machine must pass its own selected-runtime probe. A CUDA setup still needs working CUDA libraries; setup changes no driver or host setting. Hardware choice, admission and production segmentation remain separate owners.

curl ignores its user configuration and permits HTTPS downloads and redirects only. A partial file gets its final name only after its pinned hash matches. Python extracts only ordinary files and directories inside the model root. The existing verifier checks extracted inference and auxiliary bytes against the declaration and archive.

Setup opens no microphone, speaker, account or authentication endpoint. The real inference probe runs without network access. VGS ships no Python environment, model, CUDA library or espeak runtime. The core requirement notice installs the plugin's declared missing commands under [D035](../decisions/D035-manifest-requirements.md); setup never runs a system package manager.

The Debian package index has no uv package. The declaration offers the existing mise source route where mise is available instead of inventing an apt package. A system with neither a native uv package nor mise has no declared uv install route. Fedora has no declared automatic install route for the NVIDIA command. Installing VGS does not recommend an NVIDIA driver package. A CUDA tier on Fedora needs an already available NVIDIA command and working CUDA libraries. These are requirement-source limits, not successful setup.

## Readiness

`setup-local::choices` prints one `LABEL<TAB>TIER` row per tier this machine can run, in declaration order; the TUI hands the rows to `gum choose --label-delimiter`, which prints the tier. The label joins the tier's description, its provider's hardware sentence and its download size. `setup-local::runnable` is the one judge of "can this machine run this tier": a CPU tier always can; a CUDA tier only when the plugin's declared `nvidia-smi` requirement answers `nvidia-smi -L` with exit 0. The first row is marked recommended. The declaration lists a CPU tier first, because a CUDA tier can still fail on CUDA libraries that a listed GPU does not prove.

`setup-local::install` refuses before its first byte and before it removes the marker, so a refused attempt leaves an earlier ready installation in place. It refuses a tier whose provider this machine cannot run (`gpu=unavailable`) and a data root whose free space is under twice the tier's download less the bytes of the runtime and models it replaces (`disk=insufficient`). Twice rests on the one measured setup: a 2.26 GB CUDA download held 4.2 GB on disk afterwards, the archives beside their extracted models and uv's cache beside the environment.

The probe's stderr goes to `local-setup.log` in the state root, truncated each attempt. A failed probe prints `failed=probe` with the log's path and a plain-English line, and keeps its exit status. A failed or cancelled attempt removes the environment, the models and the projected CUDA lock. It then prints `kept=` with the data root and the bytes left there, uv's cache and managed Python, which the next setup reuses.

`setup-local::install` holds one exclusive state lock from marker removal through publication. A competing setup cannot remove the active run's marker or change its files. Readers take a non-blocking shared lock and report setup in progress while the exclusive owner runs.

The success marker lives in the state root. Runtime and model files live in the data root defined by [the Jarvis service](jarvis.md#wire). Every attempt removes an earlier marker before installation effects. Download, install, verification and probe failures preserve their nonzero status. Exit `77` is unavailable, never ready. Cancellation cannot continue to marker publication.

The scrubbed probe environment retains the original XDG state and data roots. It removes the appended VGS path before resolving a root alias. A symlink inside that root changes model storage, not the XDG root identity. The installed interpreter executes the same `setup-local::roots` entry as the parent, not a default HOME model directory or a path inferred from uv's cache.

`setup-local::identity` binds the tier, physical data root, artifact declaration, package locks, setup and measurement sources, fixture bytes, venv configuration, resolved interpreter and installed runtime bytes. Derived Python bytecode does not enter that identity. Setup checks identity before and after inference. It atomically publishes the pre-probe identity only when those inputs still agree.

`setup-local::status` requires that marker, the current identity, the current fixture and verified local model bytes. A moved data root, changed lock, changed source, changed interpreter/package or model corruption cannot report ready. It does not infer readiness from installation exit, directory presence or the TUI's exit code.

`LocalRuntime.qml` is the service's one status writer. It rechecks on startup, after every requirement scan and after `shell.tui.state["setup-local"].endedAt` changes, including a run Settings or the launcher started. Local voice lists no `requires` commands, so `SetupGate.js` publishes its value unchanged ([jarvis-browser.md § Owners](jarvis-browser.md#owners)). A helper that fails, cannot start or returns invalid output replaces a previous ready value with an offered setup action. It does not start an engine or change the daemon's policy.

## Evidence

- `scripts/test-jarvis-setup.py` executes the shipped installer and TUI inside [J09's private world](validation-jarvis.md). Local curl, uv, namespace-command and selected-interpreter doubles record actual argv. Every tier uses the producer's membership. These tests prove installation sequencing, not real model feasibility.
- The installed-probe fixture executes the shipped `main`, `roots` and `probe` entry with synthetic inference. Its root table covers aliases of the XDG roots and an inner `vgs` storage symlink. Shared input verification stays active. Controls drop forwarding or recover the root from resolved model storage; each leaves no marker and exactly Not set up. The missing-gum case uses the real TUI library and rejects a copy that draws the header before checking commands.
- An `nvidia-smi` double answers the GPU judge in every case, so no host GPU is read. Cases cover the offered rows with and without a GPU, the GPU and disk refusals before any uv or curl call with the earlier marker intact, a probe failure whose engine lines reach the log and not the owner, and the cleanup and `kept=` report. The TUI case without a GPU picks the recommended row and ends ready.
- Disposable behavior-preserving-text mutants cover download hashes, child failures, marker invalidation, identity, changed-during-probe inputs, serialization, archive containment, probe delegation, hash-required installation, TUI execution, the GPU judge, the GPU and disk refusals, the probe log and the failure cleanup. The existing artifact suite owns its verifier and inference-oracle controls.
- `scripts/smoke/rows/jarvis-setup.sh` uses J09's status-process double and an allow-listed TUI fixture. It reads the Settings action and launcher entry, copied-snapshot argv, completion refresh and failure replacement. Its consumer assertions reject copies without refresh or failure replacement.
- The install-tree check packages every runtime file. The nested read-only-prefix row loads the new service-owned reader from the installed tree and checks that startup changes no prefix file.
- The install-tree suite retains namespace unavailability as `77` only after all independent checks pass. Private copies of its installation assertions, namespace consumer and closing verdict prove both that result and failure precedence. Controls turn unavailability into a failure or let it hide a failed installer double.
- `scripts/check-jarvis-local.sh` remains the real prepared-model execution row. An unavailable prepared environment returns `77`. Synthetic installer doubles are not evidence that real installation or native CPU inference succeeded.

## Omarchy comparison

The read-only Omarchy `bin/omarchy-voxtype-model` opens model setup in its floating terminal. `bin/omarchy-voxtype-install` confirms installation and delegates model download to Voxtype. VGS takes that visible, user-started setup and engine verification. It uses the pinned declaration and bundled probe because its speech stack has several runtime consumers. It does not copy Omarchy's systemd setup, GPU enabling, Hyprland reload or shell restart. The existing service observes the TUI's completion instead.

On its default branch, `omarchy-voxtype-install` states the download size in its confirmation ("Install Voxtype + AI model (~150MB) to enable dictation?") and enables the GPU path only when `omarchy-hw-vulkan` passes; `omarchy-hw-nvidia` reads the sysfs PCI vendor `0x10de`. VGS takes the size in the choice and the hardware-gated offer. It reads `nvidia-smi -L` rather than sysfs because a CUDA tier needs a loaded NVIDIA driver, which a PCI ID does not prove, and the plugin already declares that command.
