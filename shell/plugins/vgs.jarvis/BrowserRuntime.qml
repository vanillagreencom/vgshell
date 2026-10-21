import QtQuick
import "SetupGate.js" as Gate

// Browser readiness uses the same setup status reader as local voice, and
// publishes its reading unchanged: the manifest makes it an optional Setup
// step, which the Settings page draws as Optional until it is done. It also
// writes the browser driver's own row, whose Install, or Update for a driver
// below the manifest's floor, raises the requirement notice; setup is
// withheld until a scan finds the driver.
LocalRuntime {
    readonly property string driver: "agent-browser"
    readonly property var driverValue: shell === null ? null : Gate.flooredValue(driver, shell.requirements.missing, shell.requirements.outdated)
    statusKey: "browser"
    tuiName: "setup-browser"
    requires: [driver]
    program: String(Qt.resolvedUrl("backend/browser-setup.js")).replace(/^file:\/\//, "")
    command: ["node", program, "status"]
    onDriverValueChanged: {
        if (driverValue === null) return;
        const reply = shell.status.set("browserDriver", driverValue);
        // A scan publishes the next instance before it reads versions, so
        // the outdated list moves once more under the instance it retired.
        if (!shell.status.isOk(reply)) throw new Error("jarvis: " + reply);
    }
}
