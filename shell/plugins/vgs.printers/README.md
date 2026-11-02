# Printers

Printers adds, chooses and removes your printers. It has a Printers section in the System Settings window, under Hardware.

![The Printers section of the System Settings window, with two printers, the default one marked, and Add a printer](../../../docs/images/plugins/vgs.printers-pane.webp)

## Features

- Your printers, with each printer's state, its queued jobs and the default printer marked.
- Set as default makes a printer the one your apps print to first.
- Remove takes a printer off the computer.
- Find printers lists the printers on this computer and your network. A printer that needs a driver opens Print Settings to choose one.
- Adds a network printer by its name or address, such as `printer.local`.
- Print Settings opens the full printer settings for drivers, paper size, two-sided printing and quality.
- Each change asks your permission in the system's password prompt. VGS never sees the password.

## Setup

Printers needs CUPS, the printing service. Without it, the section says printing is not installed, and Install printing installs it in one press. When the printing service is off, Turn on printing starts it in a setup window. The printer helper and Print Settings are optional; a change button offers to install the helper when it is missing.

<details>
<summary>Show command</summary>

```bash
systemctl enable --now cups.service
```

</details>
