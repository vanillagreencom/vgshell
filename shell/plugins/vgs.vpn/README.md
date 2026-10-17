# VPN

VPN shows your saved VPN profiles and your Tailscale connection. It turns it on and off, chooses an exit node, switches accounts and signs in. It has a bar icon with a flyout, and a VPN section in System Settings.

![The VPN section of the System Settings window, with the connection switch and the exit nodes](../../../docs/images/plugins/vgs.vpn-pane.webp)

## Features

- A bar icon that shows connected, off, or the exit node in use. It hides when neither VPN backend is available.
- A flyout with the connection switch, Sign in while you are signed out, and the exit nodes. VPN settings opens the System Settings section.
- A VPN section in System Settings, on `SUPER+PERIOD`, with the same controls, this device, your accounts and your other devices.
- The switch turns Tailscale on and off and leaves your Tailscale settings as they are.
- The exit node list holds None, your network's exit nodes by name, and one Mullvad node for each city. A long list shows a limited number of nodes and the node in use.
- Enter or a click routes your traffic through the selected exit node. None turns the exit node off.
- Sign in and Add account open the Tailscale sign-in page in your browser. A click on an account switches to it.
- Saved VPN and WireGuard profiles have a connection switch in the flyout and the VPN section. The list hides when NetworkManager is unavailable.
- Import WireGuard opens a file picker in a setup window. NetworkManager stores the imported profile and its keys.
- Shows "Tailscale did not answer." when Tailscale does not reply in 10 seconds.

## Setup

The VPN section and Tailscale service on the plugin's Details tab offer one step at a time. Enable and Let my login control Tailscale run in a setup window that shows its commands and asks before it runs them. While Tailscale is not installed, select Review all missing or outdated tools under Tools on the Details tab.

| Step | When | What it does |
| --- | --- | --- |
| Enable | The Tailscale service is off | Starts the service and keeps it on after a restart. |
| Let my login control Tailscale | The administrator holds Tailscale | Lets VGS connect, disconnect and choose an exit node for you without a password. |

Check every sets how often VGS reads Tailscale while the flyout and the section are closed: 10, 30 or 60 seconds.
