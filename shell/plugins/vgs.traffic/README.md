# Network Traffic

See download and upload speeds in the bar. Click the widget to see traffic per app.

![Network Traffic showing app download and upload rates](../../../docs/images/plugins/vgs.traffic-panel.webp)

## Features

- Download, upload, or both speeds in the bar, stacked or on one line.
- Search apps and sort them by download, upload or connection count.
- Click an app to see its processes and connections, or to kill it. Kill asks first.
- Traffic from system services, other accounts and other protocols, under Other traffic.
- See all opens the complete traffic view.

## Setup

Open Settings > Plugins > Network Traffic to change the layout, the labels, the refresh interval, the speeds shown and their decimals.

See all needs bandwhich, an optional tool. While it is missing, the Traffic capture step on the Setup tab offers Review all missing or outdated tools. Once it is installed, the step offers Allow traffic capture when capture access is needed. Allowing it lets every account on this computer see network traffic through bandwhich. Capture works only with a bandwhich from your system's packages. A package update can remove capture access; reopen Settings > Plugins > Network Traffic to check it again.

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
