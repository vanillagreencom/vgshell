# Printers

Printers adds, chooses and removes your printers. It has a Printers section in the System Settings window, under Hardware.

![The Printers section of the System Settings window, with two printers, the default one marked, and Add a printer](../../../docs/images/plugins/vgs.printers-pane.webp)

## Features

- The list of your printers, with each printer's state, its queued jobs and the default printer marked.
- While the section is open, the list changes when the printing service reports a change, such as a new job or a printer that stops. When the section is closed, Printers runs nothing in the background.
- Set as default makes a printer the one your apps print to first.
- Remove takes a printer off the computer. Delete removes the selected printer.
- Find printers lists the printers on this computer and your network. Add sets up a printer that needs no driver.
- A printer that needs a driver opens Print Settings, where you choose its driver.
- The address field adds a network printer by its name or IP address, such as `printer.local`.
- Print Settings opens the full printer settings for drivers, paper size, two-sided printing and quality.
- Each change asks your permission in the system's password prompt. VGS never sees the password. A change you do not allow changes nothing.
- Turn on printing starts the printing service in a setup window when it is off.

## Requirements

Printers reads your printers with the printing service's own tools, which come with CUPS. Without CUPS the section says that printing is not installed, and Install printing installs it in one press. On the plugin's Setup tab, the Printing step reads To do until CUPS is installed, and Review all missing or outdated tools on its row installs it. The printer helper is optional: without it the list works, and each change button offers to install it. Print Settings is optional too.

<details>
<summary>Show command details</summary>

[`Service.qml`](Service.qml) owns printer reads and changes. [`PrintersLogic.js`](PrintersLogic.js) declares the CUPS queries and cups-pk-helper calls; [`bin/printers-watch`](bin/printers-watch) owns the change subscription and its renewal and cancellation. Closing the section ends the subscription. polkit asks through your session's agent. Turn on printing runs the core system step `service-cups`, `systemctl enable --now cups.service`, in the setup window. It is offered only while neither `cups.service` nor `cups.socket` is active.

</details>
