import QtQuick
import "SetupGate.js" as Gate

// Browser readiness uses the same setup status reader as local voice. It also
// writes the browser driver's own row, whose Install raises the requirement
// notice; setup is withheld until a scan finds the driver.
LocalRuntime {
    readonly property string driver: "agent-browser"
    readonly property var driverValue: shell === null ? null : Gate.requirementValue(driver, shell.requirements.missing)
    statusKey: "browser"
    tuiName: "setup-browser"
    requires: [driver]
    program: String(Qt.resolvedUrl("backend/browser-setup.js")).replace(/^file:\/\//, "")
    command: ["node", program, "status"]
    onDriverValueChanged: {
        if (driverValue === null) return;
        const reply = shell.status.set("browserDriver", driverValue);
        if (reply !== "ok") throw new Error("jarvis: " + reply);
    }
}
