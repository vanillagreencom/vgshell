# D007: Install runs no plugin code

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active (system-package declaration → [D035](D035-manifest-requirements.md))
**Research**: —

**Decision**: Installing a plugin clones it, judges its manifest and moves the directory into place. It runs no plugin code, no git hook and no privileged step. A plugin lands disabled, except a plugin with a bar widget and no `optIn`, which the next scan places and enables after the install command has said that its code will run at once and asked.

**Why**: Running a repository's script at install hands it the user's privileges. Landing disabled, or asking first, gives the user a review step before any plugin code runs. The install rows of `scripts/test-vgshell.sh` install from local bare repositories with hooks off.

**Rejected**: Running a plugin's install script or hooks at install. A one-line convenience that opens a supply-chain class.

**Revisit when**: The marketplace adds a signed install step.
