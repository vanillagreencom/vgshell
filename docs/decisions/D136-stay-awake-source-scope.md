# D136: Stay awake scopes holds at the core idle source

[← Decision Index](INDEX.md)

**Date**: 2026-11-16

**Status**: Active

**Research**: [VGS-2576](https://linear.app/vanillagreen/issue/VGS-2576)

**Refines**: [D116](D116-screensaver-inhibits-answered-by-a-core-helper.md), only the scope of the Stay awake source. Application ScreenSaver inhibits retain their all-watch scope.

**Decision**: `IdleRegistry.qml` disables each stage's monitor for the union of live source scopes. Stay awake always holds sleep, optionally holds display stages and optionally holds the VGS lock stage. Callers name a stage explicitly; core infers none from plugin identity or timeout. Power persists its intent and original absolute end through its existing configuration writer and restores one instance-bound hold. Every Stay awake hold retains logind's `what=idle` inhibitor, including when VGS's lock stage remains enabled.

**Why**: Keeping the computer awake must allow its displays and VGS idle lock to run independently. Core monitor enablement preserves input and ticket revocation without a stage owner swallowing events. logind's inhibitor covers its entire `IdleAction`, which may sleep the computer; Keep locking on controls VGS's lock stage and exempts no external logind idle action.

**Rejected**: Gates at individual stage owners or replaying idle events on release require separate re-arm state. Releasing logind's idle inhibitor to allow its own lock action also permits its idle sleep action. A second persistence store duplicates Power's existing confirmed configuration writer.

**Revisit when**: Another pause source needs a different scope, or logind can inhibit idle sleep separately from its other idle actions.
