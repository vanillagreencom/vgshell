import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.Commons
import qs.Ui
import "GreeterLogic.js" as Logic

// One screen of the login screen, which the core's greeter host,
// shell/greeter.qml, builds on every screen; it is no entry point of the
// plugin. The host assigns `screen` and `interactive`: every screen draws
// the theme's background under the scrim and the time, and the one
// interactive screen also lists the accounts and the sessions and talks to
// greetd (docs/architecture/greeter.md). The look is the lock screen's
// (vgs.lock's LockView), so boot, lock and unlock read as one product; the
// theme and the background are the copies the service keeps under the
// greeter's XDG_CONFIG_HOME.
//
// Keyboard first: the password field holds the focus; Tab moves through
// the account, the password, the session and the power buttons. Enter in
// the field starts the login: the typed password answers greetd's first
// hidden prompt, and with the field empty a fingerprint or another PAM
// method answers. Escape cancels a login in progress.
//
// It prints, for the journal and the smoke row: `greeter:
// greetd=<available|unavailable>`, `greeter: users=<n>`, one `greeter:
// session id=<id> type=<type> state=<available|unavailable> name=<name>`
// per listed session, `greeter: refused: session=<path> reason=<key>` per
// file that is no valid entry, `greeter: sessions=<n>
// preselected=<id|none>`, and, from the interactive screen, `greeter:
// theme=<name> file=<loaded|absent|refused|unreadable>` once the theme file
// is read and `greeter: background=<ready|unloaded> path=<path>` once the
// background image loads or fails to, as it does while there is no copy;
// each of those two prints again only when its reading differs from the
// one it printed last.
Item {
    id: root

    property var screen: null
    property bool interactive: false

    property bool started: false
    property var users: []
    property bool usersRead: false
    property var sessionList: []
    property bool sessionsRead: false
    property var entries: []
    property var memory: Logic.emptyMemory()
    // The memory file's text as last read or written, "" for none: a write
    // of the same bytes reports nothing, so a login that changes nothing
    // launches without one.
    property string memoryText: ""
    property bool memoryRead: false
    property int userIndex: -1
    property string sessionId: ""

    // The login in progress: whether greetd holds a session, the password
    // for its first hidden prompt, whether the field answers a prompt now,
    // and the launch waiting on the memory write.
    property bool busy: false
    property var pending: null
    property bool asking: false
    property bool echo: false
    property var launching: null
    property string message: ""
    property bool messageError: false

    readonly property string helperPath: String(Qt.resolvedUrl("bin/sessions")).replace(/^file:\/\//, "")
    readonly property string backgroundPath: Paths.configDir + "/" + Logic.BACKGROUND
    readonly property var chosenSession: {
        for (let i = 0; i < sessionList.length; i++) if (sessionList[i].id === sessionId) return sessionList[i];
        return null;
    }
    readonly property var sessionLabels: sessionList.map(s => ({ label: s.available ? s.name : s.name + " (unavailable)" }))

    onInteractiveChanged: start()
    Component.onCompleted: start()

    // The theme and background lines, "" until each is read; the host makes
    // the view interactive after it loads, so start() prints what was read
    // before that. The image reloads, passing through Loading back to the
    // same status, whenever its sourceSize follows a new surface size, so a
    // line prints only when it differs from the last one printed.
    readonly property string themeLine: Theme.fileState === "pending" ? "" : "greeter: theme=" + Theme.name + " file=" + Theme.fileState
    readonly property string backgroundLine: backgroundImage.status === Image.Ready ? "greeter: background=ready path=" + backgroundPath
        : backgroundImage.status === Image.Error ? "greeter: background=unloaded path=" + backgroundPath : ""
    property string themePrinted: ""
    property string backgroundPrinted: ""
    onThemeLineChanged: printReadings()
    onBackgroundLineChanged: printReadings()

    function printReadings() {
        if (!started) return;
        if (themeLine !== "" && themeLine !== themePrinted) {
            themePrinted = themeLine;
            console.info(themeLine);
        }
        if (backgroundLine !== "" && backgroundLine !== backgroundPrinted) {
            backgroundPrinted = backgroundLine;
            console.info(backgroundLine);
        }
    }

    function start() {
        if (!interactive || started) return;
        started = true;
        console.info("greeter: greetd=" + (Greetd.available ? "available" : "unavailable"));
        printReadings();
        memoryFile.path = Paths.stateDir + "/greeter.json";
        usersProc.running = true;
        listProc.command = ["bash", helperPath, "list"].concat(Logic.dataDirs(Quickshell.env("XDG_DATA_DIRS")));
        listProc.running = true;
        Qt.callLater(focusField);
    }

    function focusField() {
        field.forceActiveFocus();
    }

    function userName() {
        if (users.length === 0) return nameField.text.trim();
        return userIndex >= 0 && userIndex < users.length ? users[userIndex].name : "";
    }

    // Once the accounts, the sessions and the memory are read: the last
    // user and their session.
    function choose() {
        if (!usersRead || !sessionsRead || !memoryRead) return;
        userIndex = Logic.preselectUser(users, memory);
        if (users.length === 0) nameField.text = memory.lastUser;
        sessionId = Logic.preselect(sessionList, memory, userName());
        console.info("greeter: sessions=" + sessionList.length + " preselected=" + (sessionId === "" ? "none" : sessionId));
    }

    function readSessions(found) {
        const result = Logic.sessions(entries, found);
        for (const r of result.refused) console.warn("greeter: refused: session=" + r.path + " reason=" + r.reason);
        for (const s of result.sessions) console.info("greeter: session id=" + s.id + " type=" + s.type + " state=" + (s.available ? "available" : "unavailable") + " name=" + s.name);
        sessionList = result.sessions;
        sessionsRead = true;
        choose();
    }

    function say(text, error) {
        message = text;
        messageError = error;
    }

    function reset() {
        busy = false;
        pending = null;
        asking = false;
        echo = false;
        launching = null;
        field.text = "";
        Qt.callLater(focusField);
    }

    function submit() {
        if (busy) {
            if (!asking) return;
            asking = false;
            const answer = field.text;
            field.text = "";
            Greetd.respond(answer);
            return;
        }
        if (!Greetd.available) {
            say("The login service is not running", true);
            return;
        }
        const user = userName();
        if (user === "") {
            say("Choose an account", true);
            return;
        }
        if (chosenSession === null || !chosenSession.available) {
            say("Choose a session that can start", true);
            return;
        }
        pending = field.text.length > 0 ? field.text : null;
        field.text = "";
        busy = true;
        say("", false);
        Greetd.createSession(user);
    }

    function cancel() {
        if (!busy) return;
        Greetd.cancelSession();
        reset();
        say("", false);
    }

    // greetd accepted the login: remember the user and the session, then
    // launch. greetd expects the greeter to end soon after the launch.
    function launch() {
        const request = Logic.launchRequest(chosenSession);
        const text = Logic.remember(memory, userName(), chosenSession.id, users);
        if (text === memoryText) {
            Greetd.launch(request.command, request.environment);
            return;
        }
        launching = request;
        memoryFile.setText(text);
    }

    function launchNow() {
        const request = launching;
        launching = null;
        if (request !== null) Greetd.launch(request.command, request.environment);
    }

    Connections {
        target: root.interactive ? Greetd : null
        function onAuthMessage(text, error, responseRequired, echoResponse) {
            const answer = Logic.promptAnswer(responseRequired, echoResponse, root.pending);
            root.pending = answer.pending;
            if (answer.respond !== null) {
                Greetd.respond(answer.respond);
                return;
            }
            root.say(text, error);
            root.asking = answer.ask;
            root.echo = echoResponse;
            if (answer.ask) Qt.callLater(root.focusField);
        }
        function onAuthFailure(text) {
            console.info("greeter: auth=failed");
            root.reset();
            root.say("Could not log in. Check your password and try again.", true);
        }
        function onReadyToLaunch() {
            root.say("", false);
            root.launch();
        }
        function onError(error) {
            console.error("greeter: greetd error=" + error);
            root.reset();
            root.say("The login service failed. Try again.", true);
        }
    }

    Process {
        id: usersProc
        command: ["getent", "passwd"]
        stdout: StdioCollector { id: usersOut; waitForEnd: true }
        onExited: code => {
            if (code === 0) root.users = Logic.users(usersOut.text);
            else console.error("greeter: getent passwd exit=" + code);
            console.info("greeter: users=" + root.users.length);
            root.usersRead = true;
            root.choose();
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector { id: listOut; waitForEnd: true }
        stderr: StdioCollector { id: listErr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) {
                console.error("greeter: sessions exit=" + code + " " + listErr.text.trim());
                root.readSessions({});
                return;
            }
            try {
                root.entries = Logic.readEntries(Logic.listing(listOut.text));
            } catch (e) {
                console.error(String(e.message));
                root.readSessions({});
                return;
            }
            const names = Logic.commandsToCheck(root.entries);
            if (names.length === 0) {
                root.readSessions({});
                return;
            }
            whichProc.command = ["bash", root.helperPath, "which"].concat(names);
            whichProc.running = true;
        }
    }

    Process {
        id: whichProc
        stdout: StdioCollector { id: whichOut; waitForEnd: true }
        onExited: code => {
            if (code !== 0) {
                console.error("greeter: which exit=" + code);
                root.entries = [];
                root.readSessions({});
                return;
            }
            let found = null;
            try {
                found = Logic.foundCommands(whichOut.text);
            } catch (e) {
                console.error(String(e.message));
                root.entries = [];
                found = {};
            }
            root.readSessions(found);
        }
    }

    FileView {
        id: memoryFile
        printErrors: false
        onLoaded: {
            root.memoryText = text();
            const read = Logic.readMemory(root.memoryText);
            if (!read.ok) console.warn("greeter: memory=unreadable path=" + path);
            root.memory = read.memory;
            root.memoryRead = true;
            root.choose();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) console.warn("greeter: memory=unreadable path=" + path + " error=" + error);
            root.memoryRead = true;
            root.choose();
        }
        onSaved: root.launchNow()
        onSaveFailed: error => {
            console.warn("greeter: memory=unwritten path=" + path + " error=" + error);
            root.launchNow();
        }
    }

    Image {
        id: backgroundImage
        anchors.fill: parent
        visible: status === Image.Ready
        source: "file://" + root.backgroundPath
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    Scrim {
        onClicked: root.focusField()
    }

    Column {
        anchors.centerIn: parent
        width: Theme.size.panel.sm
        spacing: Theme.stack.group

        Column {
            width: parent.width
            spacing: Theme.stack.row

            Label {
                role: "display"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatTime(Time.now, "HH:mm")
            }
            Label {
                role: "subheading"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: Theme.color.textMuted
                text: Qt.formatDate(Time.now, "dddd d MMMM")
            }
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row
            visible: root.interactive

            Select {
                width: parent.width
                visible: root.users.length > 0
                enabled: !root.busy
                model: root.users
                textRole: "label"
                currentIndex: root.userIndex
                onActivated: index => {
                    root.userIndex = index;
                    root.sessionId = Logic.preselect(root.sessionList, root.memory, root.userName());
                }
            }

            TextField {
                id: nameField
                width: parent.width
                visible: root.usersRead && root.users.length === 0
                enabled: !root.busy
                leadingIcon: "user"
                placeholderText: "Account name"
                onAccepted: root.focusField()
            }

            TextField {
                id: field
                width: parent.width
                leadingIcon: root.asking && root.echo ? "key-round" : "lock"
                password: !(root.asking && root.echo)
                placeholderText: root.asking && root.message !== "" ? root.message : "Password"
                // Read-only, not disabled, while greetd works, so the field
                // keeps the focus and Escape cancels the login.
                readOnly: root.busy && !root.asking
                error: root.messageError
                onAccepted: root.submit()
                Keys.onEscapePressed: root.cancel()
            }

            Select {
                width: parent.width
                enabled: !root.busy
                model: root.sessionLabels
                textRole: "label"
                currentIndex: {
                    for (let i = 0; i < root.sessionList.length; i++) if (root.sessionList[i].id === root.sessionId) return i;
                    return -1;
                }
                onActivated: index => { root.sessionId = root.sessionList[index].id; }
            }
        }

        Item {
            width: parent.width
            height: Math.max(spinnerRow.implicitHeight, messageLine.implicitHeight)
            visible: root.interactive

            Row {
                id: spinnerRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.stack.inline
                visible: root.busy && !root.asking

                Spinner {
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    role: "hint"
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.message !== "" ? root.message : "Logging in"
                }
            }

            Label {
                id: messageLine
                role: "hint"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: !spinnerRow.visible && root.message !== ""
                color: root.messageError ? Theme.color.danger : Theme.color.textMuted
                text: root.message
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.stack.section
        spacing: Theme.stack.inline
        visible: root.interactive

        IconButton {
            iconName: "moon"
            label: "Suspend"
            onClicked: Quickshell.execDetached(["systemctl", "suspend"])
        }
        IconButton {
            iconName: "rotate-ccw"
            label: "Restart"
            onClicked: Quickshell.execDetached(["systemctl", "reboot"])
        }
        IconButton {
            iconName: "power"
            label: "Shut down"
            onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
        }
    }
}
