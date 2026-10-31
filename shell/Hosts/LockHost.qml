import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Commons

// The session lock surfaces. The core owns the one WlSessionLock and lends
// it through the `lock` capability: the holder asks for a lock and hands
// over a Component, and this host builds that component once per screen
// inside each lock surface and assigns its `screen`. The surface colour
// stands alone while no content is handed over, which is how a lock whose
// holder was unloaded stays locked.
//
// While the cover presentation sits in the lock (CoverPresentation's
// `secure` placement), each surface holds that screen's cover under an
// input barrier and builds no lock content: nothing under the cover exists
// to take focus or input. Disabling the content is not enough: a disabled
// field's forceActiveFocus() still moves its focus scope's focus away from
// the barrier, so a key reaches neither: a probe field focused the way
// LockView focuses its own, on the turn after it is built, did that in the
// third nested run of the VGS-2097 feasibility probe (2026-10-31). The
// barrier's first input ends the cover on every screen, and only then is
// the lock content built and focused, so the next input reaches it.
// WlSessionLock builds one surface per screen when `locked` turns true,
// and a surface is only ever destroyed, never hidden:
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/WlSessionLock/
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/WlSessionLockSurface/
Scope {
    WlSessionLock {
        locked: Capabilities.sessionLock.lockRequested
        onSecureChanged: Capabilities.sessionLock.lockSecure = secure
        // A lock that goes while still requested was refused or ended by
        // the compositor; the owner drops the request (SessionLock).
        onLockedChanged: if (!locked) Capabilities.sessionLock.compositorEnded("finished")

        WlSessionLockSurface {
            id: surface
            color: Theme.color.background
            readonly property bool covered: Capabilities.covers.placement === "secure"

            Loader {
                id: content
                anchors.fill: parent
                focus: !surface.covered
                sourceComponent: surface.covered ? null : Capabilities.sessionLock.lockContent
                onLoaded: {
                    if (!("screen" in item)) {
                        console.error("lock host: lock content declares no screen property");
                        return;
                    }
                    item.screen = surface.screen;
                }
            }

            // The cover's place on this screen: CoverHost moves the
            // screen's cover instance in while the presentation is secure.
            Item {
                id: secureRoot
                anchors.fill: parent
                readonly property var at: surface.screen
                property var release: null
                function offer() {
                    if (release !== null) release();
                    release = at === null ? null : Capabilities.covers.registerSecureRoot(at, secureRoot);
                }
                onAtChanged: offer()
                Component.onCompleted: offer()
                Component.onDestruction: if (release !== null) release()
            }

            CoverBarrier {
                anchors.fill: parent
                up: surface.covered
                onConsumed: cause => {
                    console.info("lock host: cover=dismissed by=" + cause);
                    Capabilities.covers.dismissByInput();
                    content.forceActiveFocus();
                }
            }
        }
    }

    // Another client can replace a confirmed lock and unlock the session
    // with no event to this one; SessionLock.compositorReading reads
    // Hyprland's own state every two seconds while the lock is confirmed.
    Timer {
        interval: 2000
        repeat: true
        running: Capabilities.sessionLock.lockSecure
        onTriggered: if (!lockReading.running) lockReading.running = true
    }

    Process {
        id: lockReading
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { id: lockReadingOut; waitForEnd: true }
        onExited: code => Capabilities.sessionLock.compositorReading(code === 0 ? lockReadingOut.text : "")
    }
}
