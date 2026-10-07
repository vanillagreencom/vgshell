# D022: A theme apply proves ownership of application entries and edits only theme selection keys

[← Decision Index](INDEX.md)

**Date**: 2026-09-27

**Status**: Active

**Research**: [VGS-468](https://linear.app/vanillagreen/issue/VGS-468), [VGS-471](https://linear.app/vanillagreen/issue/VGS-471), [VGS-492](https://linear.app/vanillagreen/issue/VGS-492)

**Refines**: [D021](D021-theme-apply-writes-beside-each-destination.md)

**Decision**: An application target declares each entry as a link or a copy. A link proves ownership by its exact destination in the state `theme/` directory. A copy lands by rename in the application's watched directory and proves ownership by bytes equal to the previous or new render. Apply skips an occupied path; disable removes only managed entries and an owned directory only when empty. A target may also declare theme selection keys in an existing settings file. Every apply repairs those keys, preserves every other byte, refuses an ambiguous edit and never creates an absent file. Disable leaves the keys in place.

**Why**: Each managed form proves itself without a marker file. Links follow the whole `theme/` swap, but an application's watcher may miss a changed link target. A renamed copy lets that watcher read the new bytes while byte equality protects user edits. A theme selection key makes the application read the managed theme again after its picker changes the selection. Settings files can hold credentials, so the edit must stay confined to the declared keys.

**Rejected**: Copies without an ownership check, marker files that need a second file kept in step, and touching a link to make a watcher reload. Leaving selection to the user lets a picker disconnect the managed theme. Parsing and reserialising the whole settings file loses comments, order and quoting.

**Revisit when**: An application cannot reload an atomic copy, a copy needs another file mode, a target needs a file outside its render, or a theme selection uses a format or source the narrow edit cannot handle.
