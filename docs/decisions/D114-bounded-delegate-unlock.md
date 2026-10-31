# D114: The session user can opt into bounded delegate unlock

[← Decision Index](INDEX.md)

**Date**: 2026-10-22

**Status**: Active

**Research**: [VGS-1995](https://linear.app/vanillagreen/issue/VGS-1995)

**Refines**: [D062](D062-native-lock-and-polkit-plugins.md) for intentional temporary release only; the native lock, PAM path, restore behavior and protection of a held lock stay active.

**Decision**: A default-off setting permits every caller reaching session IPC to request one non-renewable unlock of 1 through 60 seconds. SessionLock owns expiry and relocks on holder disposal; any normal lock request ends access. Every relock that ends a release without its own request takes the lock cause `release-end` ([D109](D109-idle-path-one-owner-per-stage.md)'s closed set), so it shows the lock screen; an idle lock keeps its idle cause. Before it unlocks, SessionLock writes a release marker under `XDG_RUNTIME_DIR`, which it removes once the relock is confirmed; a shell that starts and finds one locks at once, so a restart, a reset, an update or a crash during a release relocks at the next start. The external tool owns step approval and always requests relock when the step ends. VGS authenticates neither Jarvis nor individual approval.

**Why**: An approved delegate needs desktop access without stopping the shell and its daemon. QML IPC supplies no protected caller identity. This is an easier password-free route for any application running as the user, whose applications can also edit the permission. Expiry requires a running, responsive shell: while no shell runs after a stop during a release, the desktop stays open until the next start; stalls can delay relock, and suspend with Lock before sleep off can extend exposure. These accepted limits remain visible in Settings and user help.

**Rejected**: Stopping or replacing the shell tears down its daemon. Permanent unlock lacks expiry; a plugin-owned timer disappears on teardown; a caller-supplied identity proves no authority. A protected identity broker and an independent expiry supervisor require separate scope.

**Revisit when**: Same-user isolation, relock while no shell runs or during stalls, or access longer than the approved cap is required.
