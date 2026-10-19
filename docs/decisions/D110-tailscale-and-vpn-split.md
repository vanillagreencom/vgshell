# D110: Tailscale and VPN are two plugins, and a split plugin declares its source

[← Decision Index](INDEX.md)

**Date**: 2026-10-19

**Status**: Active

**Research**: [VGS-1923](https://linear.app/vanillagreen/issue/VGS-1923): owner ask (Slack, 2026-10-19), split delegated; the design attached to the issue.

**Refines**: [D108](D108-renamed-plugin-declares-former-ids.md), for a plugin split in two: `formerIds` gives a former id one heir and refuses an id a scanned plugin holds.

**Refines**: [D098](D098-networkmanager-only-secrets.md), for a VPN password: it reaches `nmcli` on stdin, as hidden Wi-Fi's reaches the helper.

**Decision**: `vgs.vpn` splits in two. `vgs.tailscale` (Tailscale) owns every `tailscale` process, the `service-tailscaled` and `tailscale-operator` steps, and its own bar icon, flyout and System Settings section; it shows the account, this device, the network devices and the exit nodes the CLI reports, and opens the web admin console rather than rebuilding any of it. `vgs.vpn` (VPN) keeps its id and owns NetworkManager `vpn` and `wireguard` profiles through `nmcli`: connect, disconnect, details, import and remove. It imports WireGuard `.conf` and OpenVPN `.ovpn` files and no other type. It connects every WireGuard profile whose private key NetworkManager holds, every VPN profile whose NetworkManager plugin is installed and whose secrets NetworkManager holds, and an OpenVPN, L2TP, PPTP, SSTP or Fortinet SSL profile that asks for one password, which the user types in a masked field and VGS hands to `nmcli` on stdin. It does not connect OpenConnect profiles, a VPN that signs in on a web page or asks for more than one secret or a code, or a profile of any other type that asks for a secret when it connects; such a row states why. It edits no profile. Each bar icon hides while its backend is absent. Each System Settings section stays while its backend is absent, as the [D075](D075-consumer-features-need-no-developer-setup.md) setup path: Install Tailscale, or the line that NetworkManager is absent. A bundled plugin split from another names that plugin in its manifest's `splitFrom`. While the user file names the new plugin nowhere, the core gives it the source's `disabledPlugins` entry, a `bar.layout` entry before each of the source's, and always a `plugins[]` row for the new plugin, holding the source row's values of the settings the new manifest declares; a user file the core creates carries a bare row for each split target. It runs on the rename path, from bundled manifests alone, with no format version. `vgs.tailscale` declares `splitFrom: "vgs.vpn"` for as long as it ships.

**Why**: The owner asked that a VPN and Tailscale read apart, each with its own details. A plugin has one bar widget, one flyout and one System Settings section, so two of each need two plugins. Without the declaration a new first-party plugin starts enabled whatever the user disabled, takes first presence at the end of its section, and loses `pollSeconds`. No core edit removes a `plugins[]` row, so the row records that the file has seen the split: re-enabling the new plugin, or a disable the user makes later, is never copied again. System steps are probed and recorded by step, so moving them redoes nothing. NetworkManager owns VPN plugins and their secrets; one password field covers the files VGS imports without a secret agent in the core.

**Rejected**: Keeping one plugin, because one icon and one section cannot show the two apart. Giving `vgs.vpn` to Tailscale and a new id to the VPN half, because the id would name the wrong backend and the new plugin would still lose the user's disable. A NetworkManager secret agent lent by the core so every VPN plugin's own dialog runs, because it is a new core capability with a process and a lifetime that the common single-password profiles do not need.

**Revisit when**: Users need OpenConnect, web sign-in or multi-secret VPNs, or NetworkManager or Quickshell offers a secret agent VGS can lend without a new core capability; a split must hand the source's settings to its heirs other than by the keys each declares; or an installed plugin must split.
