# D113: The session user can opt into bounded delegate unlock

[← Decision Index](INDEX.md)

**Date**: 2026-10-22

**Status**: Active

**Research**: [VGS-1995](https://linear.app/vanillagreen/issue/VGS-1995)

**Refines**: [D062](D062-native-lock-and-polkit-plugins.md) for intentional temporary release only; the native lock, PAM path, restore behavior and protection of a held lock stay active.

**Decision**: A default-off setting permits every caller reaching session IPC to request one non-renewable unlock of 1 through 60 seconds. SessionLock owns expiry and relocks on holder disposal; any normal lock request ends access. The external tool owns step approval and always requests relock when the step ends. VGS authenticates neither Jarvis nor individual approval.

**Why**: An approved delegate needs desktop access without stopping the shell and its daemon. QML IPC supplies no protected caller identity. This is an easier password-free route for any application running as the user, whose applications can also edit the permission. Expiry requires a running, responsive shell: whole-shell failure while deliberately unlocked can lose relock, stalls can delay it, and suspend with Lock before sleep off can extend exposure. These accepted limits remain visible in Settings and user help.

**Rejected**: Stopping or replacing the shell tears down its daemon. Permanent unlock lacks expiry; a plugin-owned timer disappears on teardown; a caller-supplied identity proves no authority. A protected identity broker and an independent expiry supervisor require separate scope.

**Revisit when**: Same-user isolation, recovery across whole-shell failure or stalls, or access longer than the approved cap is required.
