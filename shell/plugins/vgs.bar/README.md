# Bar

The bar shows workspaces, the clock and plugin buttons at the top of each screen.

![The bar with its workspaces, its clock and plugin widgets](../../../docs/images/plugins/vgs.bar-bar.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- One bar per screen, above windows, with space reserved so windows never sit under it.
- Workspaces: one number per workspace, lowest first, the focused one highlighted. A click focuses that workspace.
- The clock: the date and time in the preset or custom format you choose.
- A click on the clock opens a calendar under it, on this month with today marked. Left and Right, or its arrows, change the month. A click on a day opens that day in your web calendar in the default browser.
- Three sections for plugin buttons. Enabling a plugin on its Settings page places its button in the section the plugin chooses.
- Right-click an empty part of the bar and choose Add separator or Add gap to put a thin line or a little empty room where you clicked. Drag either to move it; right-click it and choose Remove separator or Remove gap to take it away.
- Colours, the font and every size follow the theme.
- Hide top bar, in the launcher's Style menu, hides the bar on every screen and gives its space to windows. The row then reads Show top bar.
- `SUPER+SHIFT+SPACE` hides or shows the bar the same way. The Keys row on the plugin's Settings page changes it.
- Only one bar is active at a time. Disabling it hides every plugin button until a bar is enabled again.

## Settings

| Setting | What it changes |
| --- | --- |
| Clock format | How the bar's clock shows the date and time. |
| Calendar | The web calendar a click on a day opens: Google Calendar, Outlook, or your own address with {year}, {month} and {day}. |
| Hide top bar | Hide the bar on every screen and give its space to windows. |

[developer.md](developer.md) states the configuration keys that place the built-ins and the plugin buttons.
