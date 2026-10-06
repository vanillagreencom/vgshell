# D075: Consumer features need no developer setup

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-683](https://linear.app/vanillagreen/issue/VGS-683)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md), [D061](D061-no-manual-commands.md)

**Decision**: A feature a user cannot use without registering an app, creating a key or token, or visiting a developer console does not ship as a consumer feature. It ships as an extra: a manifest `extras` entry switched by a schema-less setting that defaults to off, hidden from Settings, and documented only under "Extras (not supported)" in the plugin's README. `PluginLogic.activeManifest` is the one filtered view every reader uses.

**Why**: Most users will never create a Slack app, and VGS has no server to hold an OAuth client secret, so a one-click Connect is impossible. Deleting a working feature loses code the owner uses daily, and keeping it visible asks everyone else for setup they cannot do. `scripts/test-plugin-extras.js` holds the filter.

**Rejected**: A published Slack app with OAuth. The client secret would have to ship in the package or on a server VGS does not have.

**Revisit when**: Slack offers a token-free photo source, VGS gains a backend that can hold a client secret, or an extra gains enough users to deserve a one-click consumer path.
