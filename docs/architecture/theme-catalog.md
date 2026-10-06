# The catalog is judged offline as the packages it installs

Read before touching `themes/catalog/`, its index, the catalog check, a catalog install, or a wallpaper download.

## The approach

First-party themes live in `themes/catalog/` with one judged index. Each entry installs as an ordinary installed package with a marker, passes the same judge a shipped package does, and installs with no network ([D038](../decisions/D038-judged-theme-catalog.md)). Wallpapers stay out of git: an entry pins an archive by size and SHA-256, the download streams and verifies against the pin, lands by rename, and holds a download lock that is never the theme lock. Every catalog and shipped package meets the readability floor of [design-system.md](design-system.md).

## Why

A catalog update ships with VGS itself and runs no code at apply, so update asks nothing where a git update asks. A download of tens of megabytes on the theme lock would hold every list and apply behind it. The pin, not the URL, is what makes bytes acceptable, and it bounds the preview cache to one image per archive.

## Rules

- Do judge every index entry and package through `ThemeLogic.acceptCatalogIndex` and `acceptCatalogEntry`; `bin/vgshell-theme-judge catalog-check` runs from `scripts/validate` for `themes/`, and `scripts/test-vgshell-theme-judge.js` pins it.
- Never ship a curated file on a `runsCode` target, a file no target writes, or a symlink in a catalog entry; `catalog-check` refuses each.
- Do install a catalog package as an ordinary installed package with a marker; `.git` wins over the marker for origin. `scripts/test-vgshell-catalog.sh` pins it.
- Never let install or update delete a package or its edits: an occupied name is refused, and a hand-edited install refuses update as `modified`. `scripts/test-vgshell-catalog.sh` pins both.
- Do run `recover` under the theme lock before any install verb changes anything. `scripts/test-vgshell-catalog.sh` pins it.
- Do keep `palette` and `mode` in the index equal to the package's resolved values, so a card draws without reading the package. `scripts/test-theme-logic.js` pins it.
- Do keep every package readable at the floors `ThemeLogic.readabilityShortfalls` states, with the fix inside the package's own `theme.json`; a theme no fix makes readable is not listed. `scripts/check-theme-contrast.js` refuses a shortfall.
- Do accept download bytes by the pin, refuse another size or digest, leave no part, and require HTTPS for the URL and every redirect. `scripts/test-theme-download.js` pins each.
- Do hold `download.lock` for the fetch and the theme lock for the land only, and judge the install again at the land. `scripts/test-vgshell-wallpapers.sh` pins both.
- Do land only regular `backgrounds/<image>` members under the ceiling, and never take a `backgrounds/` the download did not place. `scripts/test-theme-download.js` and `scripts/test-vgshell-wallpapers.sh` pin both.

## The canonical example

`themes/catalog/flexoki-light/`: a light package with its readability fix inside its own `theme.json`, a pinned archive in the index, and no curated code file. Copy it.

## Revisit when

The catalog outgrows the repository, catalog packages need code files with no template, or a watched CLI cannot reload from an atomic copy.

## Not governed

The package judge and the install verbs' git handling, which is [themes.md](themes.md); the wallpaper state the shell draws from, which is [theme-backgrounds.md](theme-backgrounds.md).
