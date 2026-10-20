# VPN

VPN connects your saved NetworkManager VPN and WireGuard profiles. It has its own bar icon, flyout and VPN section in System Settings.

![The VPN section of System Settings with saved VPN and WireGuard profiles](../../../docs/images/plugins/vgs.vpn-pane.webp)

## Features

- A shield icon shows whether a profile is connected. It turns while a profile connects or disconnects, and shows a warning after a profile could not connect or needs its password. It hides while NetworkManager is unavailable or no VPN or WireGuard profile is saved.
- Each profile has a connection switch in the flyout and in System Settings. Its line gives its type and state, and when a profile cannot connect here, its switch says why.
- Open a profile to see its type, its server and, while it is connected, its address.
- Import a VPN file opens a file picker in a setup window. It imports WireGuard (.conf) and OpenVPN (.ovpn) files, and NetworkManager stores the imported profile and its keys.
- Remove profile, in an open profile in System Settings, deletes the profile after you confirm. NetworkManager deletes the keys and passwords it saved for it.

## What VGS can connect

- **Import:** WireGuard (.conf) files, and OpenVPN (.ovpn) files, which need NetworkManager's OpenVPN plugin. VGS offers to install it. No other file type imports.
- **Connect and disconnect:**
  - every WireGuard profile whose private key NetworkManager holds;
  - every NetworkManager VPN profile whose NetworkManager plugin is installed and whose passwords NetworkManager holds, whatever its type;
  - an OpenVPN, L2TP, PPTP, SSTP or Fortinet SSL profile that asks for one password when it connects.
- **Details:** the type, the server and, while connected, the assigned address.
- **Remove:** any profile, after you confirm. NetworkManager deletes its saved keys and passwords with it.
- **Not supported:** OpenConnect profiles (Cisco AnyConnect, GlobalProtect, Pulse or Ivanti), a VPN that signs in through a web page, a profile that asks for more than one secret or a one-time code when it connects, a smart card or certificate passphrase, a profile of any other type that asks for a secret when it connects, and making or editing a profile by hand. These profiles still show with their details and Remove profile, and their switch says why it cannot connect.

## Setup

System Settings › VPN stays available when the bar icon hides. It shows your saved profiles when NetworkManager answers. Import a VPN file adds a WireGuard or OpenVPN file to NetworkManager. An OpenVPN profile needs NetworkManager's OpenVPN plugin: choose Install plugin in the open profile, or Install beside OpenVPN plugin under Tools in VPN Details.

Check every, in the Updates section, sets how often VGS reads your profiles while the flyout and the section are closed.
