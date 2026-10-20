# VPN

VPN connects your saved NetworkManager VPN and WireGuard profiles. It has its own bar icon, flyout and VPN section in System Settings.

![The VPN section of System Settings with saved VPN and WireGuard profiles](../../../docs/images/plugins/vgs.vpn-pane.webp)

## Features

- A shield icon shows whether a profile is connected. It hides while NetworkManager is unavailable or no VPN or WireGuard profile is saved.
- Saved profiles have a connection switch in the flyout and the System Settings section.
- Import WireGuard opens a file picker in a setup window. NetworkManager stores the imported profile and its keys.

## Setup

System Settings › VPN stays available when the bar icon hides. It shows your saved profiles when NetworkManager answers. Import WireGuard adds a configuration file to NetworkManager.

Check every sets how often VGS reads your profiles while the flyout and the section are closed.
