# Key Hints developer reference

The service registers the shortcut `vgs.keyhints:toggle`, bound to `SUPER+SLASH` by default.

The host's summon opens the window: `vgshell ipc call shell summon window vgs.keyhints '{}'`. The payload is `{}` or empty. Any other payload refuses the summon with `refused: open-failed=vgs.keyhints`.

The window adds no store, key editor or conflict rule of its own. Its rows are the manager's plugin rows, the binds the Hyprland layer is written from. A key change goes through the manager to the plugin's `plugins[].keys` in `shell.json`. Each row is the `BindField` of `qs.Ui`, the bind row the Settings page's Keys row is built on, so both draw the key capture's conflict hint for the bind they name. A refused key reads as the shared reply line of `qs.Commons`, `Reply.line`, which the Settings page uses too.

A bind a plugin asks for while an earlier plugin by id holds the same keys has a row with the hint, and Hyprland does not bind it. An unbound shortcut has a row with no keys, and Hyprland does not bind it.

`scripts/smoke/rows/keyhints.sh` is the window's validation row in the nested sandbox. It reads the rows against the binds Hyprland reports with a `vgs.` description, the conflict hint under a key a harness bind also uses, the filtered rows after typing, a refused key with the unchanged `shell.json`, the same key change here and on the Settings page, and an unbound key.
