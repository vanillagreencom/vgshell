# Clipboard developer reference

[secrets.md](../../../docs/architecture/secrets.md) holds the plugin's rules and the tests that enforce them.

## The history

`SUPER+CTRL+V` opens the history on the focused monitor. The entries are on the left: pinned entries first, then the newest. The selected entry shows on the right. Typing goes to the search field and shows only the entries that hold the text, in upper or lower case. The list shows 50 entries. The search reads the first 8192 characters of an entry.

A paste puts the entry on the clipboard, closes the history and sends the paste key to the application: Ctrl+Shift+V to a terminal, Ctrl+V to any other application. VGS reads which application has the keyboard from its desktop entry. When VGS cannot name the application, it sends no key and shows a message. The entry stays on the clipboard for the user to paste.

Up, Down, Page Up, Page Down, Ctrl+Home and Ctrl+End move the selection. Escape clears the search, then closes the history.

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

The shortcut is `vgs.clipboard:toggle`, `SUPER+CTRL+V` by default. The IPC form, with the function's name and argument in place of `rows` and the filter:

```text
vgshell ipc call vgs.clipboard invoke rows 'png'
```
