# The Jarvis daemon, its brains and its actions

Read before touching the Jarvis service, its daemon, a child it starts, its wire, its records, the capture indicator, a brain or speech adapter, a provider row, the tool bridge or a tool executor.

## The approach

`vgs.jarvis` is one service that owns one Node child whose lease is its closed stdin; every module reaches the shell only through that child's wire, and every process the daemon starts dies with it. One wire judge, `JarvisProtocol.accept`, owns every shape in both directions, and the daemon owns the generation identity the service carries back. `Session` is the sole admission judge: capture opens only after the shell has presented the indicator, a passive layer the service owns, and never from a component's existence, a status file or a pending request. Private records hold names, never values. A failure is a keyed `jarvis: <area>=<cause>` with no provider text, and readiness comes only from its one judge. The choices are [D064](../decisions/D064-jarvis-child-lease.md), [D070](../decisions/D070-jarvis-action-policy.md) and [D072](../decisions/D072-coding-task-records-and-four-fact-state.md).

Every brain reaches the model and the tools by the same controlled route. A brain is a wire adapter, whose driver sends only through `WireBrain.js`, or a harness adapter, the vendor's unmodified program behind the tool bridge ([D079](../decisions/D079-brains-wire-and-harness-adapters.md)). One engine object per conversation owns the brain, the release grants and the heard prefix, and ends them all when the generation changes ([D089](../decisions/D089-jarvis-chained-engine-and-heard-prefix.md)). The daemon owns the local speech sidecar across conversations. Every item leaves through release, then audit, then the one network door that [jarvis-outbound.md](jarvis-outbound.md) governs. An account's Verified comes only from one explicit inference request the user started, judged by the same release owner.

Every action, a brain's tool call and a harness program's own approval request alike, passes one policy gate and reports only what it read back. An executor registers only after its own readiness probe passes, and every call reaches it through one serial router, `shell/plugins/vgs.jarvis/backend/ToolRouter.js`, which owns the only confirmation identity ([D070](../decisions/D070-jarvis-action-policy.md)). A command that may already have acted reports `unknown`, never `failed`. A desktop change goes to the shell as a request, so `shell/Core/Dispatch.js` stays the one dispatch judge.

## Why

A pipe closes after a shell crash without QML teardown, where a parent-death signal alone misses a parent already dead. Linux clears the parent-death signal across fork and a process group misses a descendant that closed its pipes, so only the death of a namespace's init kills every descendant. The microphone owner must not outlive the indicator, so a sidecar is a leased child and never a service. A pending mute while the daemon is unavailable means mute on, because no toggle state exists. An audit that stored a value would hold the secret it exists to keep out.

A harness tool left on would bypass the policy gate, and vendor terms allow a subscription only through the unmodified program. A provider error body can echo content or credentials, so it is cancelled unread. A chained brain has no server item to truncate, and bytes written overstate what was heard, so the heard prefix travels as a separate labelled item and history is never rewritten. A login-status or model-list reply proves an account exists, not that it answers, so only generated text verifies it.

A model can pick an action from untrusted file, page or screen content, so no executor may hold a second policy table or a confirm method; a serial hold removes Jarvis's own path to its own confirm key. A path judged by string can be swapped between the judgement and the open, so the executor rejudges at execution and walks held descriptors. A dispatcher answers `ok` without acting, and an application may keep its window open to ask about unsaved work, so only a read-back proves an effect. Registration proves nothing about confinement, so a shell tool is offered only after a real kernel probe answers.

## Rules

### Process and wire

