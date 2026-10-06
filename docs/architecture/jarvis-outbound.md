# Every byte that leaves the machine passes one release judge and one door

Read before touching Jarvis release, the network door, a key lookup, a presence probe, or any path by which content or a credential could leave the daemon.

## The approach

Release is judged per labelled item against the whole frozen recipient set of the conversation, brain and speech together, and a summary keeps every contributing label ([D073](../decisions/D073-jarvis-release-and-origin-bound-keys.md)). One network door, `shell/plugins/vgs.jarvis/backend/net.js`, opens every socket, attaches a key only to its exact stored origin and refuses every redirect. A key is read in process at first need through `Secrets.lookup`, zeroed after use, and never enters a child, argv, file, log, status value or wire; a presence probe reads no key. A transport error carries no URL, header, secret or provider text. A new recipient set is created on any provider, account or policy change, and old grants fail against it.

## Why

Speech receives what the brain already got, so a per-destination check leaks across providers. A redirect or a custom endpoint can hand a stored key to the wrong origin. `secret-tool search` retrieves secrets even without an unlock request, so presence uses the Secret Service `SearchItems` call. A name that merely starts with a loopback address is not loopback, so `localhost` is pinned to the IPv4 loopback with no DNS.

## Rules

- Do send every request and frame through `net.create`; never open a socket in an adapter or the daemon. `scripts/test-jarvis-net.js` observes every socket creator.
- Do label content with `Tools.refine(...).source` or the speech and context producers, never a model-supplied label, and keep every contributing label on a summary. `scripts/test-jarvis-release.js` pins both.
- Do create a new recipient set on any provider, account or policy change; old grants fail against it. `scripts/test-jarvis-release.js` pins it.
- Never attach a key whose stored origin differs from the request origin, never follow a redirect, and never let adapter metadata carry a credential header or change `Host`. `scripts/test-jarvis-net.js` pins each.
- Do call `net.assertKeyTarget` before any keyring lookup, and normalise a new endpoint through `net.endpoint` before storing its reference. `scripts/test-jarvis-net.js`, `scripts/test-jarvis-live.js` and `scripts/test-jarvis-release.js` pin them.
- Never let a retrieved key enter a child, argv, file, log, status or shell wire; clear the Buffer after use. `scripts/test-jarvis-secrets.js` scans state, HOME and the runtime files for a synthetic key.
- Never read a key in a presence probe, never pass an inherited credential variable to a helper, and never report helper stdout or stderr; a helper failure is a fixed keyed cause. `scripts/test-jarvis-secrets.js` pins each.
- Never put a URL, header or secret in a transport error. `scripts/test-jarvis-net.js` asserts their absence.
- Do run the release judge before sanitised text leaves the machine, and report an overflow by stopping that output; never fall back to raw brain text. `scripts/test-jarvis-release.js` and `scripts/test-jarvis-speakable.js` pin both.
- Do release each harness turn against the set before the handoff; a harness vendor owns its own sockets. `scripts/test-jarvis-claude.js` pins it.

## The canonical example

`shell/plugins/vgs.jarvis/backend/net.js`: the door, with `GptLive.js` as the adapter that follows it, key bound before lookup, every frame through `channel.send`, the key zeroed once the handshake headers exist. Copy that order.

## Revisit when

A supported provider requires redirects, a new credential placement, or a transport the door cannot mediate.

## Not governed

How an adapter is structured, which is [jarvis.md § Adapters](jarvis.md#adapters); where a secret may sit anywhere else in VGS, which is [secrets.md](secrets.md).
