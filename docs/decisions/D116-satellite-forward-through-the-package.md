# D116: A satellite forwards a request through the home's Jarvis package

[← Decision Index](INDEX.md)

**Date**: 2026-11-03

**Status**: Active

**Research**: [VGS-2189](https://linear.app/vanillagreen/issue/VGS-2189)

**Refines**: [D105](D105-jarvis-home-folder.md), whose `lane-mail` stays the one program of a home a brain's action starts on the computer that runs the main Jarvis

**Decision**: On a satellite, a computer whose Main Jarvis host names another computer, a brain's confirmed `fleet.forward` action runs the session command of the kendex Jarvis package in the home, `.agents/skills/jarvis/scripts/jarvis-session forward`, by argv in the home. It is the one other program of a home a brain's action starts. The package owns the SSH connection to the main, the outbox, the retries and the answer. VGS hands it one record: the request's text and the audit reference, time and method of the owner's confirmation. The daemon opens no socket for it and writes no mailbox. The record names no speaker. A spoken request goes exactly as a typed one does, so voice approval of an owner-only step waits on a VGS path that knows who spoke, and until one exists the main asks the owner in Slack.

**Why**: kendex owns the satellite contract as it owns the mailbox, so an SSH client or outbox in VGS would drift from the package's record of what was sent. A Talk key or a cloud voice's delegation proves only the route a request came by, not who spoke, and VGS authenticates no caller ([D114](D114-bounded-delegate-unlock.md)).

**Rejected**: A forward that opens a `voice-request: caller=owner` line for a Talk-started request. Anyone at the keyboard can press Talk, so the line would claim an owner no VGS path proved.

**Revisit when**: The package moves its forward route to another program or transport, VGS gains a path that knows who spoke, or a satellite needs another program of the home.
