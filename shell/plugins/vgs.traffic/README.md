# Network Traffic

See download and upload speeds in the bar. Click the widget to see traffic per app.

![Network Traffic showing app download and upload rates](../../../docs/images/plugins/vgs.traffic-panel.webp)

- Choose download, upload, or both speeds in the bar.
- Search apps and sort their download, upload, or connection count.
- See traffic from other accounts and protocols in Other traffic.
- Open the complete traffic view with See all.

## Setup

Open Settings > Plugins > Network Traffic to change the display and refresh interval. Apps show TCP traffic from your account. Other traffic includes UDP, system services, and other accounts.

The optional bandwhich requirement enables See all. Install it from the Requirements section. The Traffic capture row has Allow when capture access is needed. Allowing it lets every account on this computer see network traffic through bandwhich.

A package update can remove capture access. Allow appears again when this happens.

<details>
<summary>Show command</summary>

The core system step grants capture access to the trusted installed binary:

```sh
setcap cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep /usr/bin/bandwhich
```

The See all terminal runs:

```sh
bandwhich
```

</details>

## Licence

[MIT](../../../LICENSE)
