# QML rests only on a behaviour that is proved

Read before writing QML, for every Quickshell and Qt fact the QML rests on.

## The approach

A piece of QML relies on a Quickshell or Qt behaviour only where a source line, a comment at the site that depends on it, or a test proves it on the shipped versions, Quickshell 0.3.1 and Qt 6.11.2. A behaviour remembered from another Qt is not relied on; the Quickshell reference on Context7 is read first. The rules below are the behaviours this shell has proved and the code shapes that follow from them.

## Why

A watcher that rebuilds during a read loses the change in between, a signal that fires after its object is cleared leaves a handler reading nothing, and a scale change that notifies no binding leaves a surface drawn at the old size. Each of these was read on the shipped versions and cost a round; a rule at the site costs one line.

## Rules

- Do restart a `Process` from `runningChanged` when `running` is false; `exited` fires with the process already cleared. Do attach a stdout parser before the process starts; a null parser closes the channel for good, and a `SplitParser` drains before `exited`.
- Do read a file on change through `WatchedFile` in `qs.Commons`, never a reloaded `FileView`: `FileView.reload()` during a read starts nothing and rebuilds its watcher after the read starts, so a change in between is lost. Do create the directory a `FileView` watches before the view is built; an absent directory is never watched. `scripts/test-vgshell.sh` and `scripts/smoke/rows/launcher.sh` pin the directory rule.
- Do block a write that must survive SIGTERM with `blockWrites: true`; SIGTERM runs no handler, and the default write lost the file in every stop read.
- Do publish a colour as a string and hand a reader a deep copy; `Object.freeze` does not protect a colour's channels and leaves an array's elements writable in this engine.
- Do assign object-valued properties after `createObject`; the initial-property path drops functions and arrays, and a pointer handler with a `parent` binding on a null parent crashes the engine.
- Do read the source property inside a change handler; a dependent binding may still hold its old value.
- Do write every copy of a core file before loading the first; the type loader caches a directory listing, and `Qt.createComponent` fails with a case mismatch for a file written after the listing.
- Do call `forceLayout()` before reading a `Column`'s children in the turn they changed. `scripts/smoke/rows/toasts.sh` pins it.
- Do set a nested output's scale before the shell starts; `devicePixelRatio` notifies on a signal a scale change does not fire. `scripts/smoke/rows/hidpi.sh` pins it.
- Do focus a plugin's `initialFocus` only once the host window is active, with the summon reason; an earlier focus reports the activation reason. Do keep Tab inside a dialog with `Keys.onTabPressed` on each action; an unaccepted Tab moves focus before any parent sees it. `scripts/smoke/rows/surfaces.sh` and `scripts/qml-tests/tst_dialog.qml` pin both.
- Do judge a missing folder by a `FolderListModel`'s `status === Null`, never by a `folder` binding, and never let a run's end rest on a `FolderListModel` alone; it can miss a change ([D043](../decisions/D043-tui-run-ends-by-lock-release.md)).
- Do ship a passive shader as a `.qsb` pack with no texture and no loop, and judge its rendering by captured pixels, not `ShaderEffect.status`, which stays uncompiled for repeated instances. `scripts/check-voiceorb-shader.py` pins the pack; the Gallery row reads the pixels.
- Do load an inline image through `ImagePool` before a text names it, elide a text with images yourself under `Text.ElideNone`, and wrap it with `Text.Wrap`; a StyledText `<img>` otherwise decodes on the GUI thread, and Qt's elision draws an image over the elided line. `scripts/qml-tests/tst_imagetext.qml` pins each.
- Do start the shell with `QS_PIPEWIRE_IMMEDIATE_RECONNECT`, and give a D-Bus fake every property Quickshell binds as required; Quickshell looks for bluez, NetworkManager and PipeWire once, when the singleton is first read. `scripts/test-vgshell.sh` and `scripts/smoke/rows/sound.sh` pin the first.
- Do declare `PointerCursor` on every click area and `Qt.NoButton` on every view; the pointer rules are [components.md](components.md).

## The canonical example

`shell/Commons/WatchedFile.qml`: the one reader every file watcher composes, with the reload and watcher facts it rests on stated in its header. Copy its shape: the fact, the version it was read on, and the rule that follows.

## Revisit when

A Quickshell or Qt release changes `FileView`, `Process`, `createObject`, the IPC CLI or the window types; the preflight floor in `bin/vgshell` names the versions every fact above was read on.

## Not governed

What Hyprland does with a request, which is [runtime-hyprland.md](runtime-hyprland.md); the component contract, which is [components.md](components.md).
