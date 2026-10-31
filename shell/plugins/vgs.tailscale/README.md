# Tailscale

Tailscale connects this computer to your tailnet. It turns the connection on and off, chooses an exit node, switches accounts and signs in. It has a bar icon with a flyout, and a Tailscale section in System Settings.

![Tailscale in System Settings, with accounts and this device](../../../docs/images/plugins/vgs.tailscale-pane.webp)

![Network devices, the admin console and Updates in System Settings](../../../docs/images/plugins/vgs.tailscale-pane-end.webp)

## Features

- A route icon shows the connection state and changes to a globe with a lock while an exit node is in use. It hides while Tailscale or its service is absent.
- The flyout holds the connection switch and its state, the Accounts card, this device, your network devices and the exit node. Open admin console opens the Tailscale admin console in your browser, and Tailscale settings opens the System Settings section.
- The Accounts card, at the top of the flyout and of System Settings › Tailscale, lists your saved accounts and their tailnets. Select one to switch to it. While this computer is signed out, each saved account has Sign in, which opens the Tailscale sign-in page in your browser when Tailscale asks for it. Add account opens a setup window that asks first, then opens the sign-in page; if you cancel, the previous account stays selected. Sign out asks first, because an admin may need to approve this computer again after it signs in.
- System Settings shows this device’s name, Tailscale address, DNS name and network. Copy beside the address or DNS name puts that value on the clipboard.
- This device and each network device have a copy icon that puts the device’s address on the clipboard. A network device that runs Linux, macOS, Windows, FreeBSD, OpenBSD, illumos or Solaris also has Connect in terminal, which opens your terminal with an ssh session to the device. When tmux is installed, the session is a window named after the device in the tmux session tailnet, and each later connect adds a window to it. In System Settings, the row menu also has Copy DNS name. Connect in terminal needs ssh; while it is missing, a press offers to install it.
- The Exit node row opens the exit nodes: Recommended, the node Tailscale suggests, then None, your own exit nodes and Mullvad by country and city. Best available in a country picks the city Tailscale ranks highest at that moment. Type in the search field to find a country, a city or a device. An offline exit node of your own cannot be chosen.
- The switch turns Tailscale on and off and leaves your Tailscale settings as they are. Users, access, device approval and device removal stay in the admin console.

## Setup

The Tailscale service step on the plugin's Setup tab offers one step at a time. Enable and Let my login control Tailscale run in a setup window that shows its commands and asks before it runs them. While Tailscale is not installed, System Settings › Tailscale offers Install Tailscale.

| Step | When | What it does |
| --- | --- | --- |
| Enable | The Tailscale service is off | Starts the service and keeps it on after a restart. |
| Let my login control Tailscale | The administrator holds Tailscale | Lets VGS connect, disconnect and choose an exit node for you without a password. |

Add account and Sign in need a recent Tailscale. With an older one, they say so, and the Optional tools step on the Setup tab offers the update; the connection switch and the exit node still work.

Updates, the last section in System Settings › Tailscale, holds Check every. It sets how often VGS reads Tailscale while the flyout and the section are closed.

Tailscale is a registered trademark of Tailscale Inc. VGS is not affiliated with or endorsed by Tailscale Inc.
