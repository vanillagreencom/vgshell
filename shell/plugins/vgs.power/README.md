# Power

Power shows the battery level and the power profile in the bar, and switches the profile. Its section in System Settings, under Hardware, shows what the computer does when you stop using it. It is for laptops and desktops.

![The Power flyout with battery level and profile choices](../../../docs/images/plugins/vgs.power-panel.webp)

![System Settings → Power: the idle timeline with each step's time, then the battery alert and power profile fields](../../../docs/images/plugins/vgs.power-pane.webp)

## Features

- A bar icon with the battery level and the active power profile. On a desktop it shows the profile alone, and it hides when profile control is unavailable too.
- A flyout with the battery level, the charging state, the time estimate and the power profiles.
- Use power saver, Use balanced and Use performance in the launcher.
- With a battery, switches to the profile you choose when you connect or disconnect power. It leaves the profile alone when VGS starts.
- Sends a low battery alert and an urgent critical alert, each once per discharge.
- Performance is unavailable on hardware without a performance profile.
- An idle timeline in System Settings: each step, such as dim, screensaver and lock, in order with its time. Select a time to open the field that sets it. A step that starts before an earlier step shows a warning, such as a lock before the screensaver.
- Turns every display off after you stop using the computer, and sooner while the screen is locked. A key press or pointer movement turns them on if your Hyprland config lets it, and the Power section of System Settings shows if each one can.
- A power menu with Log out, Suspend, Hibernate, Reboot, Shut down and Switch user. It lists only the actions this computer can do: Hibernate where the system allows it, and Switch user where the login screen can switch users. Hold Space, Enter or the pointer on an action for 2 seconds to run it; release early to cancel. Open it from the launcher's System menu, or choose its key under Keys in Power's Settings. It has no key until you choose one.

## Settings

The battery rows show only on a machine with a battery. The two profile rows also need the power profiles service, which is optional: without it, Power's section in System Settings offers to install it. Wake on LAN shows only on a machine with a wired network device that NetworkManager manages. Without a battery, Power sets one profile from the bar, and Details says so. The same settings show in Power's section of System Settings. If Power cannot save Wake on LAN, both views show the problem under the switch.

| Setting | What it changes |
| --- | --- |
| Turn displays off | How long the displays stay on without input. While locked, they turn off after a short pause instead. Never keeps them on while locked too. |
| Low battery alert | The battery level that sends an alert while discharging. |
| Critical battery alert | The battery level that sends an urgent alert while discharging. |
| When charging | The profile to use after you connect power. |
| On battery | The profile to use after you disconnect power. |
| Wake on LAN | Whether another device on the wired network can wake the computer from sleep. Power changes your wired connections only after you set this switch. Then it saves the value on every wired connection and, while it is on, on a connection added later. A connection in use takes it the next time it connects. When you turn Power off, the wired connections keep the last value, so turn Wake on LAN off first. |
