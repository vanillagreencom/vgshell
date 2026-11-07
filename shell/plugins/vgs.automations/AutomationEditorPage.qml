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
    // Whether the draft holds a change the store does not
    // (AutomationsViewLogic.draftChanged); the shared save bar shows while
    // it does.
    property bool dirty: false
    property int timeoutUnitIndex: View.timeoutAmount(draft.timeoutSeconds).unit === "hours" ? 1 : 0

    signal backRequested()
    signal saveRequested()
    signal discardRequested()
    signal testRequested()
    signal cancelRequested()
    signal copyRequested()
    signal removeRequested()
    signal openTranscriptRequested(string path)
    signal change(string key, var value)

    focus: true
    onDraftChanged: timeoutUnitIndex = View.timeoutAmount(draft.timeoutSeconds).unit === "hours" ? 1 : 0

    function focusName() { (page.draft.sync !== undefined ? syncName : nameField).forceActiveFocus(); }
    // One field of a sync job's form: the window writes the command from it.
    function changeSync(key, value) {
        const sync = View.clone(page.draft.sync);
        sync[key] = value;
        page.change("sync", sync);
    }
    // The window's save was accepted: the bar reads Saved for a moment.
    function confirmSaved() { saveBar.confirm(); }

    Keys.onEscapePressed: backRequested()

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        bodySpacing: Theme.stack.group

        titleContent: [
            PageHeader {
                width: layout.contentWidth
                text: page.draft.saved ? "Edit automation" : page.draft.sync !== undefined ? "New sync job" : "New automation"
                leading: [
                    IconButton { iconName: "chevron-left"; label: "Back to automations"; size: "sm"; anchors.verticalCenter: parent.verticalCenter; onClicked: page.backRequested() }
                ]
            }
        ]

        // The one save action of the page, in the shared sticky footer;
        // Ctrl+S reaches the same save through the window's keys.
        footer: SaveBar {
            id: saveBar
            width: parent === null ? 0 : parent.width
            dirty: page.dirty
            onShownChanged: if (!shown && activeFocus) page.focusName()
            onSave: page.saveRequested()
            onDiscard: page.discardRequested()
        }

        Column {
            width: parent.width
            spacing: Theme.stack.group

                // A sync job: the folders and the engine, and the command
                // they make, which the job runs.
                Section {
                    title: "Sync job"
                    description: "Creates an Automations job. Its schedule, history and failure notices stay in Automations."
                    headerInset: 0
                    width: parent.width
                    visible: page.draft.sync !== undefined

                    Field {
                        label: "Name"
                        width: parent.width
                        error: page.validation.errors.name || ""
                        TextField {
                            id: syncName
                            width: parent.width
                            text: page.draft.name
                            onTextEdited: page.change("name", text)
                        }
                    }
                    Field {
                        label: "From"
                        width: parent.width
                        error: page.validation.errors.from || ""
                        PathField {
                            width: parent.width
                            placeholderText: "Folder to copy from"
                            path: page.draft.sync === undefined ? "" : page.draft.sync.from
                            error: page.validation.errors.from !== undefined
                            onEdited: (path, valid) => page.changeSync("from", path)
                            onPicked: path => page.changeSync("from", path)
                        }
                    }
                    Field {
                        label: "To"
                        width: parent.width
                        error: page.validation.errors.to || ""
                        PathField {
                            width: parent.width
                            placeholderText: "Folder to copy to"
                            path: page.draft.sync === undefined ? "" : page.draft.sync.to
                            error: page.validation.errors.to !== undefined
                            onEdited: (path, valid) => page.changeSync("to", path)
                            onPicked: path => page.changeSync("to", path)
                        }
                    }
                    Field {
                        label: "Engine"
                        width: parent.width
                        error: page.validation.errors.engine || ""
                        // One engine at a time; an engine this computer
                        // lacks stays offered with why it cannot run.
                        Row {
                            spacing: Theme.stack.inline
                            Repeater {
                                model: View.SYNC_ENGINES
                                ToggleButton {
                                    required property string modelData
                                    text: modelData === "unison" ? "Unison" : "rsync"
                                    checked: page.draft.sync !== undefined && page.draft.sync.engine === modelData
                                    disabledReason: page.draft.sync === undefined || page.draft.sync.available.indexOf(modelData) !== -1 ? ""
                                        : modelData === "unison" ? "Install Unison to use two-way sync." : "Install rsync to copy folders."
                                    onClicked: {
                                        checked = Qt.binding(() => page.draft.sync !== undefined && page.draft.sync.engine === modelData);
                                        page.changeSync("engine", modelData);
                                    }
                                }
                            }
                        }
                    }
                    Field {
                        label: "Command"
                        width: parent.width
                        visible: page.draft.command !== ""
                        hint: "The job runs this command. It deletes nothing in the To folder."
                        CodeLine { width: parent.width; text: page.draft.command; copyLabel: "Copy command" }
                    }
                }

                Section {
                    title: "Basics"
                    description: "Name the job and the command it runs."
                    headerInset: 0
                    width: parent.width
                    visible: page.draft.sync === undefined

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
                        hint: page.pending === null ? "On, a run waits for internet access before it starts; off, it starts at once, even offline" : [View.networkExplanation(page.pending), "Saving changes cancels the waiting run."].filter(text => text !== "").join(" ")
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
