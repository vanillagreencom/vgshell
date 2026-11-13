# D134: Forwarding consent can cover one named live session

[← Decision Index](INDEX.md)

**Date**: 2026-11-12

**Status**: Active

**Research**: [VGS-2329](https://linear.app/vanillagreen/issue/VGS-2329/jarvis-voice-speaks-jarviss-answer-to-a-request-it-handed-over-or), Jarvis delegated owner decision 1794525723, covering KEN-4953 decision 1794525438, lifecycle clarification 1794531396 and settled package contract 1794532313

**Refines**: [D120](D120-satellite-forward-through-the-package.md), only the scope of sending confirmation; its package transport and unproved-caller rules remain active; [D070](D070-jarvis-action-policy.md), only the audit write before a Stop forwarding start

**Decision**: One explicit confirmation in the originating conversation may authorize sending requests from one named live Jarvis Voice session to the named main. The confirmation names that session and main. Every forward outside that confirmed session keeps its own confirmation and unchanged individual record. Only a session-scoped record adds the session identity, grant scope and live lease. Stop forwarding and the Stop key revoke the grant, and Stop forwarding starts through Audit cleanup so an unwritable audit store cannot block revocation; another explicit confirmation in that same live conversation may create a new grant with a new lease path. The session filename stays fixed inside a fresh private directory for each grant. Ordinary close, a new conversation, a changed home or main, or daemon restart ends the grant. Retained brain history restores none. A handover of main's Jarvis session in the same home does not end it. The package checks the lease once before every send attempt, including retries. A request without a receipt proving delivery is unsent; after Stop it closes with a Stop cause and is not retried. Delivered work is not recalled. Sending consent approves no requested operation and proves no speaker identity. Destructive actions, money and outside commitments keep their own approvals at main.

**Why**: Jarvis, acting as the owner's delegate, authorized this exact live-session scope on 2026-11-12 and clarified Stop and retries in decision 1794531396. The live lease ends sending authority locally. A new lease path prevents a renewed grant from restoring old queued requests. The session filename lets the package bind the file to its session, while the fresh parent distinguishes grants. Individual consent needs none of that extra authority, so its existing contract remains sufficient. Missing delivery evidence cannot justify another send after Stop. A full audit store must not keep sending authority alive.

**Rejected**: Per-forward confirmation for every request does not implement the delegated decision. A grant retained with brain history, a reused lease path, or a best-effort end call without a live lease can restore revoked sending authority.

**Revisit when**: The owner changes the allowed forwarding scope, the package gains another send route, or a live session can survive daemon restart with independently proved identity and revocation.
