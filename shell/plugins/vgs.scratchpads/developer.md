# Scratchpads developer reference

Read when changing pad startup, toggles or window adoption. The [manifest](manifest.json) owns the pad setting schema and names it in `hyprland.pads`. The [Hyprland configuration contract](../../../docs/architecture/hyprland.md#configuration-layer) owns the generated rules and special-workspace toggles.

## Service and window ownership

[Service.qml](Service.qml) registers each pad's shortcut and tracks its window through compositor events. A press toggles the pad through the core. An empty workspace starts the app only when no known window can be moved back. A pad refused by the layer, including a conflicting class, starts no app and reports the refusal.

While an app starts, presses change the pending wish. Its mapped window is shown only if the user still wants it. Startup without a matching window ends in a notice. Initial window adoption precedes preload, so a shell restart does not start a second copy of an existing app.

[Background.qml](Background.qml) draws nothing. It is active only while a pad is shown on that screen and handles a press beside the pad. The service publishes shown pads and screen choices for that instance.

## Geometry and validation

A pad uses its screen's free area. Hyprland's special-workspace scale can reduce that size. Pad animation also changes Hyprland's shared special-workspace animation until configuration reload; it is not isolated per pad.

[The nested validation row](../../../scripts/smoke/rows/scratchpads.sh) covers Settings-created pads, startup, geometry, repeated presses, adoption and removal. Change the service and the generated layer together when changing that interaction.
