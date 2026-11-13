# D134: Forwarding consent can cover one named live session

[← Decision Index](INDEX.md)

**Date**: 2026-11-12

**Status**: Active

**Research**: [VGS-2329](https://linear.app/vanillagreen/issue/VGS-2329/jarvis-voice-speaks-jarviss-answer-to-a-request-it-handed-over-or), Jarvis delegated owner decision 1794525723, covering KEN-4953 decision 1794525438

**Refines**: [D120](D120-satellite-forward-through-the-package.md), only the scope of sending confirmation; its package transport and unproved-caller rules remain active

**Decision**: One explicit confirmation in the originating conversation may authorize sending requests from one named live Jarvis Voice session to the named main. The confirmation names that session and main. Every forward outside that confirmed session keeps its own confirmation. A session grant ends on Stop forwarding, ordinary conversation close, a new conversation, a changed home or main, or daemon restart. Retained brain history restores no grant. The package checks the originating session's live lease before first delivery of an unsent request under the grant. Sending consent approves no requested operation and proves no speaker identity. Destructive actions, money and outside commitments keep their own approvals at main.

**Why**: Jarvis, acting as the owner's delegate, authorized one confirmation for this exact live-session scope on 2026-11-12. A session identity and live lease let that scope end locally without leaving unsent requests with authority after the conversation ends. A receipt can be lost after delivery, so revocation cannot recall work already admitted to send.

**Rejected**: Per-forward confirmation for every request does not implement the delegated decision. A grant retained with brain history, or a best-effort end call without a live lease, can authorize another session or a first delivery after its originating session ends.

**Revisit when**: The owner changes the allowed forwarding scope, the package gains another first-delivery route, or a live session can survive daemon restart with independently proved identity and revocation.
