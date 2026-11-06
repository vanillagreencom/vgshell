# D124: Comment-only source changes select text checks

[← Decision Index](INDEX.md)

**Date**: 2026-11-05

**Status**: Active

**Research**: [VGS-2334](https://linear.app/vanillagreen/issue/VGS-2334/validation-a-comment-only-qml-or-js-diff-gets-text-only-selection-and)

**Refines**: [D100](D100-validation-selects-by-inputs.md), extending its text-only selection to proven comment-only QML and JavaScript changes under `shell/`. All other selection rules remain active.

**Decision**: A readable diff containing only text files and existing QML or JavaScript files under `shell/` whose code stays identical after `scripts/qml_source.py` `blank_comments` removes comments selects text checks plus the keyboard, pointer-cursor and smoke edit-needle checks. Comment whitespace may change; code, literal contents and code whitespace must stay identical. The comparison preserves block-comment line terminators that can change behavior. Changes to `// keyboard-path:`, `// pointer-cursor-exempt:` or `// focus-indicator:` directives take input-based selection. Added, removed, renamed or unreadable source files, fixture QML and self-reading JavaScript tests also take input-based selection. An explicit QML run does not take the text-only grant; full and release runs keep every check.

The smoke edit-needle check reads literal match-once needles from existing smoke-edit producers, including values assembled from variables or heredocs, and from `scripts/smoke/harness.sh`, `scripts/smoke/tree.sh` and every smoke row's inline Python. It rejects a comment that overlaps or repeats a needle. A target with any edit needle the check cannot read as a literal string keeps input-based selection through actual producers and existing input reach, with no per-file exemption list or general-language parser.

**Why**: Ordinary shell comments do not change the code a product row runs, but smoke edits can depend on their spelling and static checks can read directives. Keeping those checks and retaining input-based selection where edit needles are unreadable lets comment edits avoid product runs without hiding comment-dependent smoke edits. The existing source reader owns comment recognition so selection and the needle check do not invent competing definitions.

**Rejected**: Keeping extension-only text selection, which runs product checks for ordinary comment edits; and skipping every check for comment-only source changes, which misses directive changes and comment-dependent smoke edits.

**Revisit when**: A selected-out row reads another comment directive, a supported QML or JavaScript construct defeats the shared comment reader, or a comment-only change causes a product regression that these checks miss.
