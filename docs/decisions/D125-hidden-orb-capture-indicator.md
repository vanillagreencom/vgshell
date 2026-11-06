# D125: Hidden Jarvis uses the presented bar J as its capture indicator

[← Decision Index](INDEX.md)

**Date**: 2026-11-06

**Status**: Active

**Research**: [VGS-2313](https://linear.app/vanillagreen/issue/VGS-2313/jarvis-hide-jarvis-keeps-it-listening-and-speaking-without-the-orb), with the [owner approval](https://linear.app/vanillagreen/issue/VGS-2313/jarvis-hide-jarvis-keeps-it-listening-and-speaking-without-the-orb#comment-1b4b7dcc-5d5f-4312-8527-80369a0c36ea).

**Supersedes**: [D064](D064-jarvis-child-lease.md), only its capture-indicator selection while the orb is hidden. Capture still requires Session admission after an indicator is presented. D064's child stdin lease, one wire judge, daemon-owned audio PID namespace and prohibition on a systemd unit remain unchanged.

**Decision**: While Jarvis is hidden, the bar J presented on the focused output with its listening badge replaces the orb as the capture indicator. Session admits microphone capture only after that indicator is presented, and withdraws capture when it disappears. A configured widget, an invisible bar or a widget on another output does not qualify. Hide is unavailable without the qualifying bar indicator. This changes neither the conversation lifetime nor the other child-lease requirements in D064.

**Why**: The owner wants the orb gone without ending the conversation. Requiring the orb would defeat Hide; accepting an unpresented bar widget would permit an unseen microphone. The presented J preserves the visible-capture rule at the cost of refusing hidden capture when that indicator is absent.

**Rejected**: Keep the orb mandatory for capture, or treat a configured J as sufficient. The first stops hidden listening; the second grants capture when a removed or hidden bar shows no indicator.

**Revisit when**: Hidden capture needs to work without a presented J on the focused output, or the shell cannot reliably observe that J and its listening badge being presented. Either change requires a new indicator decision, not an exemption from presentation.
