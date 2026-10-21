import QtQuick
import "SetupGate.js" as Gate

// The Cloned voice setup row (SetupGate.clonedVoiceStep) uses the same
// setup status reader as local voice, read again after either clone TUI
// ends, after each requirement scan and when the voice the daemon runs
// changes. `provider` is that voice (Service.voiceProvider).
LocalRuntime {
    property string provider: ""
    readonly property double readerStartedAtMs: Date.now()
    readonly property var removeState: shell === null ? null : shell.tui.state["clone-voice-remove"]
    readonly property var removedAt: removeState === null || removeState === undefined ? null : removeState.endedAt
    statusKey: "clonedVoiceSetup"
    tuiName: "clone-voice"
    command: ["python3", "-I", program, "clone", "status"]
    shape: value => Gate.clonedVoiceStep(value, provider)
    onRemovedAtChanged: {
        if (removedAt === null) return;
        // TUI state keeps the last ended record across restarts; a reader
        // must not turn off a setting for an old Remove recording run.
        const endedMs = Date.parse(removedAt);
        if (removeState.code === 0 && !isNaN(endedMs) && endedMs >= readerStartedAtMs
                && shell !== null && shell.settings.clonedVoice === true)
            Qt.callLater(unsetClonedVoice);
        refresh();
    }
    onProviderChanged: refresh()

    function unsetClonedVoice() {
        if (shell === null) return;
        const reply = shell.configure.unset("clonedVoice");
        if (reply !== "ok") console.warn("jarvis-clone: setting=unwritten reply=" + reply);
    }
}
