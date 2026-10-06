# Jarvis is one service, one leased child and one wire judge

Read before touching the Jarvis service, its daemon, a child it starts, its wire, its records, or the capture indicator.

## The approach

`vgs.jarvis` is one service that owns one Node child whose lease is its closed stdin; every module reaches the shell only through that child's wire, and every process the daemon starts dies with it. One wire judge, `JarvisProtocol.accept`, owns every shape in both directions, and the daemon owns the generation identity the service carries back. `Session` is the sole admission judge: capture opens only after the shell has presented the indicator, a passive layer the service owns, and never from a component's existence, a status file or a pending request. Private records hold names, never values. A failure is a keyed `jarvis: <area>=<cause>` with no provider text, and readiness comes only from its one judge. The choices are [D064](../decisions/D064-jarvis-child-lease.md), [D082](../decisions/D082-jarvis-approval-bound-to-the-action.md) and [D087](../decisions/D087-jarvis-task-control.md).

## Why

A pipe closes after a shell crash without QML teardown, where a parent-death signal alone misses a parent already dead. Linux clears the parent-death signal across fork and a process group misses a descendant that closed its pipes, so only the death of a namespace's init kills every descendant. The microphone owner must not outlive the indicator, so a sidecar is a leased child and never a service. A pending mute while the daemon is unavailable means mute on, because no toggle state exists. An audit that stored a value would hold the secret it exists to keep out.

## Rules

- Do end the child by closing its stdin; never add a systemd unit or a detached keeper. `scripts/test-jarvis-daemon.js` and `scripts/smoke/rows/jarvis.sh` pin it.
- Do start every child through `setpriv --pdeathsig KILL` with a parent check, run audio children inside a PID namespace that dies with the daemon, and give each child an explicit environment with no key and no `VGSHELL_RUNNER_PID`. `scripts/test-jarvis-audio-daemon.js`, `scripts/test-jarvis-audio.js` and `scripts/test-jarvis-desktop-tools.js` pin each.
- Never fall back to a host process, a unit or a privilege prompt when user namespaces are refused; report an audio fault.
- Do start one speech sidecar per conversation, load models when it opens and unload when it closes; never write under the plugin directory from a child. `scripts/test-jarvis-local-speech.js` and the read-only-prefix row pin both.
- Never read the core from the plugin snapshot; the daemon loads shared libraries from the VGS tree passed as argv. The read-only-prefix row pins it.
- Do add a wire type only in `JarvisProtocol.accept`, with both endpoint consumers; unknown types, extra fields and oversized lines fail. Never assign a daemon generation from the service. `scripts/test-jarvis-protocol.js` and `scripts/test-jarvis-daemon.js` pin both.
- Do treat a missing shell or lock value as locked; neither `locked` nor `ready` health permits capture. Never grant capture from a component's existence; the presented observation travels on the child's ordered wire. `scripts/test-jarvis-daemon.js` and `scripts/smoke/rows/jarvis-bubble.sh` pin both.
- Never start playback before Audio acknowledges the recorder closed, never queue microphone data for replay, and never add an echo loader whose success cannot be verified. `scripts/test-jarvis-session.js` and `scripts/test-jarvis-audio.js` pin it.
- Never let talk or stop clear mute, never copy mute into the mode setting, and register talk through the core hold-shortcut contract. `scripts/smoke/rows/jarvis-keys.sh` pins it.
- Do call `Audit.before` after authorization and before an executor or transfer starts, never put a value, image, transcript or key in a record, and use `cleanup` for stop, mute and teardown so an unwritable store cannot block privacy teardown. `scripts/test-jarvis-audit.js` and `scripts/test-jarvis-redact.js` pin each.
- Do exit 78 for a permanent configuration failure and never retry it; never let a successful hello replenish the restart allowance. `scripts/smoke/rows/jarvis.sh` pins both.
- Do publish every settings offer list through the plugin's `choices` status; a discovery failure never changes a configured provider or device. `scripts/smoke/rows/settings.sh` pins it.
- Never fall back to a default for a status shape the service does not produce, never infer readiness from an installer's exit status or a directory's presence, and never map a scratch or helper failure to exit 77. `scripts/test-jarvis-widget.js` and `scripts/test-jarvis-setup.py` pin them.
- Do keep a coding task the one child that outlives the daemon, reached only through records written by rename under one lock ([D072](../decisions/D072-coding-task-records-and-four-fact-state.md)); never put a goal or a path in TUI arguments. `scripts/test-jarvis-task-runner.js` pins it.

## The canonical example

`shell/plugins/vgs.jarvis/backend/Audio.js`: children in a leased namespace, one teardown path, bounded buffers that fault instead of retaining. Copy its lifetime shape for a new child owner.

## Revisit when

Quickshell provides a stronger child lease, capture moves to a process the shell cannot own, or an echo implementation can verify both module acquisition and routing before admitting simultaneous capture and playback.

## Not governed

What a tool executor does, which is [jarvis-executors.md](jarvis-executors.md); how a brain or speech adapter is written, which is [jarvis-adapters.md](jarvis-adapters.md); what leaves the machine, which is [jarvis-outbound.md](jarvis-outbound.md); the test world, which is [validation-jarvis.md](validation-jarvis.md).
