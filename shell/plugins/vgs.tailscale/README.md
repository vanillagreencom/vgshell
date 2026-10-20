# Tailscale

Tailscale connects this computer to your tailnet. It turns the connection on and off, chooses an exit node, switches accounts and signs in. It has a bar icon with a flyout, and a Tailscale section in System Settings.

![The Tailscale section of System Settings, with the connection switch and exit nodes](../../../docs/images/plugins/vgs.tailscale-pane.webp)

## Features

- A route icon shows the connection state and changes to a globe with a lock while an exit node is in use. It hides while Tailscale or its service is absent.
- The flyout holds the connection switch and its state, your account and tailnet, this device, your network devices and the exit node. Open admin console opens the Tailscale admin console in your browser, and Tailscale settings opens the System Settings section.
- The account row lists your accounts. Select one to switch to it. Add account opens the Tailscale sign-in page in your browser. Sign out asks first, because an admin may need to approve this computer again after it signs in.
- Copy beside this device or a network device puts its Tailscale address on the clipboard.
- The Exit node row opens the exit nodes: Recommended, the node Tailscale suggests, then None, your own exit nodes and Mullvad by country and city. Best available in a country picks the city Tailscale ranks highest at that moment. Type in the search field to find a country, a city or a device. An offline exit node of your own cannot be chosen.
- The switch turns Tailscale on and off and leaves your Tailscale settings as they are. Users, access, device approval and device removal stay in the admin console.

## Setup

The Tailscale service step on the plugin's Setup tab offers one step at a time. Enable and Let my login control Tailscale run in a setup window that shows its commands and asks before it runs them. While Tailscale is not installed, select Review all missing or outdated tools under Optional tools on the Setup tab.

| Step | When | What it does |
| --- | --- | --- |
| Enable | The Tailscale service is off | Starts the service and keeps it on after a restart. |
| Let my login control Tailscale | The administrator holds Tailscale | Lets VGS connect, disconnect and choose an exit node for you without a password. |

Check every sets how often VGS reads Tailscale while the flyout and the section are closed.

Tailscale is a registered trademark of Tailscale Inc. VGS is not affiliated with or endorsed by Tailscale Inc.
