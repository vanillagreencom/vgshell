# Jarvis chained engine adapters

Covers: shell/plugins/vgs.jarvis/backend/ChainedEngine.js, shell/plugins/vgs.jarvis/backend/jarvisd.js, scripts/test-jarvis-engine.js, scripts/fixtures/jarvis/engine.js

The [chained engine](jarvis-engine.md) owns each conversation. This contract defines its ports, account selection and speech adapter interface.

## Engine seam

The daemon creates the chained engine with the router and the audit writer on the first hello. It installs the following ports alongside [D084's duplex speech port](../decisions/D084-duplex-speech-engine-sessions.md). The snapshot selects `chained`; voice and account selection must choose the duplex engine before the daemon can start it.

| Member | Session or Audio consumer |
|---|---|
| `configure(settings)` | The daemon, before each snapshot. The gate rises only on `ready`. |
| `observe(state)` | The daemon's publish callback. A generation change ends the conversation. |
| `images()` | Whether the conversation's brain row, or the next conversation's, takes images. [Vision](jarvis-vision.md#release-and-route) routes a capture by it; a tool result's image reaches the brain beside its text. |
| `brain` | Session's brain port: `send`, `cancel`, `close`, and the router's `outcome`. |
| `collect(e, done, failed)` | Session's collect port. |
| `captureSink(e)`, `playbackSource(op)` | Audio's speech sink and source factories. |
| `playback(port)` | Wraps Audio's playback port to read the flush report. |
| `close()` | Lease loss. |

## Selection

`configure` answers `{kind: "ready"}` or `{kind: "unconfigured", cause}`. It never answers with a partial plan.

| Step | Source | Cause when it fails |
|---|---|---|
| Speech | The first ready row of the speech table, in table order | `speech=no-adapter`, or the first row's own cause |
| AI model | The `brain` setting through `Accounts::resolve`: a keyring reference, a local server or a Codex directory, with no vendor command or port read | `brain=unselected`, `brain=account-unavailable`; a keyed account or key reader failure is `brain=accounts-unreadable` with that failure as `detail` |
| Model | The provider declaration's Verify probe model in `AccountProviders.js`; a subscription's program uses its own default | `brain=model-required` for a key or local account |
| Driver and recipient | The `Providers.js` row; its base origin is the brain recipient. `codex-app-server` is the [Codex harness](jarvis-codex.md), created with the account's directory, the generation and the daemon's bridge and gate | A row outside the driver table is an invariant error |
| Guidance class | `local` for a loopback base, else `text` | none |

Any other failure during selection is a defect and throws. A speech row is `{select({settings, accounts, directories})}`; `directories` are the hello's roots. A ready answer carries the row's recipient entries and `open({net, recipients})`. The table ships the [local row](jarvis-local-speech.md#selection), so a daemon without local setup stays unconfigured with `speech=local-not-set-up`. The ElevenLabs row extends this table and uses the same selection path. Plan § 3.10's `voiceProvider`, when it exists, chooses above this table and above the duplex engine.

## Speech adapter contract

| Member | Contract |
|---|---|
| `transcribe(frames)` | `frames` is an async iterable of `speech`-labelled Policy items holding PCM Buffers. It yields `{kind: "partial", text, rev}` with strictly increasing `rev`, then one `{kind: "final", text}`. `return()` abandons the utterance. |
| `speak(sentences)` | `sentences` is an async iterable of released Policy items holding `Speakable` sentences, with their reply's labels. It yields Audio's object-mode chunks: `{pcm, sentence: {text, frames, words?}}`, then `{pcm}` for the rest of that sentence. It ends when its input ends. |
| `close()` | Releases the adapter's own resources. A network adapter sends only through the `net` owner it received, with the labels of the items it carries. |

A partial only draws: it reaches Session's collecting turn. Only the final reaches the brain. A partial whose revision does not increase, an event of another shape and a transcription that ends without a final are failures. While the capture is open, a failure closes it as `provider-disconnected`. After the capture closed, it reaches the collecting turn as Session's `collect-failed`. An utterance no collection holds reports only an `audio-fault` line.
