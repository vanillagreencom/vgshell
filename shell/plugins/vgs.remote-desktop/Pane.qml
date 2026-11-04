import QtQuick
import qs.Commons
import qs.Ui
import "Remote.js" as Remote

// System Settings › Remote desktop: This computer, with Hosting and who is
// viewing it, and Computers, one row per profile with Connect, which asks
// the service to open gliff, and Set up sign-in, the plugin's terminal
// that makes key sign-in to that computer work. Profiles are edited on the
// plugin's Settings tab, which Change computers opens.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: content

    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var session: values.session === undefined ? null : values.session
    readonly property bool hosting: shell === null || shell.settings.hosting !== false
    readonly property var profiles: shell === null ? [] : shell.settings.profiles.filter(profile => profile.host !== "")

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
    }
    function close() {}

    function openSettings(key) {
        const reply = shell.surfaces.openPage("vgs.remote-desktop", "Settings/" + key);
        if (reply !== "ok") console.warn("remote-desktop pane: settings " + reply);
    }
    // The service refuses in plain words through a notification.
    function connect(profile) {
        shell.ipc.call("connect", profile.name);
    }
    function signIn(profile) {
        const reply = shell.tui.run("sign-in", [profile.host]);
        if (reply !== "ok") console.warn("remote-desktop pane: sign-in " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Section {
            id: here
            width: content.width
            title: "This computer"

            Field {
                width: here.width
                inline: true
                label: "Hosting"
                error: root.values.hostingProblem ?? ""
                onHintPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)

                Row {
                    spacing: Theme.stack.inline
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "value"
                        text: root.hosting ? "On" : "Off"
                    }
                    RowAction {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Change"
                        onClicked: root.openSettings("hosting")
                    }
                }
            }

            Field {
                width: here.width
                inline: true
                label: "Viewing now"
                lines: root.session !== null && root.session.active ? Remote.tooltip(root.session).details : []

                Label {
                    role: "value"
                    textFormat: Text.PlainText
                    text: root.session === null ? "Checking" : root.session.active ? Remote.tooltip(root.session).title : "Nobody"
                }
            }
        }

        Section {
            id: computers
            width: content.width
            title: "Computers"

            Repeater {
                model: root.profiles

                ListItem {
                    required property var modelData
                    width: computers.width
                    leftPadding: 0
                    rightPadding: 0
                    clickable: false
                    iconName: "monitor"
                    text: modelData.host
                    secondary: Remote.summary(modelData, root.shell.manifest.schema.profiles.items)
                    trailing: [
                        RowAction {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Set up sign-in"
                            Accessible.name: "Set up sign-in to " + modelData.host
                            onClicked: root.signIn(modelData)
                        },
                        RowAction {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Connect"
                            Accessible.name: "Connect to " + modelData.host
                            onClicked: root.connect(modelData)
                        }
                    ]
                }
            }

            Label {
                visible: root.profiles.length === 0
                width: computers.width
                role: "hint"
                text: "Add the computers you use to connect to them in one click."
                wrapMode: Text.Wrap
            }

            RowAction {
                text: root.profiles.length === 0 ? "Add a computer" : "Change computers"
                onClicked: root.openSettings("profiles")
            }
        }
    }
}
