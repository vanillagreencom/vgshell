# A Jarvis brain or speech adapter is one owner per conversation that sends through the door

Read before adding or changing a brain, a speech engine, a provider row, a harness program adapter or the tool bridge.

## The approach

A brain is a wire adapter, a provider row in `shell/plugins/vgs.jarvis/backend/Providers.js` served by one driver that sends only through `WireBrain.js`, or a harness adapter, the vendor's unmodified program with every built-in tool off and the tool bridge as its only tool server ([D079](../decisions/D079-brains-wire-and-harness-adapters.md)). One engine object per conversation owns the adapter, the brain, the release grants and the heard prefix, and ends them all when the generation changes ([D089](../decisions/D089-jarvis-chained-engine-and-heard-prefix.md)). Every item leaves through release, then audit, then the one network door. An account's Verified comes only from one explicit inference request the user started, judged by the same release owner.

## Why

A harness tool left on would bypass the policy gate, and vendor terms allow a subscription only through the unmodified program. A provider error body can echo content or credentials, so it is cancelled unread. A chained brain has no server item to truncate, and bytes written overstate what was heard, so the heard prefix travels as a separate labelled item and history is never rewritten. A login-status or model-list reply proves an account exists, not that it answers, so only generated text verifies it.

## Rules

- Do add a provider as one row in `Providers.js`; a row for another driver refuses `brain=driver`. `scripts/test-jarvis-providers.js` pins it.
- Do send only through the shared owner; a driver adds no transport, timer, SDK or credential reader, and a speech adapter sends only through the `net` owner it is handed. `scripts/test-jarvis-brain-anthropic.js` and `scripts/test-jarvis-brain-openai.js` pin it.
- Do pass every history item through `Policy.release` on every request, look the key up through `Secrets.lookup` at first need and zero it on close, and call `net.assertKeyTarget` before any keyring lookup. `scripts/test-jarvis-brain-openai.js` and `scripts/test-jarvis-live.js` pin each.
- Never read a provider's error text; fail `brain=stream-error` with the body unread, and never yield a tool call before the stream completes. `scripts/test-jarvis-brain-anthropic.js` pins both.
- Do keep a sent, cancelled turn in history unanswered, answer every call it left before the next turn, and refuse `brain=context-limit` at the history bound; never summarise or drop a turn. `scripts/test-jarvis-engine.js` pins each.
- Do create every per-conversation resource inside the engine and release all in `end()`; a changed brain, provider, account, policy or `cloudVision` setting ends the conversation. `scripts/test-jarvis-engine.js` pins it.
- Do answer selection as `{kind: "ready"}` or `{kind: "unconfigured", cause}`; any other failure throws. Do yield partials with a rising `rev` then one final, and never let a partial reach the brain. `scripts/test-jarvis-engine.js` pins each.
- Do start a harness program with its tools off, the bridge as its only server, hooks disabled, user settings unloaded, an allowlisted environment and no session persistence; fail the turn when its init shows another tool or server, and end the conversation on any wire-order defect. `scripts/test-jarvis-claude.js` and `scripts/test-jarvis-codex.js` pin each.
- Do route a harness program's own approval request as `{kind: "approval"}` through the gate's `harness` executor, never offer harness rows to a brain, and refuse a program command outside the trusted profile. `scripts/test-jarvis-codex.js` and `scripts/test-jarvis-policy.js` pin it.
- Never call `Policy.decide`, an executor or the approval path from the bridge; every call goes through `router.route`, the token travels only in the shim's environment, and `Mcp.js` alone parses MCP. `scripts/test-jarvis-bridge.js` and `scripts/test-jarvis-mcp.js` pin each.
- Do judge every Verify payload with `Accounts::released` and write `Audit.before` first; never let a login-status reply count as Verified, and never rebind a stored key to a selected target. `scripts/test-jarvis-account-verify.js` pins each.
- Do bind a duplex session's key to its origin, send every frame through `channel.send`, and end the conversation on any fault; no other voice takes over. `scripts/test-jarvis-live.js` and `scripts/test-jarvis-session.js` pin it.

## The canonical example

`shell/plugins/vgs.jarvis/backend/AnthropicMessages.js`: a driver that owns only its wire encoding and event judge and sends through `WireBrain.js`. Copy it for a wire driver; `ClaudeCode.js` for a harness.

## Revisit when

A provider speaks neither a compatible wire nor a harness program, VGS gains an npm route, a vendor permits a subscription outside its own program, or a speech provider reports played-frame timing.

## Not governed

The release judge and the door themselves, which is [jarvis-outbound.md](jarvis-outbound.md); what a tool executor does with a call, which is [jarvis-executors.md](jarvis-executors.md).