- Do end the child by closing its stdin; never add a systemd unit or a detached keeper. `scripts/test-jarvis-daemon.js` and `scripts/smoke/rows/jarvis.sh` pin it.
- Do start every child through `setpriv --pdeathsig KILL` with a parent check, run audio children inside a PID namespace that dies with the daemon, and give each child an explicit environment with no key and no `VGSHELL_RUNNER_PID`. `scripts/test-jarvis-audio-daemon.js`, `scripts/test-jarvis-audio.js` and `scripts/test-jarvis-desktop-tools.js` pin each.
- Never fall back to a host process, a unit or a privilege prompt when user namespaces are refused; report an audio fault. Gap: no test refuses user namespaces.
- Do let the daemon own the local speech sidecar across conversations and close it on daemon teardown; never write under the plugin directory from a child. `scripts/test-jarvis-engine.js`, `scripts/test-jarvis-local-speech.js` and `scripts/smoke/rows/read-only-prefix.sh` pin both.
- Never read the core from the plugin snapshot; the daemon loads shared libraries from the VGS tree passed as argv. `scripts/smoke/rows/read-only-prefix.sh` pins it.
- Do add a wire type only in `JarvisProtocol.accept`, with both endpoint consumers; unknown types, extra fields and oversized lines fail. Never assign a daemon generation from the service. `scripts/test-jarvis-protocol.js` and `scripts/test-jarvis-daemon.js` pin both.
- Do exit 78 for a permanent configuration failure and never retry it; never let a successful hello replenish the restart allowance. `scripts/smoke/rows/jarvis.sh` pins both.
- Do publish every settings offer list through the plugin's `choices` status; a discovery failure never changes a configured provider or device. `scripts/smoke/rows/settings.sh` pins it.
- Never fall back to a default for a status shape the service does not produce, never infer readiness from an installer's exit status or a directory's presence, and never map a scratch or helper failure to exit 77. `scripts/test-jarvis-widget.js` and `scripts/test-jarvis-setup.py` pin them.
- Do keep a coding task the one child that outlives the daemon, reached only through records written by rename under one lock ([D072](../decisions/D072-coding-task-records-and-four-fact-state.md)); never put a goal or a path in TUI arguments. `scripts/test-jarvis-task-runner.js` pins it.

### Capture and records

- Do treat a missing shell or lock value as locked; neither `locked` nor `ready` health permits capture. Never grant capture from a component's existence; the presented observation travels on the child's ordered wire. `scripts/test-jarvis-daemon.js` and `scripts/smoke/rows/jarvis-bubble.sh` pin both.
- Never start playback before Audio acknowledges the recorder closed, never queue microphone data for replay, and never add an echo loader whose success cannot be verified. `scripts/test-jarvis-session.js` and `scripts/test-jarvis-audio.js` pin it.
- Never let talk or stop clear mute, never copy mute into the mode setting, and register talk through the core hold-shortcut contract. `scripts/smoke/rows/jarvis-keys.sh` pins it.
- Do call `Audit.before` after authorization and before an executor or transfer starts, never put a value, image, transcript or key in a record, and use `cleanup` for stop, mute and teardown so an unwritable store cannot block privacy teardown. `scripts/test-jarvis-audit.js` and `scripts/test-jarvis-redact.js` pin each.

### Adapters

- Do add a provider as one row in `Providers.js`; a row for another driver refuses `brain=driver`. `scripts/test-jarvis-providers.js` pins it.
- Do send only through the shared owner; a driver adds no transport, timer, SDK or credential reader, and a speech adapter sends only through the `net` owner it is handed. `scripts/test-jarvis-brain-anthropic.js` and `scripts/test-jarvis-brain-openai.js` pin it.
- Do pass every history item through `Policy.release` on every request, look the key up through `Secrets.lookup` at first need and zero it on close, and call `net.assertKeyTarget` before any keyring lookup. `scripts/test-jarvis-brain-openai.js` and `scripts/test-jarvis-live.js` pin each.
- Never read a provider's error text; fail `brain=stream-error` with the body unread, and never yield a tool call before the stream completes. `scripts/test-jarvis-brain-anthropic.js` pins both.
- Do keep a sent, cancelled turn in history unanswered, answer every call it left before the next turn, and refuse `brain=context-limit` at the history bound; never summarise or drop a turn. `scripts/test-jarvis-engine.js` pins each.
- Do create every per-conversation resource inside the engine and release all in `end()`; a changed brain, provider, account, policy or `cloudVision` setting ends the conversation, and a chained transcription partial never reaches the brain. `scripts/test-jarvis-engine.js` pins it.
- Do start a harness program with its tools off and the bridge as its only server; fail the turn when its init shows another tool or server, and end the conversation on any wire-order defect. `scripts/test-jarvis-claude.js` and `scripts/test-jarvis-codex.js` pin each.
- Do end a Pi conversation when any tool but the bridge's starts. Pi still starts the MCP servers the user configured, with its own environment, so never put the bridge's token in Pi's environment. `scripts/test-jarvis-pi.js` pins both.
- Do route a harness program's own approval request as `{kind: "approval"}` through the gate's `harness` executor, never offer harness rows to a brain, and refuse a program command outside the trusted profile. `scripts/test-jarvis-codex.js`, `scripts/test-jarvis-copilot.js` and `scripts/test-jarvis-policy.js` pin it.
- Never call `Policy.decide` or an executor from the tool bridge; every action goes through `router.route`. The bridge asks the conversation engine for content release and uses its bound grants. `scripts/test-jarvis-bridge.js` and `scripts/test-jarvis-mcp.js` pin it.
- Do judge every Verify payload with `Accounts::released` and write `Audit.before` first; never let a login-status reply count as Verified, and never rebind a stored key to a selected target. `scripts/test-jarvis-account-verify.js` pins each.
- Do bind a duplex session's key to its origin, send every frame through `channel.send`, and end the conversation on any fault; no other voice takes over. `scripts/test-jarvis-live.js` and `scripts/test-jarvis-session.js` pin it.

