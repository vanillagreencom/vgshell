# Clipboard history

Covers: shell/plugins/vgs.clipboard/**, scripts/test-clipboard-history.js, scripts/test-clipboard.py, scripts/smoke/rows/clipboard.sh

The clipboard history plugin, `vgs.clipboard`: who owns the watcher and the history, how the overlay reaches them, which copies are never recorded and how a paste picks its key. The plugin's [README](../../shell/plugins/vgs.clipboard/README.md) holds the user's view.

## Owners

- The service is the one owner of the watcher and the one writer of the history. `entries` in `Service.qml` is the history. The service reads the store file once, as it is built, and writes it after each change.
- The overlay holds no history. It asks the service for the rows of its filter and for each change, through capability `ipc` and `shell.ipc.call`: `rows`, `paste`, `copy`, `pin`, `delete` and `clear`. The host builds the overlay on a summon and destroys it on a hide, so it reads at most 50 rows each time it opens or its filter changes. Plugin status is not used: the core copies a status value to every instance and the Settings page, and a status value has a size ceiling. A second reader of the store file is not used: it would be a second parser, and it would lag the service's own list.
- The manifest sets `optIn` ([plugin-manifest.md](plugin-manifest.md)), so the plugin is off until it is enabled: no service and no watcher exist, and no copy is read, before the user turns it on. Disabling keeps the store.
- `ClipboardHistory.js` holds every decision about the history and its rows. `helper/clipboard.py` runs `wl-paste` and `wl-copy` and is the one program that writes under the store directory.
- Each helper run but the watcher's goes through one queue in the service, one at a time. The service names a file for `drop` as that run starts, only while no entry names it. A capture writes an image's bytes under a private name and renames the file to the entry's id before it prints the entry's line, so an entry in the history names a whole file.

## Capture

- One watcher runs: `setpriv --pdeathsig TERM -- wl-paste --watch python3 helper/clipboard.py <store> capture`. `wl-paste --watch` runs the command once for each copy, the first for the copy on the clipboard as the watcher starts, so the service needs no second read at its start. Read in `scripts/smoke/rows/clipboard.sh` with wl-clipboard 2.3.0 on host cachy on 2026-10-04: a copy made before the plugin was enabled was the first entry.
- The parent-death signal ends the watcher with the shell, however the shell ends. The plugin kills no process by name. A watcher that ends while it is wanted starts again after 5 s. Read in `scripts/smoke/rows/clipboard.sh` on host cachy on 2026-10-04: the row ended the watcher by its PID, read no watcher, then one with another PID, and the next copy was recorded.
- The helper records text when the copy offers plain text: `text/plain`, with or without a parameter, or `TEXT`, `STRING` or `UTF8_STRING`. The text is the data `wl-paste` hands the command on stdin, read as UTF-8; other text is not recorded. With no plain text, the helper reads the first offered `image/` type with a second `wl-paste`. Markup such as `text/html` is not plain text, since a browser offers it beside a copied image. A copy with neither is not recorded.
- The helper closes its stdin before that second read. `wl-paste` hands the command the copy's first offered type on stdin, and `wl-copy` serves one transfer at a time. While a copy larger than the pipe waits unread there, `wl-copy` sends the second `wl-paste` nothing: the image is not recorded and the source answers no other request until the helper ends. A pipe holds 65,536 bytes (pipe(7)) unless its writer grows it, and the `cat` that `wl-copy` sends a copy with does: read with `F_GETPIPE_SZ` on host cachy on 2026-10-04, GNU coreutils 9.11 grew it to 524,288 bytes. The helper does not take the image from stdin, since the first offered type can be markup. Read in `scripts/test-clipboard.py` on host cachy on 2026-10-04: behind a blocked transfer of 131,072 bytes the helper recorded the image in 0.06 s, and a copy of the helper without the close ended at its 5 s limit with no entry.
- The helper ends itself 5 s after it starts, so a source application that never sends its data does not hold the watcher.

## Secrets

- The helper records nothing and prints nothing when `CLIPBOARD_STATE` is `sensitive`, or when the offered types include `x-kde-passwordManagerHint`. It makes both checks before it reads any data of the copy. The [wl-clipboard manual](https://man.archlinux.org/man/wl-clipboard.1.en) defines the variable and says `wl-paste` sets `sensitive` for that type.
- The helper refuses a run with no `CLIPBOARD_STATE`, with `clipboard: clipboard-state=absent` on stderr. Only `wl-paste` ties the secret mark to the data on stdin. Without the variable, the types of the next copy could pass for the types of this one.
- No log line and no IPC refusal holds copied data. The service counts a line it cannot read and prints its length alone.
- An entry draws as plain text: its row is a `ListItem` of `qs.Ui`, which draws plain text ([components.md](components.md)), and the preview sets `Text.PlainText`. Qt's default format draws a tag in copied text as markup. The message for a search with no match names no typed text, for the same reason.

## Store

- The store is `clipboard/` under `Paths.stateDir`: `history.json` and `images/`. An image entry's file is named by the entry's id alone, with no extension: Qt reads the format from the file's content, and `scripts/smoke/rows/clipboard.sh` reads the thumbnail of such a file as decoded. The directories have mode 0700 and each file mode 0600. The helper's `sweep` sets the modes each time the service is built, and `save` makes the history file anew with mode 0600 and renames it into place.
- The history holds 500 entries. An entry's id is the SHA-256 of the copied bytes, so an exact repeat is the same entry, moved to the front with its pin kept. Past 500, the oldest entry that is not pinned goes. A history of 500 pinned entries records no new copy.
- A text copy over 1 MiB and an image copy over 16 MiB are not recorded. The worst case is 500 entries of 1 MiB in `history.json`, which the service rewrites on each change, or 500 images of 16 MiB.
- `sweep` deletes every image file no entry names when the service is built, before the watcher starts. After that, `drop` deletes the files of entries that left the history.
- A store file that is not a history starts the history empty. The next change overwrites it.

## Paste

- A paste runs `wl-copy --type <type>` through the helper, with the entry's text on stdin or its image file. `wl-copy` forks its provider once the copy is set, so its exit is the answer. The provider belongs to the clipboard: it ends when another copy replaces it.
- After the copy, the service hides the overlay and asks the core for the keyboard target with `shell.compositor.observeInput(null, done)` ([input-facts.md](input-facts.md)). For kind `terminal` it runs `wtype` with Ctrl+Shift+V. For kind `application` it runs `wtype` with Ctrl+V. The plugin holds no list of terminals: the core reads the `TerminalEmulator` category of the window's desktop entry.
- A change the service refuses answers a keyed `refused:` line and shows a toast, since the key that asked for it shows nothing else. A refusal for a missing command shows the requirement notice in its place.
- For any other answer the service sends no key and shows a toast. These answers are a refusal, such as `refused: input=unknown-application` for a window no desktop entry names, and kind `vgs` for a window of the shell. The entry stays on the clipboard.
- The service reads `DesktopEntries` as it is built. Quickshell starts its index scan at the first read ([jarvis-desktop-tools.md](jarvis-desktop-tools.md)), and the core's observation reads the index. Without that read, the first paste of a session found no desktop entry: read in `scripts/smoke/rows/clipboard.sh` on host cachy on 2026-10-04, in a run where no earlier row had read the index.
- The observation is a snapshot. A window that takes the keyboard between the observation and the key receives the key.

## Omarchy

Omarchy (`basecamp/omarchy`, branch `quattro` at `2f7302a7`, read 2026-10-04) is the design: the shell records copies itself with `wl-paste --watch`, the history is one JSON file and image files, the overlay shows the list beside a preview, and the two secret checks are the same. VGS differs in these points:

- Omarchy sends Shift+Insert and ships terminal settings that bind it to the clipboard. VGS ships no terminal settings, and foot, kitty, Alacritty and Ghostty bind Shift+Insert to the primary selection by default. VGS sends Ctrl+V, or Ctrl+Shift+V to a terminal.
- Omarchy watches text and `image/png` with two watchers, so a copy with only another image type is lost. A copy with both starts both watchers, so it can make two entries: inferred from the two watchers, not run. VGS runs one watcher and takes text, else the first image type.
- Omarchy's capture uses bash, perl and jq. VGS uses python3, a core requirement.
- Omarchy stops earlier watchers with `pkill -f`. VGS relies on the parent-death signal.
- Omarchy never deletes an image file and sets no file mode or size ceiling. VGS does all three, and adds the pin.
- Omarchy guesses UTF-16 text that has no byte-order mark. VGS records UTF-8 text alone.
- VGS leaves out Omarchy's Alt+Enter, which opens an entry in a browser, editor or image viewer, and its file rows. VGS owns no launcher for those programs, and a file list stays a text entry.

## Invariants

1. An exact repeat adds no entry and moves to the front with its pin. The history holds at most 500 entries, and a pinned entry outlives the limit and Clear all. The rows are pinned first, then newest, at most 50, with 8192 characters of each text entry, and the filter is a substring compared without case. Enforced by `scripts/test-clipboard-history.js`, whose controls each remove one rule from a copy of `ClipboardHistory.js`.
2. A copy with `CLIPBOARD_STATE` `sensitive`, or with the type `x-kde-passwordManagerHint`, prints no line, leaves no file and starts no read of its data. A run with no `CLIPBOARD_STATE` is refused. Enforced by `scripts/test-clipboard.py` against stand-in `wl-paste` and `wl-copy` programs, with one control for each trigger and one for the refusal. On the nested instance, `scripts/smoke/rows/clipboard.sh` copies with `wl-copy --sensitive`, reads a later copy in the history and the secret absent, and its control copy without both checks records the secret.
3. The store's directories have mode 0700 and its files mode 0600. A text copy over 1 MiB and an image copy over 16 MiB are not recorded. An image name the helper takes is an id, never a path, and a recorded image's file has that name. An image is recorded while the copy's first transfer waits unread on the helper's stdin. Enforced by `scripts/test-clipboard.py`, with a control for each rule. `scripts/smoke/rows/clipboard.sh` reads the modes the running service leaves. Its image is larger than `/proc/sys/fs/pipe-max-size`, the largest pipe a user's process can ask for, so the real `wl-copy` serves its capture and its paste behind a blocked transfer: with the close removed from the helper, the row read `capture=timeout` and no image entry on host cachy on 2026-10-04.
4. A terminal receives V with Ctrl and Shift, another application V with Ctrl alone, and a window no desktop entry names receives no key while a toast shows. Enforced by `scripts/smoke/rows/clipboard.sh`, which reads the key and modifier log of the harness's toplevel helper. Its control copy sends a terminal the application's chord.
5. `SUPER+CTRL+V` opens the history, typing filters the drawn rows, and a text copy, an image copy and a copy made before the plugin was enabled are recorded. The overlay decodes an image entry's thumbnail from the file the store names by the entry's id. A change the service refuses shows a toast. Enforced by `scripts/smoke/rows/clipboard.sh`. Its control copy has a shortcut that opens nothing, a watcher whose lines are dropped, a filter the overlay does not send, a thumbnail whose URL names another directory and a refusal without its toast.
6. The plugin is off until enabled: no disabled list names it, and enabling writes its `plugins` row. A watcher that ends while the plugin is enabled starts again, and a disabled plugin leaves no watcher among the shell's children. Enforced by `scripts/smoke/rows/clipboard.sh`, whose control copy starts no watcher again and leaves none. `scripts/test-plugin-logic.js` holds the `optIn` rule and its controls.

`scripts/smoke/rows/clipboard.sh` needs `wl-copy` and `wl-paste` on the path. It fails when one is missing; it does not exit 77.
