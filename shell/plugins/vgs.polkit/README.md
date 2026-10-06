# Polkit

Polkit asks for your password when an application needs administrator access. The prompt uses your theme.

![The password prompt for a program run with pkexec](../../../docs/images/plugins/vgs.polkit-prompt.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- A dialog over a dimmed screen with the request's message, its polkit action, the account it authenticates as and the password field.
- A choice of account when the request accepts several, such as every member of an administrators' group. Tab and Shift+Tab reach it from the keyboard.
- Enter or Allow submits the password. Escape or Cancel denies the request.
- A wrong password, and every message PAM sends, shows under the field. The dialog then asks again.
- The password is cleared from the field as soon as it is sent.

## Setup

The plugin ships with VGS and is on by default. Only one app at a time can show password prompts. The Settings page shows whether VGS can show them. When another app shows them, the page names it and offers Uninstall, or Stop when another installed app needs it. When polkit is not installed, the page offers Install. After each of these, VGS shows password prompts at once, with no new login.
