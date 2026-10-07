# D075: Consumer setup automates what it can

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-1042](https://linear.app/vanillagreen/issue/VGS-1042), [VGS-683](https://linear.app/vanillagreen/issue/VGS-683)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md), [D061](D061-no-manual-commands.md)

**Decision**: VGS automates every setup step it can. A step only the user can take is allowed when Settings gives a clear path for it. This includes an API key or token, an access setting, a sign-in, or installing an app. Settings gives the field or action, where to get the key or complete the step, and what feature it unlocks. Secrets use the masked field and storage required by [D061](D061-no-manual-commands.md). An existing feature that needs unsupported developer setup without this user path remains an extra, such as developer-console app registration with no supported setup path. Its manifest `extras` entry stays off by default and absent from Settings. Its README documents it under "Extras (not supported)". Do not add a new hidden extra.

**Why**: Only the user can grant account access or create some credentials. A clear Settings path lets the user complete those steps and use the feature. Hiding every feature that needs a key removes features the user can reasonably set up. Unsupported developer setup without a user path still leaves the user unable to complete setup.

**Rejected**: Requiring every consumer feature to work without a user-made key, access setting or sign-in. VGS cannot automate consent or credentials that only the user controls.

**Revisit when**: An unsupported extra gains a supported Settings path, or VGS can automate a step that currently needs the user.
