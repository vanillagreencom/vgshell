# Login screen

`vgs.greeter` logs you in on a screen that uses your VGS theme and background. It is for a computer that starts VGS at boot.

![The login screen: the time, the account, the password field and the session picker](../../../docs/images/plugins/vgs.greeter-screen.webp)

Screenshot of the `greeter` scene of `scripts/sandbox-shots.sh` in the nested sandbox, with the default theme at scale 2, over fixture sessions and one fixture account, cut and encoded the way `scripts/readme-shots.sh` does for its row.

## Features

- Shows the time, your accounts and a password field on every screen, in your theme over your background.
- Lists every installed session: Hyprland, Hyprland (uwsm-managed), GNOME, Plasma and any other Wayland or X11 session.
- Chooses Hyprland (uwsm-managed) on the first login, then remembers your last account and each account's last session.
- Unlocks your login keyring with your password, so apps that use the keyring start signed in.
- Types with the system keyboard layout. A layout without Latin letters gets US English first, and Left Alt + Right Alt switches between them.
- Accepts a fingerprint or another method your login configuration sets: press Enter with the password field empty.
- Offers Suspend, Restart and Shut down.
- Copies your theme and background for the login screen each time you change them.

## Setup

The plugin ships with VGS. The login screen is off until you turn it on: open Plugins, choose Login screen and press Set up. A terminal shows each file the setup writes and asks for your password once. The login screen shows at the next boot.

Setup needs greetd and VGS installed from a package. If another login screen, such as GDM or SDDM, is turned on, Set up is not offered and VGS leaves that login screen alone. On that login screen, Hyprland (uwsm-managed) starts the same session.

Removing the setup puts back the login configuration that was there before.

<details>
<summary>Show command</summary>

```sh
vgshell system apply greeter
vgshell system undo greeter
```

</details>

The Settings page shows whether the login screen is set up and whether its copy of your theme is up to date.
