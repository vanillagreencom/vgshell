# One judge of how a tree was installed

Read before touching `vgshell self`, the curl installer, `bin/lib/self.js`, or a tree's `current` link.

## The approach

`bin/lib/self.js` is the one judge of how a tree was installed, a checkout, a package, a curl install or a Nix tree, and whether it is behind. `vgshell self update` changes only a tree VGS laid out itself, a checkout or a curl install, and refuses a package or Nix tree. The curl installer and the self-update write only under a directory VGS owns, under one lock, `.self.lock`, and only a verified archive reaches it; the installer starts no shell, writes no unit and edits no `hyprland.lua`.

## Why

A checkout fast-forwards with no diff and no question because VGS is the program the user runs, not third-party code. An AUR helper reports a `-git` package behind only when its recipe's version changes, so VGS reads `vgshell-git`'s commit itself. `Hyprland --version` aborts when `XDG_RUNTIME_DIR` is unset, so the installer probes under a private empty one. VGS publishes no release signing key yet, so the update checks the sha256 alone.

## Rules

- Do make every git call in `bin/vgshell` and hand `self.js` the facts; `self.js` decides.
- Never refuse the command on a failed step; it becomes `error`, exit 0, and the fields read before it stay. `scripts/test-vgshell-self.sh` pins it.
- Do keep three trees after an update: the new one, the one the command ran from, and the one the running shell started from. `scripts/test-vgshell-self.sh` pins it with a control that removes the running shell's tree.
- Do fetch with no hook, no prompt, no askpass and no `FETCH_HEAD`, ended at 10 s, and run `bin/vgshell-migrate` from the updated tree after an update.
- Do keep the whole installer one brace group, so a cut download runs nothing. `scripts/test-install-sh.sh` truncates it at every line end and every byte of the last 256.
- Do refuse root, a non-Linux host, a system package and a foreign `~/.local/bin/vgshell` before writing. `scripts/test-install-sh.sh` pins each.
- Do fetch with `curl --proto =https --tlsv1.2`, match the one `SHA256SUMS` line, replace `current` by rename only, and never remove a version directory from the installer. `scripts/test-install-sh.sh` pins each.
- Do run required installs through the staged tree's presenter and package runner, which owns elevation. `scripts/test-install-sh.sh` pins it with a fake presenter.
- Do hold the installer's floor and package tables to `bin/vgshell` and `config/requirements.json`; the drift rows of `scripts/test-install-sh.sh` pin them.
- Do accept `VGS_RELEASE_API` only with a loopback or `file://` base in a test run. `scripts/test-install-sh.sh` and `scripts/test-vgshell-self.sh` pin it.

## The canonical example

`scripts/test-vgshell-self.sh`: one case per method, one per outcome, a control that removes the running shell's tree. Copy its shape when a method or an outcome is added.

## Revisit when

A release signing key is published, and the update then checks the signature.

## Not governed

What each channel ships, which is [distribution.md](distribution.md).