### Executors

- Do register through `Executors.register`, once, after your probe passes; `available()` returns literal `true` or the offer is withdrawn. `scripts/test-jarvis-router.js` and `scripts/test-jarvis-desktop-tools.js` pin both.
- Never offer a shell tool from a command-presence probe; only a real kernel probe that answers `available` permits an offer, and there is no unsandboxed fallback ([D074](../decisions/D074-jarvis-kernel-sandbox.md)). `scripts/test-jarvis-sandbox.js` and `scripts/test-jarvis-shell.js` pin it.
- Never add a policy table, a confirm method, a second child owner or a command timer in an executor. `scripts/test-jarvis-router.js` refuses a tool named confirm; `Child.run` bounds every command.
- Do take the schema and the result's source label from `Tools.TABLE`; a late result never taints a newer turn. `scripts/test-jarvis-tools.js` and `scripts/test-jarvis-router.js` pin both.
- Do ask the router's authority check immediately before you act, rejudge every path field with a fresh `Denied` snapshot, and open through `bin/lib/anchored.js` with `O_NOFOLLOW`; never judge containment by string prefix. `scripts/test-jarvis-input.js`, `scripts/test-jarvis-files.js` and `scripts/test-jarvis-denied.js` pin each.
- Do answer `completed` only on a read-back; a command that may have acted is `unknown`. `scripts/smoke/rows/jarvis-desktop.sh` and `scripts/test-jarvis-desktop-tools.js` pin it.
- Do answer `completed`, `failed` or `unknown` with a sentence that begins with its status; never copy an exception body. `scripts/test-jarvis-router.js` and `scripts/test-jarvis-shell.js` pin it.
- Never run `hyprctl dispatch` from the daemon; send a `request` and let the shell dispatch. Never add a second launch path; `shell/Commons/DesktopLaunch.js` is the launcher's rule, pinned by `scripts/test-desktop-launch.js`.
- Do run every command through `Child.run` under `setpriv --pdeathsig KILL` with only the variables the command table lists, send text through stdin never argv, and end model text with `--` before an option parser. `scripts/test-jarvis-desktop-tools.js` and `scripts/test-jarvis-child.js` pin each.
- Do wrap every start in `Audit.before`, with names never values; a refused write starts nothing. `scripts/test-jarvis-router.js`, `scripts/test-jarvis-audit.js` and `scripts/test-jarvis-redact.js` pin it.
- Do count a capture or an input against the live thinking turn the user started, keep working files in a private 0700 runtime directory removed before the turn ends, and refuse before any capture when a route's command is missing ([D073](../decisions/D073-jarvis-release-and-origin-bound-keys.md)). `scripts/test-jarvis-vision.js` pins each.
- Do stamp every adapter callback with its effect's identity; a callback that does not match the live operation and generation is discarded, and a late one never rearms a closed owner. `scripts/test-jarvis-session.js` and `scripts/test-jarvis-session-runner.js` pin both.
- Never let a vendor browser session inherit the user's HOME, profile or signed-in state, and label browser results `web`. `scripts/test-jarvis-browser.js` pins both.

## The canonical example

`shell/plugins/vgs.jarvis/backend/Audio.js` for a new child owner, `AnthropicMessages.js` for a wire driver, `ClaudeCode.js` for a harness adapter and `DesktopSession.js` for an executor. Copy them.

## Revisit when

Quickshell provides a stronger child lease, capture moves to a process the shell cannot own, or an echo implementation can verify both module acquisition and routing before admitting simultaneous capture and playback. A provider speaks neither a compatible wire nor a harness program, VGS gains an npm route, a vendor permits a subscription outside its own program, or a speech provider reports played-frame timing. An executor cannot supply typed arguments or trusted target facts, kernel confinement cannot mediate an operation, or Hyprland exposes atomic target-bound input.

## Not governed

What leaves the machine, which is [jarvis-outbound.md](jarvis-outbound.md); the test world, which is [validation.md](validation.md).
