# Network

Network joins Wi-Fi and shows your Wi-Fi and Ethernet connections. It has a bar icon with a dropdown, and a Network section in System Settings.

![Network in System Settings](../../../docs/images/plugins/vgs.network-pane.webp)

Image: `scripts/readme-shots.sh`.

## Features

- A dropdown under the bar icon with the Wi-Fi switch, the current connection, the Wi-Fi networks to join and each Ethernet device with its state. Network settings opens the System Settings section.
- Joins Wi-Fi with a saved password, or asks for the password in a masked field. It asks again when a saved password fails.
- Select a network and press Enter to join or disconnect. Delete forgets the selected saved network.
- Turns the Wi-Fi radio and automatic joining on or off.
- Shows the connection details of the selected device.
- Share QR code shows a QR code that joins another device to a saved network. VGS keeps neither the password nor the QR code after the view closes.
- Shows the cause when NetworkManager is missing, stopped or refuses access. Wi-Fi passwords stay in NetworkManager's store.
- Offers to install the details tool or the sharing tool when one is missing.

## Settings

Show disconnected icon keeps the network icon in the bar while disconnected.
