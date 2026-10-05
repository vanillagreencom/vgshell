# Web Apps

Turn a website into an app. Each web app has its own name and icon in the launcher, and opens its site in its own window of the browser you already have.

## Features

- Add, change and remove web apps on the Web Apps page in Settings. No file to edit.
- Find each web app in the launcher by its name, with the site's icon.
- Select a web app to open its site in a window of its own, without tabs or an address bar.
- Select it again while its window is open, and VGS brings that window into view, on whatever workspace it is.
- Remove a web app, and its launcher entry and icon go with it.

Web Apps is off until you turn it on in Settings.

## Settings

Each web app has these fields under Web apps:

| Setting | What it does |
|---|---|
| Address | The web address of the site. Pick a common site, or choose Custom… and type the address. |
| Name | The name the launcher shows. The site's own name is the default. Choose Custom… to type another. |
| Icon | The site's own icon is the default. Choose Custom… to type the full path or the web address of an image. |

The Details page shows the browser that opens web apps and the state of each web app.

## Browsers

A web app opens in a browser of the Chromium family: Chromium, Google Chrome, Brave, Vivaldi, Microsoft Edge, Opera, Thorium or Helium. VGS uses your default browser when it is one of these, and otherwise the first one it finds. Firefox has no mode that opens a site in its own window, so it cannot open a web app. Web Apps installs no browser: with none of these installed, the Details page and a message say so.

## Known limits

- Turning off or removing Web Apps leaves its web apps in the launcher. Remove them on the Web Apps page in Settings first.
- VGS finds the window of a web app by the window class the browser gives it, which names the site's host and path. Two web apps with the same host and path share one window.
- VGS reads a site's name and icon once, when you add the web app or change its address or icon. A site that changes its icon later keeps the one VGS read.

## Developer interface

| Path | How |
|---|---|
| Setting | `apps`, a list of `{ name, url, title, icon }` in the plugin's `plugins[]` row of `shell.json`. This list is the registry of web apps: the one place the plugin keeps them, which the Settings page alone writes. |
| Desktop entries | `$XDG_DATA_HOME/applications/vgs-webapp-<name>.desktop`, one per web app, which the service alone writes and removes. Each runs `vgshell ipc call vgs.webapps invoke open <name>`. |
| Icons | `$XDG_CONFIG_HOME/vgshell/webapps/icons/<name>.<png, jpg, gif, ico, webp or svg>`, beside `<name>.json`, what the service read from the site. |
| IPC | `open <name>`: brings the web app's window into view, or opens its site. |
| Status | `browser`, the browser that opens web apps, and `apps`, the state of each web app. |

The service is the one owner of the entries and icons. At its start and after each change of the list, it reads each new site once with `curl`, at most 1 MiB in at most 10 s a read: the page for its title and icon links, then the icons in order, each apple-touch-icon first, the largest declared icon next and `/favicon.ico` last, each read against the address the page came from after any redirect. It keeps the first file whose first bytes are an image, and the plugin's default icon when none is. Then it writes every desktop entry and removes each entry and icon the list no longer holds. Quickshell's desktop entry index sees each entry, and the launcher lists it as an installed application.

`open` looks for a window whose class holds `-<host>_<path, with each / as _>-`, the part a Chromium-family browser puts in the class of a site opened with `--app=<address>`, as in `chrome-web.whatsapp.com__-Default`. It brings that window into view through `shell.compositor.reveal`. With no such window, it asks `xdg-mime` for the default browser and runs that browser's desktop entry command with `--app=<address>`. A second `open` within 15 seconds of a launch, before its window maps, opens nothing more.

## Validation

`scripts/smoke/rows/webapps.sh` adds a web app from the Settings window in the nested sandbox, against a site the row serves on the loopback address and a stand-in browser that maps a window with the class a Chromium-family browser gives. It reads the desktop entry, the icon and the launcher's row, opens the web app from the launcher, reads one launch and one window, opens it again and reads no second launch and that window focused, and removes it and reads the entry, the icon and the row gone. Its controls read the default icon for a site with none, and a launch while only a window of another class is open.
