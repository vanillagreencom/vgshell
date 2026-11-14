# Power

Power shows the battery level in the bar, or the power profile on a computer with no battery, switches the profile and keeps the computer awake for a time you choose. Its section in System Settings, under Hardware, shows what the computer does when you stop using it. It is for laptops and desktops.

![The Power flyout with battery level, Stay awake and profile choices](../../../docs/images/plugins/vgs.power-panel.webp)

![System Settings → Power: the idle timeline with each step's time, then the battery alert and power profile fields](../../../docs/images/plugins/vgs.power-pane.webp)

## Features

- A bar icon and flyout with the battery level, the charging state, the time left and the power profiles.
- Power saver, balanced and, where the hardware has it, performance profiles, also from the launcher.
- A profile of your choice when you connect or disconnect power.
- A low battery alert and an urgent critical alert.
- Stay awake keeps the computer from dimming, locking or sleeping for a duration you choose. A cup in the bar shows when it is on.
- An idle timeline in System Settings: dimming, the screensaver, the lock, the displays turning off and sleep, in order, each with its time. Lock after is changed in place.
- Turns the displays off after you stop using the computer, and sooner while the screen is locked.
- A power menu to log out, suspend, hibernate, reboot, shut down or switch user. Hold an action for 2 seconds to run it. Open the menu from the launcher's System menu, or choose its key under Keys in Power's Settings.
- Wake on LAN for a wired network device that NetworkManager manages.

## Setup

Wake sources, a required step on the plugin's Setup tab, lets only keyboards and pointing devices wake the computer through USB or Bluetooth. The power button and a USB device you connect during sleep also wake it. Allow opens a terminal that asks for your password.

<details><summary>Show command</summary>

```bash
vgshell system apply wake-sources
```

</details>

Open System Settings → Hardware → Power to set display and sleep times, battery alerts and power profiles. Battery settings appear only on a computer with a battery. If the power profiles service is missing, the page offers to install it.

Choose Stay awake in the flyout or Power page for 30 minutes, 1 hour, 2 hours, 4 hours or until you turn it off. The flyout offers the duration you used last. Stay awake ends when its time runs out, you select End, a discharging battery reaches the critical alert level, or VGS restarts. Your idle and sleep settings stay as they are.

Power changes your wired connections only after you set Wake on LAN. When you turn the Power plugin off, the wired connections keep the last value, so turn Wake on LAN off first.
