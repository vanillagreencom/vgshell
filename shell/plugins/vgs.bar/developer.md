# Bar developer reference

Read when changing builtin widgets, section layout or bar visibility. The [manifest](manifest.json) owns settings, shortcuts and status declarations.

## Builtins and sections

[Bar.qml](Bar.qml) declares builtin labels and families and receives `widgetLayout` from the core. Its keyed model owns the Loader delegates. Each delegate owns a registered [Builtin.qml](Builtin.qml) wrapper, so the core can place, drag and hide it through the same path as a plugin widget.

Builtin IDs retain their identity across sections. Hiding removes a layout entry; it does not disable the bar or change its settings. The Settings switch restores a fixed builtin's declared section and neighbour order. Repeated spacers use the declared builtin families and the core's builtin-add path.

The side zones keep their available width during a drag. Their section objects expose the visible geometry, `reveal` and `step` to the core, so a preview gap and a dropped widget remain reachable when a section overflows. Keep scrolling in that zone contract rather than adding a separate drag layout.

## Visibility and IPC

[Service.qml](Service.qml) registers the visibility handlers while this bar is active. `toggle` changes the persistent `hidden` setting. `hide` and `reveal` change only the in-memory `hiddenUntilReveal` status; a restart ends that temporary hide.

The bar shows only when neither hide applies. `reveal` does not override the persistent setting, and `toggle` can still change that setting during a temporary hide. The service header defines the replies.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.bar invoke toggle ''
vgshell ipc call vgs.bar invoke hide ''
vgshell ipc call vgs.bar invoke reveal ''
```

</details>
