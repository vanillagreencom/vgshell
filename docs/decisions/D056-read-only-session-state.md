# D056: Plugins read the session's lock state without lock authority

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-617](https://linear.app/vanillagreen/issue/VGS-617)
**Refines**: [D012](D012-core-owns-lent-objects.md)

**Decision**: The shared `session` capability exposes one read-only boolean, `locked`. The exclusive `lock` capability keeps unlock authority.

**Why**: Lending `lock` to a reader grants unlock authority and breaks the lock screen's exclusive hold. The one existing owner supplies the state with no polling and no registry. `scripts/test-session-lock.sh` holds the provider.

**Rejected**: The lock plugin owning the Wayland lock with services looking each other up. VGS keeps lock ownership in the core under D012.

**Revisit when**: A reader must observe a lock another process owns, or the compositor supplies a session-state API.
