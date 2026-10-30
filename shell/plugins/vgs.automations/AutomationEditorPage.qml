import QtQuick
import qs.Commons
import qs.Ui
import "AutomationsLogic.js" as Engine
import "AutomationsViewLogic.js" as View

FocusScope {
    id: page

    required property Item panel
    required property var draft
    required property var validation
    required property string summary
    required property var previewRows
    required property var testRun
    required property string testTranscript
    property var pending: null
    property int timeoutUnitIndex: View.timeoutAmount(draft.timeoutSeconds).unit === "hours" ? 1 : 0

    signal backRequested()
    signal saveRequested()
    signal testRequested()
    signal cancelRequested()
    signal copyRequested()
    signal removeRequested()
    signal openTranscriptRequested(string path)
    signal change(string key, var value)

    focus: true
    onDraftChanged: timeoutUnitIndex = View.timeoutAmount(draft.timeoutSeconds).unit === "hours" ? 1 : 0

    function focusName() { nameField.forceActiveFocus(); }

    Keys.onEscapePressed: backRequested()

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        bodySpacing: Theme.stack.group

        titleContent: [
            PageHeader {
                width: layout.contentWidth
                text: page.draft.saved ? "Edit automation" : "New automation"
                leading: [
                    IconButton { iconName: "chevron-left"; label: "Back to automations"; size: "sm"; anchors.verticalCenter: parent.verticalCenter; onClicked: page.backRequested() }
                ]
                trailing: [
                    Row {
                        spacing: Theme.space.xs
                        anchors.verticalCenter: parent.verticalCenter
                        Kbd { text: "Ctrl" }
                        Kbd { text: "S" }
                        Button { text: "Save"; iconName: "save"; size: "sm"; onClicked: page.saveRequested() }
                    }
                ]
            }
        ]

        Column {
            width: parent.width
            spacing: Theme.stack.group

                Section {
                    title: "Basics"
                    description: "Name the job and the command it runs."
                    headerInset: 0
                    width: parent.width

                    Field {
                        label: "Name"
                        width: parent.width
                        error: page.validation.errors.name || ""
                        TextField {
                            id: nameField
                            width: parent.width
                            text: page.draft.name
                            onTextEdited: page.change("name", text)
                        }
                    }

                    Field {
                        label: "Command"
                        hint: page.draft.saved ? "Test the saved automation and view its output." : "Save the automation before a test run."
                        error: page.validation.errors.command || ""
                        width: parent.width
                        TextArea {
                            id: commandEditor
                            width: parent.width
                            text: page.draft.command
                            placeholderText: "printf '%s\\n' hello"
                            error: page.validation.errors.command !== undefined
                            onTextChanged: if (text !== page.draft.command) page.change("command", text)
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.space.xs
                        Button {
                            text: page.draft.saved ? "Test run" : "Save before test run"
                            iconName: "play"
                            variant: "secondary"
                            disabledReason: !page.draft.saved ? "Save this automation before a test run." : page.pending !== null ? "Cancel the waiting run before starting another." : ""
                            onClicked: page.testRequested()
                        }
                        Button { text: "Copy command"; iconName: "copy"; variant: "tertiary"; onClicked: page.copyRequested() }
                        Button { text: "Remove"; iconName: "trash"; variant: "danger"; visible: page.draft.saved; onClicked: page.removeRequested() }
                    }
                    Label {
                        width: parent.width
                        role: "body"
                        text: page.pending === null ? "" : "Waiting for network · Due " + View.formatWhen(page.pending.dueAt)
                        visible: page.pending !== null
                        wrapMode: Text.Wrap
                    }
                    RowAction {
                        text: "Cancel waiting run"
                        visible: page.pending !== null
                        onClicked: page.cancelRequested()
                    }
                }

                TranscriptPanel {
                    width: parent.width
                    run: page.testRun
                    transcript: page.testTranscript
                    onOpenRequested: path => page.openTranscriptRequested(path)
                }

                RecurrenceSection {
                    width: parent.width
                    draft: page.draft
                    validation: page.validation
                    onChange: (key, value) => page.change(key, value)
                }

                PreviewPanel {
                    width: parent.width
                    summary: page.summary
                    occurrences: page.previewRows
                }

                Section {
                    title: "Run settings"
                    description: "Set how this automation runs."
                    headerInset: 0
                    width: parent.width

                    Field {
                        width: parent.width
                        label: "Network"
                        inline: true
                        hint: page.pending === null ? "" : [View.networkExplanation(page.pending), "Saving changes cancels the waiting run."].filter(text => text !== "").join(" ")
                        Switch {
                            size: "sm"
                            text: "Needs internet"
                            checked: page.draft.requiresNetwork
                            onToggled: {
                                checked = Qt.binding(() => page.draft.requiresNetwork);
                                page.change("requiresNetwork", !page.draft.requiresNetwork);
                            }
                        }
                    }
                    Field { width: parent.width; label: "Notify"; inline: true; Switch { size: "sm"; text: "Notify on every run"; checked: page.draft.notifyEveryRun; onToggled: { checked = Qt.binding(() => page.draft.notifyEveryRun); page.change("notifyEveryRun", !page.draft.notifyEveryRun); } } }
                    Field { width: parent.width; label: "Catch up"; inline: true; Switch { size: "sm"; text: "Catch up missed runs"; checked: page.draft.catchUp; onToggled: { checked = Qt.binding(() => page.draft.catchUp); page.change("catchUp", !page.draft.catchUp); } } }
                    Field { width: parent.width; label: "Paused"; inline: true; Switch { size: "sm"; text: "Pause this automation"; checked: !page.draft.enabled; onToggled: { checked = Qt.binding(() => !page.draft.enabled); page.change("enabled", page.draft.enabled ? false : true); } } }
                    Field {
                        width: parent.width
                        label: "Timeout"
                        info: "Choose from 1 second to 24 hours. The time limit stops a command that does not finish, so it cannot keep using your computer without a bound. A full day allows long tasks while keeping that bound."
                        inline: true
                        error: page.validation.errors.timeout || ""
                        Row {
                            width: parent.width
                            spacing: Theme.space.xs
                            TextField {
                                width: Theme.size.panel.sm
                                text: String(View.timeoutAmount(page.draft.timeoutSeconds).amount)
                                validator: IntValidator { bottom: 1; top: 1440 }
                                onTextEdited: page.change("timeoutSeconds", View.timeoutSeconds(Number(text), unit.currentText))
                            }
                            Select {
                                id: unit
                                width: parent.width - x
                                model: ["minutes", "hours"]
                                currentIndex: page.timeoutUnitIndex
                                onActivated: index => {
                                    currentIndex = Qt.binding(() => page.timeoutUnitIndex);
                                    page.change("timeoutSeconds", View.timeoutSeconds(Number(parent.children[0].text), model[index]));
                                }
                            }
                        }
                    }
                    Field {
                        width: parent.width
                        label: "Working directory"
                        error: page.validation.errors.workingDirectory || ""
                        PathField {
                            width: parent.width
                            placeholderText: "Working directory, blank for home"
                            path: page.draft.workingDirectory
                            error: page.validation.errors.workingDirectory !== undefined
                            onEdited: (path, valid) => { page.change("workingDirectory", path); page.change("workingDirectoryMissing", !valid && path !== "" && path.charAt(0) === "/"); }
                            onPicked: path => { page.change("workingDirectory", path); page.change("workingDirectoryMissing", false); }
                        }
                    }
                }

        }
    }
}
