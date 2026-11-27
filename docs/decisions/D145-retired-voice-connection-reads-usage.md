# D145: A retired voice connection reads only its owed usage

[← Decision Index](INDEX.md)

**Date**: 2026-11-26

**Status**: Active

**Research**: [VGS-2751](https://linear.app/vanillagreen/issue/VGS-2751)

**Supersedes**: [D121](D121-conversation-transport-lifetimes.md), only its "Closing ends ... voice connections" clause, for a Realtime connection that still owes usage. Its brain history, release grant, capture and renewal policy remain active.

**Decision**: When a session leaves a Realtime connection on close, conversation end, renewal, failure or brain failover, the connection stays open only while it owes usage for a response it asked for or an input it committed. It is receive-only and reads only that usage: it sends nothing, plays no audio, captions nothing, commits no turn and holds no capture. It closes once nothing is owed, when it closes itself, or when RESPONSE_WAIT_MS passes. Lease loss and daemon close close it at once and write what it still owes as unread rows.

**Why**: OpenAI bills a reply and a transcription whether or not the session still listens, so closing at once leaves the spend cap and the usage report short exactly when sessions end early. D121 rejected keeping voice connections alive because they would carry brain context and microphone, network or action authority across closes. A usage read carries none of these: the connection sends no frame, reaches no Session state and no brain, and lives at most RESPONSE_WAIT_MS past the close.

**Rejected**: Closing at once and writing each owed call unread. That hides countable usage that the provider still sends.

**Revisit when**: OpenAI reports a session's usage through another route after the connection closes, or a retired connection needs to send or reach Session state.
