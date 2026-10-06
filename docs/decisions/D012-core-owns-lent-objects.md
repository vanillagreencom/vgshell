# D012: The core owns every session-wide object and lends it per instance

[← Decision Index](INDEX.md)

**Date**: 2026-09-23
**Status**: Active
**Research**: —

**Decision**: The core creates each one-per-session object, shortcuts, IPC targets, the notification server, the session lock, the polkit agent, and lends it to a plugin instance through `shell/Core/Capabilities.qml`. Every registration returns a disposer the instance's teardown runs. A D-Bus role exists only while a plugin holds it, and lock and polkit are separate exclusive capabilities.

**Why**: One owner per object removes the collision class and makes disabling a plugin a complete release. On-demand D-Bus roles keep a shell without those plugins out of the user's own daemons' way. `scripts/smoke/rows/capability-release.sh` reads the lending record back.

**Rejected**: Plugins creating these objects themselves. Two plugins or a user daemon collide, and nothing releases the object on disable. One `session` capability was rejected because it forces one plugin to own lock and polkit both.

**Revisit when**: Quickshell releases the notification D-Bus name when its server object is destroyed, or a plugin needs a lent object two plugins share at once.
