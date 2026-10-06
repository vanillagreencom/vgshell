# Clipboard

Clipboard keeps what you copy. Open the history with `SUPER+CTRL+V`, find an earlier copy and paste it again.

![The clipboard history](../../../docs/images/plugins/vgs.clipboard-history.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- A history of your last 500 text and image copies. It stays after a restart.
- Type to find an entry. Find an image entry by "image" or by its type, such as "png".
- Enter pastes the selected entry into the application you work in. Shift+Enter puts it on the clipboard only.
- Ctrl+P pins an entry. A pinned entry stays first, and stays when you clear the history or the history is full.
- Delete removes an entry. Shift+Delete clears the history after a question.
- A copy that a password manager marks as secret is never recorded.

## Setup

Clipboard ships with VGS and is off until you turn it on, so VGS records no copy before you ask. Once on, it saves every copy to disk, and that includes a password copied from an app that does not mark it as secret. Open Plugins, select Clipboard in the plugin list and turn the plugin on. Turn it off there to stop recording; the history you have stays.

The Keys row on the plugin's Settings page changes `SUPER+CTRL+V`. The same page lists the tools Clipboard needs and installs the missing ones.

[developer.md](developer.md) states what is recorded, where it is kept and the plugin's IPC functions.
