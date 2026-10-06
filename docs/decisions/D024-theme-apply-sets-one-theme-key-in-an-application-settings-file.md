# D024: A theme apply sets one theme key in an application's own settings file

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-471](https://linear.app/vanillagreen/issue/VGS-471)
**Refines**: [D022](D022-theme-apply-keeps-managed-links-in-application-directories.md)

**Decision**: A target may name one key in its application's settings file. Apply sets exactly that key on every landing apply, byte-preserving, with JSON parsed whole and TOML or YAML edited line by line. It refuses a file it cannot edit without guessing, never creates an absent file, and leaves the key in place on disable.

**Why**: The key is what makes a coding-agent CLI read the linked theme, and a theme picker or a hand edit moves it away. These files hold credentials, so the edit is as narrow as the file allows and an absent file is never created.

**Rejected**: Leaving the selection to the user, as D022 does for editors: a `/theme` pick moves the key and the CLI never reads the theme again. Parse-and-re-serialise loses comments, order and quoting, and the repository ships no TOML or YAML library.

**Revisit when**: A CLI names its theme in a form the edit refuses, such as JSON with comments, or takes it from somewhere other than a settings key.
