# D022: A theme apply keeps managed links in an application's own theme directory

[← Decision Index](INDEX.md)

**Date**: 2026-09-27
**Status**: Active (watched directories → [D030](D030-managed-copies-for-watched-theme-directories.md); settings keys → [D024](D024-theme-apply-sets-one-theme-key-in-an-application-settings-file.md))
**Research**: [VGS-468](https://linear.app/vanillagreen/issue/VGS-468)
**Refines**: [D021](D021-theme-apply-writes-beside-each-destination.md)

**Decision**: For an application with a themes or extension directory, apply keeps one symlink per entry into the state `theme/` directory and never edits the application's configuration. A path holding anything but that exact link is skipped as occupied and never replaced; disable removes only managed links, and an owned directory only when empty.

**Why**: Nothing but an apply makes a symlink into the state `theme/`, so the link is its own proof of ownership and no marker file is needed. The swap replaces `theme/` whole, so the link never needs rewriting.

**Rejected**: Copying the rendered file into the application's directory, where a user-edited copy cannot be told from the apply's own; and a marker file, a second file to keep in step.

**Revisit when**: An application refuses to follow a symlink in its theme directory, or a target needs a file not among its files in `theme/`.
