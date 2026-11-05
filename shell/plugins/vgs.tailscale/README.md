# Tailscale

Tailscale connects this computer to your tailnet. It turns the connection on and off, chooses an exit node, switches accounts and signs in. It has a bar icon with a flyout, and a Tailscale section in System Settings.

![Tailscale in System Settings, with accounts and this device](../../../docs/images/plugins/vgs.tailscale-pane.webp)

![Network devices, the admin console and Updates in System Settings](../../../docs/images/plugins/vgs.tailscale-pane-end.webp)

## Features

- A bar icon that shows the connection state and whether an exit node is in use.
- A count on the bar icon of the devices connected to this computer, and a list of them with their user, what they use and since when.
- A switch that turns Tailscale on and off and leaves your Tailscale settings as they are.
- Saved accounts: switch between them, add one, sign in and sign out.
- This device and your network devices, with their addresses to copy.
- Connect in terminal starts SSH for a network device. The device needs an SSH server.
- Exit nodes: Tailscale's recommendation, your own nodes, and Mullvad by country and city.
- Open admin console opens the Tailscale admin console, which holds users, access, device approval and device removal.

## Setup

Open System Settings > Tailscale. If Tailscale is missing, choose Install Tailscale.

In Plugins > Tailscale > Setup, the Tailscale service step offers Enable when the service is off. It starts the service and keeps it on after a restart. Let my login control Tailscale lets VGS change the connection and exit node without a password. Each step opens a setup window and asks before making the change.

Finish sign-in in your browser. Sign out asks first, because an administrator may need to approve this computer again after it signs in. If Add account or Sign in needs a newer Tailscale, Optional tools on the Setup tab offers the update. Connect in terminal offers to install SSH if it is missing.

Tailscale is a registered trademark of Tailscale Inc. VGS is not affiliated with or endorsed by Tailscale Inc.
