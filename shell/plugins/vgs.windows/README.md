# Windows

Windows sets the corner radius and the border width of windows and flyouts, and VGlass, the frosted glass of the launcher, notifications and windows. It is for anyone who wants rounder, squarer or thinner window edges than the theme gives, or more or less glass.

It also gives you a key that locks a window group, and tells you whether the group is locked or unlocked.

![The Windows section of the System Settings window, with the Corner radius and Border width rows](../../../docs/images/plugins/vgs.windows-pane.webp)

## Features

- A Windows section under Appearance in the System Settings window.
- Each value shows Set by theme until you change it. Use theme value puts the theme's value back.
- One corner radius for windows, flyouts and grouped window tabs.
- VGlass on for every glass surface, off for every one, or each surface's own choice.
- The values stay in effect when you disable this plugin.
- `SUPER+CTRL+G` locks or unlocks the group of the focused window, and a notification tells you which. The key is under Keys on the plugin's Settings page.

## Setup

| Value | What it changes |
| --- | --- |
| Corner radius | The corners of windows, flyouts and grouped window tabs, from 0 to 32 px. |
| Border width | The window border, from 0 to 20 px. |
| VGlass | Each surface decides, On for every glass surface or Off for every glass surface. |
| Windows | Whether your windows draw with glass while each surface decides. |
| Glow | Whether your focused window has a soft glow while window glass is on. |

A value you set applies over your own Hyprland config. Where your config sets another value, the row shows it and offers Use my Hyprland value, which makes VGS stop setting it. The group lock key needs `hyprland.lua`; with a classic `hyprland.conf` it changes nothing.
