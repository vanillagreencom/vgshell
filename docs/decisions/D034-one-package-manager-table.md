# D034: One package-manager table in the core, and the shell never elevates for a package

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-516](https://linear.app/vanillagreen/issue/VGS-516), the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511) § 2

**Decision**: `shell/Core/PackageManagers.js` is the one package-manager table, read by every package flow and every manifest judge. A package change runs only in a terminal the user watches, and the table names no elevation command.

**Why**: A shell process that elevated would hold root with no one watching, and separate per-flow lists disagree on argv. `scripts/test-vgshell-pkg-table.js` holds the table.

**Rejected**: PackageKit. It is absent on Arch by default and has no AUR, Flatpak or mise.

**Revisit when**: A supported manager cannot be expressed as argv steps, or the shell must change a package with no terminal open.
