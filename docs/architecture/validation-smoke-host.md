# No smoke row reaches the host

Read before touching a sentinel, the stand-in terminal, a device fake, a host command's stand-in, the device guard, or a row that presses a button which opens a TUI.

## The approach

The nested sandbox shares the host's PAM, polkit, faillock, files and sudo timestamp, so a row never authenticates against the host user, never runs a plugin's real TUI script, and resolves no host command the shell runs outside the shell's stand-in directory. `sudo`, `doas`, `run0`, `pkexec`, `su`, `loginctl` and `secret-tool` are sentinels that log and exit 1. A System row reads fakes for the host's audio, radios, network, VPN, DDC and hidraw, built on `scripts/smoke/devices.sh`, behind a guard that proves the shell's environment points at them.

## Why

A real authentication or a real TUI script in the sandbox changes the owner's machine. `crontab` picks the caller's table by user, not by HOME, so it is a stand-in for the whole run. Quickshell looks for bluez, NetworkManager and PipeWire once, when the singleton is first read, so a fake must be up before the plugin that reads it is enabled, and a null sink given `media.class` `Audio/Source` never activates in WirePlumber.

## Rules

- Never write, copy or run `xdg-terminal-exec` in a row; `terminal_stand_in` alone writes it. `scripts/check-smoke-terminal.py` refuses another writer.
- Never let the stand-in terminal run a plugin script; it runs only a byte-identical copy of a fixture under `scripts/smoke/fixtures/plugins/<id>/tui/` or `scripts/smoke/fixtures/tui/<id>/tui/`. `scripts/smoke/rows/tui-guard.sh` is the guard's own control.
- Never authenticate; `scripts/smoke/rows/auth-sentinel.sh`, a core row, reads the sentinel log empty, and `scripts/sandbox-shots.sh` fails a run that logged one.
- Do stand over a sentinel with `sentinel_stand_over` and put it back with `sentinel_restore`; the sentinel row reads the stood-over list empty.
- Do read the argv the stand-in recorded, never a script's effect; each plugin's offline suite runs its TUI scripts.
- Never put a fixture id under both fixture homes; the harness stops at start.
- Do make `devices_ready ROW` a device row's first line; a missing prerequisite or a guard leak records the row not measured and the run exits 77. `scripts/smoke/rows/device-fakes.sh` holds the controls, and `scripts/test-smoke-verdict.sh` pins the verdict.
- Never add a fake in a row; `scripts/smoke/devices.sh` owns every fake, stand-in and guard.
- Do call `devices_up` before enabling a plugin that reads a Bluetooth, Networking or Pipewire singleton, start a fake's process in the row's own shell so its group reaches the teardown list, and stop the private PipeWire only through `devices_audio_stop`.
- Do leave a System plugin enabled or disabled as the row found it.

## The canonical example

`scripts/smoke/rows/device-fakes.sh`: `devices_ready` first, each fake read through the `acme.devices` fixture, and a control per guard. Copy it for a new device row.

## Revisit when

The sandbox gains its own PAM, polkit and session, or Quickshell re-probes a service that starts late.

## Not governed

The sandbox's lifetime and readers, which is [validation-smoke.md](validation-smoke.md); what a fault excuses, which is [validation-smoke-faults.md](validation-smoke-faults.md).
