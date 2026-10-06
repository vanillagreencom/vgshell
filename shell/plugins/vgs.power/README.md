# Power

Power shows the battery level and the power profile in the bar, and switches the profile. It is for laptops, and for desktops that run a power profile service.

![The Power flyout with battery level and profile choices](../../../docs/images/plugins/vgs.power-panel.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2, over the sandbox's fake battery.

## Features

- A bar icon with the battery level and the active power profile. On a desktop it shows the profile alone, and it hides when profile control is unavailable too.
- A flyout with the battery level, the charging state, the time estimate and the power profiles.
- Use power saver, Use balanced and Use performance in the launcher.
- Switches to the profile you choose when you connect or disconnect power. It leaves the profile alone when VGS starts.
- Sends a low battery alert and an urgent critical alert, each once per discharge.
- Performance is unavailable on hardware without a performance profile.

## Settings

| Setting | What it changes |
| --- | --- |
| Low battery alert | The battery level that sends an alert while discharging. |
| Critical battery alert | The battery level that sends an urgent alert while discharging. |
| When charging | The profile to use after you connect power. |
| On battery | The profile to use after you disconnect power. |
