# The README is held to its sources by offline checks

Read before touching README § Install, README § Plugins, a plugin README's screenshot, `docs/images/plugins/`, `scripts/check-readme.js`, `scripts/readme-install.sh` or `scripts/readme-shots.sh`.

## The approach

Every install line in the README belongs to a channel `scripts/check-readme.js` knows, the plugin table is generated from each shipped plugin's manifest, and the README's sections are a named set in order. Every first-party plugin README shows a screenshot cut from a sandbox shot by one table, `docs/images/plugins/shots.tsv`, and one command, `scripts/readme-shots.sh`; `scripts/check-readme-images.py` holds READMEs, table and files to each other. `scripts/readme-install.sh` runs each install command in a container against what users get from `main`.

## Why

A hand-written plugin table and a hand-cropped screenshot drift from the plugins the moment one changes. The curl, nix and checkout commands read `main` on GitHub, so the runner checks what users get, not the working tree. The sandbox draws every shot with the default theme, so an image never shows the live desktop.

## Rules

- Never add an install line without a channel in `scripts/check-readme.js`; a line that fits none is refused, planted by `scripts/test-check-readme.js`.
- Never hand-edit README § Plugins; run `node scripts/check-readme.js --write-plugins`. The `plugin` rule fails on one byte of difference.
- Do keep the README's `## ` sections to the named set in order; the `heading` rule refuses another.
- Never state a runtime floor in the README; `vgshell run` checks it and `scripts/check-packaging.js` holds the recipes.
- Do add a new image as a row in `shots.tsv`, then run `scripts/readme-shots.sh`; never put a file under `docs/images/plugins/` without a row. `scripts/check-readme-images.py` refuses it, as a `tools` row of `scripts/validate`.
- Do show at least one image whose name starts with the plugin's id, so a README copied from another plugin fails the `no-own-image` rule.
- Never exceed the image budget `scripts/check-readme-images.py` holds, and never place an image beside its README, which the installer would ship.
- Do run `scripts/readme-install.sh` by hand before a release; it needs podman and the network, and an unpublished need exits 77, which is not a pass.

## The canonical example

`shell/plugins/vgs.tray/README.md` and its row in `shots.tsv`: one description, one image named by the plugin's id, one command that made it. Copy the pair.

## Revisit when

A channel's install command stops reading `main`, or a screenshot needs a theme other than the default.

## Not governed

What each channel ships, which is [distribution.md](distribution.md); the README's own sections, which the docs-writing skill's README example holds.
