# D029: Chromium's theme colour is a managed policy written by one narrow passwordless writer

[← Decision Index](INDEX.md)

**Date**: 2026-09-28

**Status**: Active

**Research**: VGS-491

**Context**: [D027](D027-chromium-follows-gtk-mode.md) left Chromium, Google Chrome, Microsoft Edge and Brave to follow the theme in GTK mode only. In Classic mode, the owner's setting, the browser keeps its own colour. The one colour input outside the browser is the managed policy `BrowserThemeColor`, a JSON file under a root-owned directory: `/etc/chromium/policies/managed/`, `/etc/opt/chrome/policies/managed/`, `/etc/opt/edge/policies/managed/` or `/etc/brave/policies/managed/`. Omarchy writes it through a root-owned helper and one NOPASSWD sudoers rule: `bin/omarchy-theme-set-browser`, `bin/omarchy-theme-set-browser-policy`, `install/helpers/browser-policy.sh` and `etc/sudoers.d/omarchy-theme-browser` in basecamp/omarchy. The owner reversed D027 and asked for Omarchy's approach.

**Decision**: The `chromium` target writes the theme background as six lowercase hex digits into the state directory, and its hook, run on every apply, hands them to `vgs-browser-policy`. That writer is `bin/vgsh-browser-policy`, installed root-owned together with one sudoers rule that lets a user run it as root with no password and with six hex character classes as the only argument. The Arch and Fedora packages ship it at `/usr/bin/vgs-browser-policy` with the rule `/etc/sudoers.d/vgs-theme-browser`, which grants every local user; the writer prints that rule itself, so the grammar has one spelling. A packaged install has no setup step. A home install has no package, so one owner-run command, `vgsh theme browser-policy install`, installs the writer at `/usr/local/bin/vgs-browser-policy` and the rule `/etc/sudoers.d/vgs-browser-policy`, which grants the installing user alone. As the user, the writer exits at once when every managed directory already holds the canonical file, runs its own path as root through `sudo -n`, and has each running browser read its policy again with `--refresh-platform-policy`. As root, it pins `PATH`, hardens each directory's chain to `root:root 0755`, creates the directory of an installed browser, and replaces `color.json` by rename, `root:root 0644`, holding `{"BrowserThemeColor": "#rrggbb", "BrowserColorScheme": "device"}`. Apply never prompts: until the writer is on `PATH`, the target is skipped with `setup-absent`.

**Rationale**:

- The owner wants the browser to follow the theme in Classic mode, which only the managed policy reaches.
- The rule's argument grammar is the whole grant: the caller chooses a colour, never a path, a policy or a second argument.
- `sudo -n` never waits for a password, so a background apply and a session with no terminal behave as a terminal apply does.
- The target's `setup` key names the writer, so a machine without the one-time step reports `setup-absent` instead of a failed hook on every apply.
- A package install already runs as root, so it can install the writer and its rule with no step left for the user. A package cannot know which user will log in, so its rule grants every user, sudoers' `ALL`. A narrower group would leave a user outside it with the setup read as done and every apply's hook failing. The grant carries only a colour: six hex classes, and the root half writes one fixed JSON file.
- The user half elevates its own path, so each copy matches the rule that names it. The two rule files have different names, so a package installed over a home setup conflicts with no file.

## Where VGS differs from Omarchy

| Omarchy | VGS | Why |
|---|---|---|
| Two scripts: an unprivileged setter and a privileged writer. | One file with both halves, chosen by the effective user. | The directory list, the policy text and the canonical test have one owner. |
| The writer falls back to `pkexec`, or prompts through `sudo` in a terminal. | `sudo -n` only; a missing rule fails the hook. | The owner's rule: apply never prompts. |
| The package ships the writer at `/usr/bin` and a `%wheel` rule in `/etc/sudoers.d/omarchy-theme-browser`. | The Arch and Fedora packages ship `/usr/bin/vgs-browser-policy` and `/etc/sudoers.d/vgs-theme-browser`, whose rule grants every user. A home install's one-time setup grants the user who ran it. | A package cannot know the user, and the setup report cannot tell a user outside `wheel` that the hook will fail; the grant carries only a colour. An install with no package has no root step but the user's own. |
| The installer and browser installer create and purge the policy directories. | The writer hardens each chain and creates the directory of a browser installed on the system `PATH` on every write. | VGS installs no browsers, so no install step knows when a browser arrives. |
| `install -T` writes the file. | A staged file in the same directory is renamed over `color.json`. | A browser never reads a half-written policy. |
| The colour comes from a theme's `chromium.theme` RGB file. | The colour is the `color.background` token. | Every VGS package carries the token; no package file is needed. |
| Brave Origin is refreshed. | It is not listed. | It is an Omarchy package, not a browser VGS detects. |

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| GTK mode only, D027 | The browser keeps its own colour in Classic mode. |
| A symlink from the policy directory to a file in the state directory | Every process of the user could then write any managed policy, not only the colour. |
| A privileged writer asked through `pkexec` on each apply | A background apply has no one to answer the prompt. |

**Revisit When**: Chromium reads a theme colour from a file or setting the user owns, or a second policy key needs writing.

**Verification**: `scripts/test-vgsh-browser-policy.sh` runs the writer against a temporary prefix, its root half under `unshare -r`, with controls for the argument, the canonical skip, the chain check, the mode check, the hardening, the planted directory, the created directories, the refresh, the elevated path and the package rule. `scripts/check-packaging.js`, `scripts/check-install-tree.sh`, `scripts/arch-packages.sh` and `scripts/fedora-container.sh` hold the packages to shipping the writer and its rule. `scripts/test-vgsh-browsers.sh` covers the target's `setup-absent` skip, its hook argument and `vgsh theme browser-policy install`; `scripts/test-theme-render.js` covers the `setup` key.

**References**: [D027](D027-chromium-follows-gtk-mode.md), [D024](D024-theme-apply-sets-one-theme-key-in-an-application-settings-file.md), [theme-browsers.md](../architecture/theme-browsers.md)
