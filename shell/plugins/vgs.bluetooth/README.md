# Bluetooth

Bluetooth turns Bluetooth on and off, and pairs, connects, renames and forgets your devices. It has a bar icon with a flyout, and a Bluetooth section in the System Settings window.

![The Bluetooth section of the System Settings window, with the power switch, Discoverable and the connected headphones](../../../docs/images/plugins/vgs.bluetooth-pane.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2, over the sandbox's Bluetooth fakes.

## Features

- A bar icon that shows off, on, or the count of connected devices. It hides when the computer has no Bluetooth adapter.
- A flyout with the power switch, your devices and the devices nearby. A click on your device connects or disconnects it, and a click on a nearby device opens the Bluetooth section to pair it.
- A Bluetooth section in System Settings, on `SUPER+PERIOD`, with the power switch, Discoverable, My Devices and Nearby.
- My Devices connects or disconnects a device, and its menu renames, trusts or forgets it. Delete forgets the selected device.
- Pair shows each request from the device in a dialog: confirm a code, enter a PIN or passkey, or allow a service. A paired device is trusted and connected.
- Discoverable lets other devices find this computer and pair with it while the section is open.
- Bluetooth stays off after a restart when you turn it off.
- Shows when a hardware switch turns the radio off.
- Turn on the service starts the Bluetooth service in a setup window when it is stopped.

## Settings

Hide when off hides the bar icon while Bluetooth is off.
