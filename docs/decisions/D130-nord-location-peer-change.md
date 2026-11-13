# D130: Nord location changes replace only the saved profile's public peer identity

[← Decision Index](INDEX.md)

**Date**: 2026-11-12

**Status**: Active

**Research**: [VGS-2402](https://linear.app/vanillagreen/issue/VGS-2402/vpn-nordvpn-location-picker-country-then-region-or-state-then-city), owner approval of answer A to ask 1794310584.

**Supersedes**: [D110](D110-tailscale-and-vpn-split.md) and [D129](D129-vpn-kill-switch.md) only where their no-profile-edit rule forbids the Nord peer change below. Other profile changes stay in NetworkManager's editor.

**Decision**: The user designates one saved, single-peer WireGuard profile by UUID as the Nord profile. `vgs.vpn` lists Nord's public countries, then regions or states where supplied, then cities. It fetches the list once per open and uses Nord's recommendation for the city's WireGuard server. After validating the public key and numeric address, it changes only the peer's public key and endpoint address through `nmcli` argv, preserving the port and other peer attributes. The account private key stays unread and untouched in NetworkManager. It reconnects only a profile connected when the change began. An armed kill switch must acknowledge the new endpoint allowance before reconnect; intent and the block stay in place throughout. No token access, profile creation, alternate backend, polling or favourites are added.

**Why**: One saved profile keeps the existing account identity and protection without repeating profile setup for each location. Public discovery supplies the server identity without provisioning credentials or adding a secret store. The kill switch passes the endpoint, so the UUID alone cannot acknowledge its new allowance.

**Rejected**: Requiring NetworkManager's editor or another profile for each location leaves the owner's location changes outside VGS. Moving to Nord's app would replace the saved-profile and protection path with credential provisioning the change does not need.

**Revisit when**: Discovery needs authentication, Nord stops supplying a usable public key and numeric address, preserving the peer requires secret access, or users need multiple Nord profiles or profile creation. Token access or another secret store needs owner approval first.
