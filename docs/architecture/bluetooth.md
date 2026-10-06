# Bluetooth

Covers: shell/plugins/vgs.bluetooth/**, scripts/test-bluetooth-logic.js, scripts/smoke/rows/bluetooth.sh

The `vgs.bluetooth` plugin: a service, a bar widget, a flyout `panel` and a System section `pane`. It reads adapters and devices from Quickshell's `Bluetooth` singleton, a read model that claims no session role. Power, discovery and pairing each have one owner: the service owns power and discovery, and the core's `bluetoothAgent` capability owns the pairing agent ([bluetooth-agent.md](bluetooth-agent.md)). `BluetoothLogic.js` makes every decision below; the QML runs its effects.

## Parts

- `Service.qml` runs the power operation, the rfkill reads and writes, and the discovery debt, and publishes the power view as status.
- `Widget.qml` binds the bar icon to `BluetoothLogic.barView`.
- `PowerField.qml` is the power switch the flyout and the pane share, with the line `BluetoothLogic.powerLine` picks as its hint or error. `DeviceSections.qml` is the My Devices and Nearby lists they share, each a `qs.Ui` `DeviceList` ([components-layout.md](components.md)).
- `Pairing.qml` runs one pairing and answers the agent's prompts; `Prompt.qml` is the pane's one `Dialog`, drawn from `BluetoothLogic.PROMPTS`. `DiscoveryLease.qml` is a lease of the service's discovery.

## Power

- rfkill's soft block is the power state, as Omarchy's `bin/omarchy-bluetooth-power` has it: BlueZ never keeps an adapter's `Powered` across a boot, systemd-rfkill keeps the block, and `bluetoothctl power on` fails while a block is set.
- On runs `rfkill unblock bluetooth`, then waits `POWER_WAIT_MS`, 2000 ms, for any adapter to report powered. With none, it sets `Powered` on every unpowered adapter Quickshell does not report blocked, and waits again. With none still, the operation fails with `no-power`. Off runs `rfkill block bluetooth`, which reaches every radio.
- A failure lasts until what was asked for is observed or the next press: a powered adapter clears a failed On, and rfkill reading the soft block clears a failed Off. A failed view's switch stands where the observed power stands.
- The power view keeps the states apart, in the order they win: `rfkill-missing`, `hard-blocked` ("Turned off by a hardware switch", no action), `service-needed` (no adapter and the `service-bluetooth` step reads needed or nixos), `no-adapter`, `turning-on`, `turning-off`, `failed`, `rfkill-failed`, `off` and `on`. A press is refused while the view offers no toggle.
- The service reads `rfkill -J` at start, after each of its own runs, after each requirement scan and whenever an adapter's `Powered` or `PowerState` changes, which BlueZ moves on every block. It polls nothing.
- No widget, flyout or pane writes an adapter's `enabled`: they ask the service.

## Discovery

- Quickshell 0.3.1 forwards a `discovering` write only when it differs from what BlueZ last reported (`BluetoothAdapter::startDiscovery`, `stopDiscovery` in `src/bluetooth/adapter.cpp`), so a stop written before BlueZ confirmed a start is dropped.
- The service keeps the leases, what it wants, apart from `discovering`, what BlueZ confirms, and a debt: set when it starts a session or adopts one already running or confirmed while a lease is open, cleared when BlueZ reports discovery down with no lease open.
- The flyout and the pane each hold a lease while Bluetooth is on (`DiscoveryLease.qml`); the instance's teardown ends it.
- After the last lease ends, a stop is written at once if BlueZ confirms discovering, then once a second while BlueZ still confirms it, at most 3 times, as Omarchy's `shell/plugins/panels/bluetooth/Panel.qml` does. While a lease is open and the adapter is powered, a start is written once a second until BlueZ confirms one.
- A replaced default adapter and the service's teardown clear the debt; the teardown writes a stop for a session it owes.

## Pairing

- The pane holds a `bluetoothAgent` lease while a pairing runs and while Discoverable is on. BlueZ ending Discoverable, on its own timeout or at power-off, releases that lease. The flyout pairs nothing: a nearby device's action opens the pane with `{"pair":"<address>"}`.
- A pairing takes the lease, calls `Pair` once the lease reads ready, and ends done once the device reads paired, then trusts and connects it, as Omarchy's `bin/omarchy-bluetooth-device` does. It fails on a refused lease, a cancel, a device that left, or a `Pair` call that answered with the device unpaired and no prompt open for `PAIR_SETTLE_MS`, 2000 ms: BlueZ queues its `Paired` change, so it can arrive after the answer. A pairing keeps the device and the name it started with; Pair hides while one runs.
- The pane answers the agent's first open request through one `Dialog`. `PROMPTS` holds each kind's title, message, field, actions, accept answer and dismissal: confirm, PIN, passkey entry, a code to type, authorize, cancel and a rename. The dialog starts afresh only when the request's id or kind changes, since the agent lists a new copy after every line bluetoothctl prints. A code to type is dismissed when the pairing ends.

## Status and IPC

- The service publishes `power`, a state entry whose Turn on the service action applies the `service-bluetooth` system step while the view reads `service-needed`, and `bluetooth`, data `{ power }`, the power view every surface draws. The Settings page offers the action, and the pane offers it under its power switch while the core's status row offers it (`status.rows`) and runs it through `status.act` ([status-actions.md](status-actions.md)).
- The service's IPC functions are `power on|off`, `discovery begin`, which answers `lease=<id>`, `discovery end <id>` and `refresh`. The flyout and the pane call them through `shell.ipc.call`.

## Differences from Omarchy

- Omarchy's flyout writes its own discovery and power from each bar instance and hands a debt to a sibling widget. VGS gives both to the one service, so a flyout and a pane share one debt.
- Omarchy pairs through an always-on `bt-agent` unit. VGS installs no user unit; the pane takes the core's agent only while a pairing or Discoverable needs it ([D085](../decisions/D085-bluetooth-agent-core-lent-over-bluetoothctl.md)).

## Invariants

1. The power operation, the power view and its lines, the discovery debt, the pairing steps, the dialog's prompts, the device rows and the bar icon decide as above. Enforced by `scripts/test-bluetooth-logic.js`, with a control per rule, each required to fail on its own assertion, one of them a plain lease counter that leaks a start confirmed after the last lease.
2. In the nested sandbox over the BlueZ mock and the rfkill stand-in ([validation-smoke-devices.md](validation-smoke-devices.md)): Off writes the soft block and a rebuilt service reads it off and unblocks nothing; On unblocks and waits for confirmed power, and sets `Powered` itself when the automatic power-on does not come; a hard block shows the hardware-switch state, offers no switch and runs no rfkill write; a start BlueZ confirms after the flyout closed is stopped; three pairings each call `Pair` once and take and release the agent's lease, answering a confirm prompt from the keyboard, dismissing a code to type, and sending a typed PIN that survives a later line of bluetoothctl's output; BlueZ's end of Discoverable releases its lease; Connect, Disconnect and Forget reach the mock; the keyboard alone reaches every control; and with no adapter and a stopped service, a click on the pane's Turn on the service hands the stand-in terminal `vgshell system apply service-bluetooth`, which runs no step. Enforced by `scripts/smoke/rows/bluetooth.sh`, whose control is a copy of the plugin that writes no stop after the last lease, which leaves the late start running, and never calls `Pair`, which leaves the mock's count at 0. The stopped service is a second copy whose service lists no adapter, since the mock's adapter stays planted for the run; the terminal holds no record before the click.

## Decisions

[D012](../decisions/D012-core-owns-lent-objects.md), [D037](../decisions/D037-plugin-status.md), [D061](../decisions/D061-no-manual-commands.md), [D081](../decisions/D081-system-steps-closed-core-table.md), [D085](../decisions/D085-bluetooth-agent-core-lent-over-bluetoothctl.md), [D088](../decisions/D088-system-panes.md).
