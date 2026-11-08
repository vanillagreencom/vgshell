# D121: Brain history and voice connections have separate lifetimes

[← Decision Index](INDEX.md)

**Date**: 2026-11-05

**Status**: Active

**Research**: [VGS-2209](https://linear.app/vanillagreen/issue/VGS-2209/jarvis-talk-flow-superj-opens-and-closes-a-free-conversation-hold-is-a)

**Supersedes**: [D089](D089-jarvis-chained-engine-and-heard-prefix.md), only brain lifetime across Session generations and the assumption of one voice connection per conversation. Its heard-prefix, release and action policy remain active.

**Decision**: The engine retains the exact suspended brain across ordinary Talk closes. Wire brains keep their native history in memory; harness brains keep their idle child and opaque context. Closing ends capture, voice connections and release grants. Resume waits for cancellation, rejudges retained labels and binds tool access to the new generation. New conversation, the 40-turn bound, relevant selection changes including account, model or home, and shell or daemon restart start fresh. At the bound, the next attempted turn continues with fresh context and an explanation. A live speech owner renews an expiring voice connection without changing Session generation or brain context.

**Why**: Closing Talk must preserve exact context without carrying microphone, network or action authority across closes. Keeping an ephemeral native child preserves context that a new child cannot reconstruct exactly without transcript conversion or new persistence. Provider connection expiry must not decide the brain's lifetime.

**Rejected**: Reseeding a new brain from transcript text loses native tool context. Keeping voice connections or release grants alive to retain that context gives them the wrong lifetime. A disk history store changes the required fresh start on restart.

**Revisit when**: A native harness offers exact context export and import without new persistence, or the owner changes restart or history semantics.
