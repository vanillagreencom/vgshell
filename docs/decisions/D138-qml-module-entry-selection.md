# D138: A QML module entry reaches the files that name it

[← Decision Index](INDEX.md)

**Date**: 2026-11-17

**Status**: Active

**Research**: [VGS-2618](https://linear.app/vanillagreen/issue/VGS-2618).

**Refines**: [D100](D100-validation-selects-by-inputs.md)'s static shell-load reach through QML module definitions and [D137](D137-capability-provider-selection.md)'s ordinary static loads. D137's provider edges and [D117](D117-reuse-rows-on-recorded-passes.md)'s pass reuse remain.

**Decision**: `smoke_loads_read` derives module-entry edges from `qmldir` declarations and source import names. A type or JavaScript resource reaches the files that name that entry in an imported or implicit namespace, then the rows that name those files. Importing a module alone does not observe every entry. An attributable `qmldir` hunk reaches the union of its added, removed and changed entries' readers on both sides, including a version, file or public/internal change. A new entry reaches only its named readers. Qt's local namespace qualifiers, implicit directory imports, singleton and internal declarations determine which entry a name can resolve to; uncertain resolution retains all possible readers. Comments and import declarations are not uses; literal names in strings retain conservative reach. Explicit file imports, direct row inputs, core rows and row dependencies remain. A module-wide directive change retains all module importers; an unreadable module or unattributable hunk selects every row. A shared harness hunk still selects every row when it changes top-level work or a helper every row uses.

**Why**: A scene can use one part of `qs.Ui` or `qs.Commons` without observing every part the module exports. Treating a consulted `qmldir` as an observation of every entry confuses name availability with use. Existing type loads provide the edges; the module definition must preserve their distinction. Narrowing removes over-reach under the declared-input rule. Neither a time target nor a timing reading removes a reached row, and all timing measurements and verdicts stay unchanged.

**Rejected**: Keeping every module importer as a reader of every entry, or keeping a separate list of entry consumers. The first retains over-reach; the second can disagree with Qt's source declarations. This grant does not narrow top-level JavaScript data, module-wide directives or unknown loads.

**Applies to**: At design HEAD `6a94fc5c3f96173840ae5a82f1d9cda9ded76a40`, VGS-2370 selects 135 rows today, every listed row except `bluetooth-agent`, `portal-accent` and `supervise`. Its after prediction is 101 rows: the 100 named-source rows in the issue's source-only native projection, plus `overlays` as a direct `qmldir` input. Its entry change affects `ListItem`; its padding change affects `ContentRow`, including transitive readers. VGS-2475 selects 136 today and is predicted to keep those same rows, every listed row except `portal-accent` and `supervise`: its `PluginLogic.js` import and top-level constant changes retain whole-file reach through actual core importers. Its new Commons entry alone reaches the `Commons.TuiArguments` reader in Agent Warden's `ViewLogic.js`, plus direct `qmldir` inputs. VGS-2616's `SessionLock.qml` keeps D137's 63 rows from its declared capability consumers. Final-base native `--list` must confirm or correct each after prediction before landing. These predictions claim no elapsed-time improvement.

**Revisit when**: An unselected scene catches a regression in a module entry, supported Qt module syntax cannot be attributed, or another source of module-wide effects makes a named-entry edge insufficient.
