# VPN

VPN connects your saved NetworkManager VPN and WireGuard profiles. It has its own bar icon, flyout and VPN section in System Settings.

![The VPN section of System Settings with saved VPN and WireGuard profiles](../../../docs/images/plugins/vgs.vpn-pane.webp)

![The VPN section continued, with profile actions, import, the connection editor and Updates](../../../docs/images/plugins/vgs.vpn-pane-end.webp)

## Features

- A shield in the bar that shows whether a profile is connected or needs you.
- A connection switch for each profile, in the flyout and in System Settings. When a profile cannot connect here, its switch says why.
- A password prompt for a profile that asks for its password.
- A profile's type, server and, while connected, its address.
- Import a VPN file imports WireGuard (.conf) and OpenVPN (.ovpn) files.
- NetworkManager's connection editor to add or edit a profile.
- Remove profile deletes a profile after you confirm.

## What VGS can connect

- **Import:** WireGuard (.conf) files, and OpenVPN (.ovpn) files, which need NetworkManager's OpenVPN plugin.
- **Connect:** WireGuard profiles; NetworkManager VPN profiles other than OpenConnect whose plugin is installed and whose passwords NetworkManager holds; and OpenVPN, L2TP, PPTP, SSTP or Fortinet SSL profiles that ask for their password.
- **Not supported:** OpenConnect profiles (Cisco AnyConnect, GlobalProtect, Pulse or Ivanti), a VPN that signs in through a web page, and a profile that asks for anything other than its password when it connects, such as a one-time code or a smart card. These profiles still show, with Edit in connection editor and Remove profile.

## Setup

System Settings › VPN lists your saved profiles. Import a VPN file adds a WireGuard or OpenVPN file. Add with connection editor makes a profile, including a VPN with no file to import. Edit in connection editor, in an open profile, changes it or saves the sign-in details it needs. VGS offers to install the editor when it is missing.

OpenVPN profiles need NetworkManager's OpenVPN plugin. Use Install plugin on an OpenVPN profile, or Optional tools on the plugin's Setup tab.

VGS gives the password you type to NetworkManager for that one connect and keeps no copy. NetworkManager keeps it only where the profile's own password setting says to. Remove profile deletes the passwords and keys saved in the profile; the key and certificate files it uses stay on this computer.

Check every, in the Updates section, sets how often VGS reads your profiles while the flyout and the section are closed.
