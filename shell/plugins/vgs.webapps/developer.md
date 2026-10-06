# Web Apps developer reference

## Files

The setting `apps` is a list of `{ name, url, title, icon }` in the plugin's `plugins[]` row of `shell.json`. This list is the registry of web apps: the one place the plugin keeps them, which the Settings page alone writes.

`$XDG_DATA_HOME/applications/vgs-webapp-<name>.desktop` is one desktop entry per web app, which the service alone writes and removes. Each entry's command is the plugin's `open` IPC call with the web app's name:

```text
vgshell ipc call vgs.webapps invoke open <name>
```

`$XDG_CONFIG_HOME/vgshell/webapps/icons/<name>.<png, jpg, gif, ico, webp or svg>`, beside `<name>.json`, holds what the service read from the site.

## IPC

`open <name>` brings the web app's window into view, or opens its site.

## Status

`browser` is the browser that opens web apps. `apps` is the state of each web app.

## The service

The service is the one owner of the entries and icons. At its start and after each change of the list, it reads each new site once with `curl`, at most 1 MiB in at most 10 s a read: the page for its title and icon links, then the icons in order, each apple-touch-icon first, the largest declared icon next and `/favicon.ico` last, each read against the address the page came from after any redirect. It keeps the first file whose first bytes are an image, and the plugin's default icon when none is. Then it writes every desktop entry and removes each entry and icon the list no longer holds. Quickshell's desktop entry index sees each entry, and the launcher lists it as an installed application.

The service reads a site's name and icon once, when the web app is added or its address or icon changes. A site that changes its icon later keeps the one the service read.

`open` looks for a window whose class holds `-<host>_<path, with each / as _>-`, the part a Chromium-family browser puts in the class of a site opened with `--app=<address>`, as in `chrome-web.whatsapp.com__-Default`. It brings that window into view through `shell.compositor.reveal`. With no such window, it asks `xdg-mime` for the default browser and runs that browser's desktop entry command with `--app=<address>`. A second `open` within 15 seconds of a launch, before its window maps, opens nothing more.

Two web apps with the same host and path share one window, since the class names only those two parts.
