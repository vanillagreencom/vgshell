import QtQuick
import QtTest
import Quickshell.Services.Pipewire
import Quickshell.Io
import "../../shell/plugins/vgs.jarvis"

// The environment the Jarvis service hands its daemon. The service clears
// the shell's environment, so a variable the desktop tool executors pass to
// their commands reaches the daemon only by name here. The stand-in
// Quickshell.env answers "env:NAME", so each value also names its source.
Item {
    Service { id: service }
    QtObject {
        id: firstSource
        property bool ready: true
        property QtObject audio: QtObject { property bool muted: false }
    }
    QtObject {
        id: secondSource
        property bool ready: true
        property QtObject audio: QtObject { property bool muted: true }
    }

    QtObject {
        id: nonAudioSource
        property bool ready: true
        property var audio: null
    }

    TestCase {
        name: "jarvisService"

        function init() {
            Pipewire.ready = false;
            Pipewire.defaultAudioSource = null;
            firstSource.ready = true;
            firstSource.audio.muted = false;
            secondSource.ready = true;
            if (secondSource.audio !== null) secondSource.audio.muted = true;
        }

        function test_default_microphone_observation_and_toggle() {
            compare(service.microphoneMute.kind, "unavailable");
            compare(service.toggleMicrophoneMute(), "refused: microphone=unavailable");
            Pipewire.defaultAudioSource = firstSource;
            compare(service.microphoneMute.kind, "unavailable", "an unsynced PipeWire server gives no mute reading");
            Pipewire.ready = true;
            compare(service.microphoneMute.kind, "ready");
            compare(service.microphoneMute.muted, false);
            firstSource.audio.muted = true;
            compare(service.microphoneMute.muted, true, "external mute follows the source");
            Pipewire.defaultAudioSource = secondSource;
            compare(service.microphoneSource, secondSource);
            compare(service.toggleMicrophoneMute(), "ok");
            compare(secondSource.audio.muted, false, "toggle acts on the new default");
            compare(firstSource.audio.muted, true, "toggle leaves the former default alone");
            secondSource.ready = false;
            compare(service.microphoneMute.kind, "unavailable", "a source still syncing stays unknown");
            compare(service.toggleMicrophoneMute(), "refused: microphone=unavailable");
            Pipewire.defaultAudioSource = nonAudioSource;
            compare(service.microphoneMute.kind, "unavailable", "a source without an audio interface stays unknown");
            Pipewire.defaultAudioSource = null;
            compare(service.microphoneMute.kind, "unavailable", "a missing default stays unknown");
        }

        function daemonProcess() {
            const found = ProcessRegistry.processes.filter(process =>
                process.command.length > 1 && String(process.command[1]).endsWith("/backend/jarvisd.js"));
            compare(found.length, 1, "one daemon process");
            return found[0];
        }

        function test_daemon_environment() {
            const process = daemonProcess();
            verify(process.clearEnvironment, "the daemon inherits nothing");
            const expected = { LANG: "C.UTF-8" };
            for (const name of ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME",
                "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS",
                "YDOTOOL_SOCKET", "SSH_AUTH_SOCK", "VGS_TEST_RUN", "VGS_JARVIS_TRACE", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "COPILOT_HOME",
                "PI_CODING_AGENT_DIR"])
                expected[name] = "env:" + name;
            const sorted = value => Object.keys(value).sort().map(name => name + "=" + value[name]).join("\n");
            compare(sorted(process.environment), sorted(expected));
        }
    }
}
