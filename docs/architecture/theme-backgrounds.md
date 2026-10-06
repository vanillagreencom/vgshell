# One wallpaper state the runner writes and the plugin reads

Read before touching `vgshell theme backgrounds`, `backgrounds.json`, `bin/lib/theme-backgrounds.js`, or the background surface.

## The approach

Wallpaper state is one file, `backgrounds.json`, that `bin/lib/theme-backgrounds.js` alone writes and the `vgs.themes` plugin's `WallpaperState.qml` alone reads. It holds a current image and an optional per-screen map that a theme apply clears ([D039](../decisions/D039-per-screen-wallpaper-map.md)). The background surface exists only while an image is drawn, and the user's own images live in the user folder, never in a package ([D025](../decisions/D025-no-theme-override-layer.md)).

## Why

A wallpaper another program draws must not be covered by a bare background colour, so no image means no surface. An absent map entry is the same-everywhere state, so nothing needs seeding. A file replaced under its name must reload, so an image is stamped by size and modification time. Qt's directory watcher follows a link to its target, so the plugin watches the state file, not the `background` link.

## Rules

- Do make `bin/lib/theme-backgrounds.js` the only writer and `WallpaperState.qml` the only reader. `scripts/test-vgshell-backgrounds.sh` and `scripts/smoke/rows/themes.sh` pin both.
- Do count only `.png`, `.jpg` and `.jpeg` regular files, never a symlinked image or `backgrounds/` itself. `scripts/test-vgshell-backgrounds.sh` pins it.
- Do clear `screens` on apply so the package shows on every screen; `next`, `previous` and `set` keep it. `scripts/test-vgshell-backgrounds.sh` pins it.
- Do stamp an image by size and modification time, and decode at the screen's device-pixel size. `scripts/smoke/rows/themes.sh` and `hidpi.sh` pin both.
- Never map the background surface while no image is current, unreadable, or the state file is not the runner's. `scripts/smoke/rows/themes.sh` pins it.
- Never ask Hyprland whether an output exists; the judge checks the name's shape alone, so an entry can wait for a disconnected monitor.
- Do choose and read the image before anything moves, so an unreadable image refuses the apply before the theme file changes. `scripts/test-vgshell-backgrounds.sh` pins it.

## The canonical example

The `set` verb of `bin/lib/theme-backgrounds.js`: judge the name, read the image, then write the state whole. Copy its order for a new verb.

## Revisit when

A screen needs a setting beyond its image, or an apply must keep a screen's own image.

## Not governed

The wallpaper archives and their download, which is [theme-catalog.md](theme-catalog.md); the runner's queue, which is [theme-capability.md](theme-capability.md).
