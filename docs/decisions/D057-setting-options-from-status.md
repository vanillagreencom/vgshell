# D057: String settings take runtime options from their plugin's status

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-616](https://linear.app/vanillagreen/issue/VGS-616)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D037](D037-plugin-status.md)

**Decision**: A string setting may name a `choices` status entry of its own plugin through `optionsFrom`. The service publishes stable ids with labels, the Settings page draws them, and a configured id that leaves the offers stays configured and shows as unavailable.

**Why**: A manifest cannot list the devices, accounts or models found at run time, the Settings page must stay manifest-only, and removing an offer must not delete the user's stored value. `scripts/test-plugin-logic.js` pins the rule.

**Rejected**: Runtime enum options. An enum refuses a configured value once it leaves the offers.

**Revisit when**: A setting needs several selected values, or discovery outgrows the bounded status list.
