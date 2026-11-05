# D118: The screen freeze also writes its held frame for the holder

[← Decision Index](INDEX.md)

**Date**: 2026-11-03

**Status**: Active

**Research**: [VGS-2232](https://linear.app/vanillagreen/issue/VGS-2232)

**Refines**: [D115](D115-screen-freeze-is-a-core-surface.md), adding the held frame as files beside the drawn freeze

**Decision**: A holder that passes `still` to `shell.screencopy.freeze` gets the frame it froze as files: once every screen shows its frame, the core writes each screen's frame at its own scale, and at every greater scale in the layout, as PPM bands bounded by `shell/Core/FreezeBands.js` (which also owns the exception for the fewest rows both scales cut whole) into `$XDG_RUNTIME_DIR/vgshell/freeze/<serial>`, a directory `ScreenFreeze` makes for the hold with mode 0700 and removes when the hold ends, and answers `still` at most once, with every band's path or with `failed: still=<reason>`. A hold whose frame never shows, or whose band grab never returns, gets no `still` answer, as it gets no `done`, so the holder bounds its wait. One chain of bands covers every screen, each band a hidden `ShaderEffectSource` over a strip of the frame. The GUI thread requests each grab and saves its result. Render-thread readback can hold the GUI thread at synchronization; the band's size bounds that work too. Each band's callback asks for the next before it saves its own. With `cursor`, a second, hidden `ScreencopyView` that draws the pointer is the saved source, and a screen counts as framed only once both views have content. The holder names no path. `vgs.capture` crops each undelayed screenshot selection and each text selection from these frames and runs no grim around the selector; a delayed screenshot and a recording ask for no still.

**Why**: The whole-layout grim the worker ran before the freeze took 212 ms (187-329) of the 453 ms (422-632) from the key press to the selector, in the nested sandbox at the owner's geometry, two scale-2 outputs, at a 5-minute load of 11.6 to 13.8, not in a live session ([VGS-2232 round-2 trace](https://linear.app/vanillagreen/issue/VGS-2232#comment-e0675c7d)), and the freeze captured the same screen again right after it. Quickshell has no image writer, and `ItemGrabResult.saveToFile` runs on the GUI thread: a whole 6016x3384 frame took 29-43 ms there, past a 16.7 ms frame (nested sandbox, NVIDIA, Qt 6.12.0, unit VGS-2232-measure-1793759881, as `FreezeBands.js` cites it), so the frame is cut into bands. The native render/readback of a band also held the GUI thread past a frame at low load ([VGS-2310 source trace](https://linear.app/vanillagreen/issue/VGS-2310#comment-cb5eb6e5-8175-499e-92d5-98101a8b582c)); `FreezeBands.js` owns the measured pixel limit for that work. The core owns the directory because a path a plugin named would let it choose where the shell writes, and one shell runs per runtime directory. The pointer view is hidden so the freeze a person sees draws no still pointer under the selector's.

**Rejected**: Keeping the grim before the freeze, and its 212 ms. Starting grim with the freeze and showing the freeze only after it, which still captured twice and could save the freeze surface. Saving each screen in one call, which stalled the GUI thread past a frame. A path the plugin names.

**Revisit when**: Quickshell gives QML an image writer off the GUI thread or a `ScreencopyView` image export, or a holder needs the frame of some screens only.
