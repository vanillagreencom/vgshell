# Remote desktop

Remote desktop opens the desktop of your other computers in a window, and shows in the bar when another computer views this one. It uses [gliff](https://github.com/omacom/gliff) over SSH: no account, no pairing and no open port beyond SSH.

![System Settings › Remote desktop: Hosting says SSH is off, and two computers to connect to](../../../docs/images/plugins/vgs.remote-desktop-pane.webp)

## Features

- A red screen icon in the bar while another computer views this desktop. Its tooltip names that computer and its address.
- One entry per computer, each with its own screen, window, video, picture, bitrate, capture, clipboard and release keys.
- Connect opens a computer in one click, from System Settings › Remote desktop or from the launcher, which lists Connect to each computer.
- The first time it starts, the list holds the computers your SSH settings name and that you signed in to before.
- Hosting off turns off remote desktop to this computer; SSH stays as it is. While it is off, Hyprland refuses the screen to gliff, and VGS ends each session it finds.

A window your Hyprland configuration marks `no_screen_share` stays hidden in every screen capture, a remote session included.

## Setup

Both computers need gliff, and the computer you connect to needs SSH on. gliff signs in with an SSH key and cannot ask for a password. On the plugin's Setup tab:

| Step | When | What it does |
| --- | --- | --- |
| Optional tools | gliff or SSH is missing | Installs them. gliff comes from Omarchy's package repository as one file, whose signature VGS checks against Omarchy's key. |
| SSH on this computer | Hosting is on and the SSH server is off | Starts the SSH server and keeps it on after a restart. |

Set up sign-in, on each computer's row in System Settings › Remote desktop, makes key sign-in to that computer work. It opens a terminal that uses your first key of `~/.ssh/id_ed25519`, `id_ecdsa` and `id_rsa`, or makes one when you have none, then copies the key to the other computer. A key with a passphrase goes into your SSH agent first, since Remote desktop cannot type the passphrase. You type your password on that computer, and any passphrase, into the terminal; VGS does not see or keep them.

<details><summary>Show command</summary>

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519        # only when none of the three keys exists
ssh-keygen -y -f ~/.ssh/<your key> > ~/.ssh/<your key>.pub   # only when its .pub is missing
ssh-add ~/.ssh/<your key>                                # only for a key with a passphrase the agent does not hold
ssh-copy-id -i ~/.ssh/<your key>.pub -- <computer>
```

</details>

Connect also offers to install gliff while it is missing. The first time the plugin is on, Hosting off takes full effect after you sign in again, because Hyprland reads its screen capture rules only when it starts. Until then, VGS ends each session it finds while hosting is off.
