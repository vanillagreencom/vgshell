# A Jarvis tool executor registers once, asks the gate, and reports only what it read back

Read before adding or changing a Jarvis tool executor: a desktop, file, input, shell, browser or screen tool.

## The approach

Every tool a Jarvis brain may call is an executor registered through one seam, `Executors.register`, only after its own readiness probe passes, and every call reaches it through one serial router, `shell/plugins/vgs.jarvis/backend/ToolRouter.js`, which judges with fresh facts through `Policy.decide`, audits before the start, and owns the only confirmation identity ([D070](../decisions/D070-jarvis-action-policy.md), [D082](../decisions/D082-jarvis-approval-bound-to-the-action.md)). An executor takes its schema and its result's source label from `Tools.TABLE`, never from model prose, rejudges every path against a fresh `Denied` snapshot through held descriptors, counts its work against the live turn the user started, and answers `completed` only when it read the effect back. A command that may already have acted reports `unknown`, never `failed`. The desktop changes it needs go to the shell as requests, so `shell/Core/Dispatch.js` stays the one dispatch judge.

## Why

A model can pick an action from untrusted file, page or screen content, so no executor may hold a second policy table or a confirm method; a serial hold removes Jarvis's own path to its own confirm key. A path judged by string can be swapped between the judgement and the open, so the executor rejudges at execution and walks held descriptors. A dispatcher answers `ok` without acting, and an application may keep its window open to ask about unsaved work, so only a read-back proves an effect. Registration proves nothing about confinement, so a shell tool is offered only after a real kernel probe answers.

## Rules

- Do register through `Executors.register`, once, after your probe passes; `available()` returns literal `true` or the offer is withdrawn. `scripts/test-jarvis-router.js` and `scripts/test-jarvis-desktop-tools.js` pin both.
- Never offer a shell tool from a command-presence probe; only a real kernel probe that answers `available` permits an offer, and there is no unsandboxed fallback ([D074](../decisions/D074-jarvis-kernel-sandbox.md)). `scripts/test-jarvis-sandbox.js` and `scripts/test-jarvis-shell.js` pin it.
- Never add a policy table, a confirm method, a second child owner or a command timer in an executor. `scripts/test-jarvis-router.js` refuses a tool named confirm; `Child.run` bounds every command.
- Do take the schema and the result's source label from `Tools.TABLE`; a late result never taints a newer turn. `scripts/test-jarvis-tools.js` and `scripts/test-jarvis-router.js` pin both.
- Do ask the router's authority check immediately before you act, rejudge every path field with a fresh `Denied` snapshot, and open through `bin/lib/anchored.js` with `O_NOFOLLOW`; never judge containment by string prefix. `scripts/test-jarvis-input.js`, `scripts/test-jarvis-files.js` and `scripts/test-jarvis-denied.js` pin each.
- Do answer `completed` only on a read-back; a command that may have acted is `unknown`. `scripts/smoke/rows/jarvis-desktop.sh` plants a no-wait read-back, and `scripts/test-jarvis-desktop-tools.js` holds the outcome control.
- Never run `hyprctl dispatch` from the daemon; send a `request` and let the shell dispatch. Never add a second launch path; `shell/Commons/DesktopLaunch.js` is the launcher's rule, pinned by `scripts/test-desktop-launch.js`.
- Do run every command through `Child.run` under `setpriv --pdeathsig KILL` with only the variables the command table lists, send text through stdin never argv, and end model text with `--` before an option parser. `scripts/test-jarvis-desktop-tools.js` and `scripts/test-jarvis-child.js` pin each.
- Do wrap every start in `Audit.before`, with names never values; a refused write starts nothing. `scripts/test-jarvis-router.js`, `scripts/test-jarvis-audit.js` and `scripts/test-jarvis-redact.js` pin it.
- Do count a capture or an input against the live thinking turn the user started, keep working files in a private 0700 runtime directory removed before the turn ends, and refuse before any capture when a route's command is missing ([D093](../decisions/D093-jarvis-screenshots.md)). `scripts/test-jarvis-vision.js` pins each.
- Do stamp every adapter callback with its effect's identity; a callback that does not match the live operation and generation is discarded, and a late one never rearms a closed owner. `scripts/test-jarvis-session.js` and `scripts/test-jarvis-session-runner.js` pin both.
- Do answer `completed`, `failed` or `unknown` with a sentence that begins with its status; never copy an exception body. `scripts/test-jarvis-router.js` and `scripts/test-jarvis-shell.js` pin it.
- Never let a vendor browser session inherit the user's HOME, profile or signed-in state, and label browser results `web`. `scripts/test-jarvis-browser.js` pins both.

## The canonical example

`shell/plugins/vgs.jarvis/backend/DesktopSession.js`: probe-first registration, every change as a shell request, one read-back judge, outcome sentences. Copy it.

## Revisit when

An executor cannot supply typed arguments or trusted target facts, kernel confinement cannot mediate an operation, or Hyprland exposes atomic target-bound input.

## Not governed

What leaves the machine, which is [jarvis-outbound.md](jarvis-outbound.md); how a brain or speech adapter is written, which is [jarvis-adapters.md](jarvis-adapters.md); the daemon's own lifetime and wire, which is [jarvis.md](jarvis.md).
