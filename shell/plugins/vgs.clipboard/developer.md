# Clipboard developer reference

[secrets.md](../../../docs/architecture/secrets.md) holds the plugin's rules and the tests that enforce them.

## The history

`SUPER+CTRL+V` opens the history on the focused monitor. The entries are on the left: pinned entries first, then the newest. The selected entry shows on the right. Typing goes to the search field and shows only the entries that hold the text, in upper or lower case. The list shows 50 entries. The search reads the first 8192 characters of an entry.

A paste puts the entry on the clipboard, closes the history and sends the paste key to the application: Ctrl+Shift+V to a terminal, Ctrl+V to any other application. VGS identifies the window through its desktop entry, including NoDisplay entries. For a custom window class, the core matches the window process's executable to a desktop entry's command basename. When VGS cannot name the application, it sends no key and shows a message. The entry stays on the clipboard for the user to paste.

Up, Down, Page Up, Page Down, Ctrl+Home and Ctrl+End move the selection. Escape clears the search, then closes the history.

## Copy, paste and cut

`SUPER+C`, `SUPER+V` and `SUPER+X` are the shortcuts `vgs.clipboard:copy`, `vgs.clipboard:paste` and `vgs.clipboard:cut`. A press reads what has the keyboard from the core and sends it one key through Hyprland's send-shortcut dispatch, with no window named. The key reaches a VGS layer such as the launcher, which is never Hyprland's active window.

| Target | Copy | Paste | Cut |
|---|---|---|---|
| A terminal, or the window of a VGS floating TUI | Ctrl+Shift+C | Ctrl+Shift+V | no key |
| Another application, or a VGS surface | Ctrl+C | Ctrl+V | Ctrl+X |

Ctrl+Shift+C and Ctrl+Shift+V are the clipboard keys of kitty, Ghostty, foot and Alacritty at their default settings. A window whose class and executable match no desktop entry receives no key, and a message shows. A wrapper command whose `TryExec` alone names the real application remains unresolved: Quickshell 0.3.1 has no public `TryExec` accessor. `ClipboardHistory.chord` holds the table.

## Recorded copies

Text up to 1 MiB and an image up to 16 MiB. A larger copy is not recorded.

A copy that offers both plain text and an image is recorded as text.

A copy is not recorded when its source marks it as secret with `x-kde-passwordManagerHint`. KeePassXC and other password managers set that mark. A copy from a program that sets no mark is recorded like any other copy.

The history is in `clipboard/` under `~/.local/state/vgshell/`, or under `$XDG_STATE_HOME/vgshell/` when that is set. Only the user can read it. It is not encrypted. An image file is deleted when no entry uses it.

## IPC

| Name | Argument | Reply |
|---|---|---|
| `toggle` | none | Opens or closes the history. |
| `rows` | a filter | `{ images, total, rows }`, at most 50 rows. |
| `paste`, `copy`, `pin`, `delete` | an entry id | `ok`, or a `refused:` line. |
| `clear` | none | Clears the history. Pinned entries stay. |

The history's shortcut is `vgs.clipboard:toggle`, `SUPER+CTRL+V` by default. The IPC form, with the function's name and argument in place of `rows` and the filter:

```text
vgshell ipc call vgs.clipboard invoke rows 'png'
```
