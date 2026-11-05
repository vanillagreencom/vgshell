# Themes developer reference

Read when changing theme views, apply completion or wallpaper state. The [manifest](manifest.json) owns settings, shortcuts, menu rows and entry points. The [theme architecture](../../../docs/architecture/themes.md) owns package, target and runner rules.

## Service and views

[Service.qml](Service.qml) owns shared browser data, setup status and apply-result reporting after a browser closes. Views use the declared theme capability. They do not start a separate theme runner.

[ThemeView.qml](ThemeView.qml) can close when the new theme is published, before application targets finish. It hands that apply to the service through `report-apply`; the service reports a failed or partial result. Closing a view does not cancel the runner's apply.

[ThemesPanel.qml](ThemesPanel.qml) keeps the apply result available when the panel opens again. The runner's result, not the panel's visibility, determines completion.

## Wallpaper state

[WallpaperState.qml](WallpaperState.qml) reads the runner's background state file. A background instance selects the image for its own screen from that state. It watches the state file rather than the public image symlink.

The runner owns remembered package images and per-screen overrides. The browsers use the same theme capability for those operations. Read [the theme architecture](../../../docs/architecture/themes.md) before changing their persistence or apply behavior.

## Appearance precedence

The gap toggle writes the plugin setting through the configure capability. A theme apply does not change that setting. User appearance choices control whether theme borders, rounding and animations reach Hyprland: [D104](../../../docs/decisions/D104-appearance-values-over-the-theme.md).

Browser-policy setup uses the declared TUI and publishes its availability as status. [Theme targets](../../../docs/architecture/themes.md#targets) owns browser-policy installation and target behavior.

## IPC

The service registers the gap toggle. Panel placement comes from the same setting for a shortcut and a host summon.

<details>
<summary>Show command</summary>

```text
vgshell ipc call shell summon panel vgs.themes '{}'
vgshell ipc call vgs.themes invoke gaps ''
```

</details>
