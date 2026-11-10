import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "UsageView.js" as View

// Each signed-in and visible account in a card of its own: the provider,
// the account's email, its menu, whose Refresh checks every account again
// as Check now does and whose Hide adds it to Hidden accounts,
// one row per limit with its time to reset and one
// per credit the provider reports. Full view gives the credits a larger
// group gap and adds a meter under each limit
// and each credit with a used share, and the provider detail fields the
// helper received. The calendar button left of the Settings gear shows the
// reset calendar above the cards until the panel closes. The footer shows
// when the shared check last completed.
// The pane is at most half its output's height. Opening the panel reads
// nothing: Check now asks the service for a new check, and the panel draws
// status alone.
Item {
    id: root
    property var shell: null
    property Item initialFocus: refreshButton
    readonly property var usage: shell === null || shell.status.values.usage === undefined ? null : shell.status.values.usage
    readonly property var rows: View.panel(usage, Time.now.getTime(), shell === null ? null : shell.settings)
    readonly property string checked: View.checkedText(usage === null ? null : usage.readAt, Time.now.getTime())
    readonly property bool fullView: shell !== null && shell.settings.view !== "compact"
    readonly property bool calendarOpen: calendarButton.checked
    // Why the last Hide failed, or "".
    property string problem: ""
    // Each reset time in the locale's short time format, which Qt reads from
    // LC_TIME: doc.qt.io/qt-6/qml-qtqml-date.html#toLocaleTimeString-method.
    readonly property var calendar: calendarOpen
        ? View.calendar(usage, Time.now.getTime(), shell === null ? null : shell.settings, ms => new Date(ms).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        : []
    // The output the panel's popup window occupies, a ShellScreen whose
    // height is logical, or null before the panel has a window.
    readonly property var host: QsWindow.window
    readonly property var output: host === null || host === undefined || host.screen === null || host.screen === undefined ? null : host.screen
    // The tallest the pane draws: half its output, or panel.maxHeight with
    // no output yet.
    readonly property real heightCap: output === null ? Theme.size.panel.maxHeight : output.height * Theme.size.window.heightShare

    function refresh() {
        const reply = shell.ipc.call("refresh", "");
        if (reply !== "ok") console.warn("ai-usage: panel refresh " + reply);
        return reply;
    }
    // Hide adds account ID to the Hidden accounts setting Settings edits,
    // so its card and calendar entry leave and the panel stays open. The
    // keys move to the More actions of the card that takes its place, else
    // of the card before it, else to Check now, the panel's first focus,
    // with the ring when OPENER, the input that opened the card's menu, is
    // "key".
    function hide(id, opener) {
        const ids = rows.map(row => row.id);
        const at = ids.indexOf(id);
        const next = at + 1 < ids.length ? ids[at + 1] : at > 0 ? ids[at - 1] : "";
        const reply = shell.configure.set("hidden", View.hiding(shell.settings, id));
        problem = reply === "ok" ? "" : "The account could not be hidden.";
        if (reply !== "ok") {
            console.warn("ai-usage: hide " + reply);
            return reply;
        }
        const card = cardOf(next);
        (card === null ? refreshButton : card.menuButton).forceActiveFocus(opener === "key" ? Qt.TabFocusReason : Qt.MouseFocusReason);
        return reply;
    }
    // The card of account ID, or null.
    function cardOf(id) {
        for (let i = 0; i < cards.count; i++) {
            const card = cards.itemAt(i);
            if (card !== null && card.modelData === id) return card;
        }
        return null;
    }
    function open(payloadJson) {}
    function close() {}

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: root.heightCap
        title: "AI Usage"
        // Pane leaves the title slot's end clear of its Settings gear, and
        // the slot comes before the gear in Tab order. The slot is as tall
        // as its children's box, so a child centred on it is a binding
        // loop; the button and the gear are one size and set the row's
        // height.
        titleContent: [
            IconButton {
                id: calendarButton
                anchors.right: parent.right
                size: "sm"
                iconName: "calendar-clock"
                label: "Reset calendar"
                checkable: true
            }
        ]

        // Built only while open, so a closed calendar adds no card to the body.
        Loader {
            width: layout.contentWidth
            visible: root.calendarOpen
            active: visible
            sourceComponent: Card {
                Label { role: "label"; text: "Reset calendar" }
                Label {
                    width: parent.width
                    visible: root.calendar.length === 0
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: "No plan limit resets in the next seven days."
                }
                // Each day is one group: its heading over its accounts.
                GroupList {
                    Repeater {
                        model: root.calendar
                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: Theme.row.lineGap
                            Label { role: "bodyStrong"; text: modelData.heading }
                            Repeater {
                                model: modelData.accounts
                                Item {
                                    required property var modelData
                                    width: parent.width
                                    implicitHeight: Math.max(resetAccount.implicitHeight, resetShare.implicitHeight)
                                    // The provider mark leads the account's line on
                                    // its x-height centre (design-system.md § Tokens).
                                    Image {
                                        id: resetLogo
                                        y: resetAccount.y + resetAccount.topForLeadingIcon(height, resetAccount.y)
                                        width: Theme.icon.size.sm
                                        height: Theme.icon.size.sm
                                        // Qt loads a data URL at sourceSize alone, unscaled
                                        // for the display: see providerLogo.
                                        sourceSize.width: resetLogo.width * Screen.devicePixelRatio
                                        sourceSize.height: resetLogo.height * Screen.devicePixelRatio
                                        source: View.logo(modelData.provider, Theme.color.text, resetLogo.sourceSize.width)
                                    }
                                    Label {
                                        id: resetAccount
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: resetLogo.width + Theme.stack.inline
                                        width: parent.width - x - resetShare.width - Theme.stack.inline
                                        elide: Text.ElideRight
                                        role: "hint"
                                        text: modelData.label
                                    }
                                    Row {
                                        id: resetShare
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.stack.inline
                                        Label { anchors.verticalCenter: parent.verticalCenter; role: "hint"; text: modelData.time }
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            role: "body"
                                            text: modelData.text
                                            color: Theme.badge.tone[modelData.tone].foreground
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Label {
            width: layout.contentWidth
            visible: root.problem !== ""
            role: "hint"
            wrapMode: Text.Wrap
            text: root.problem
            color: Theme.badge.tone.warning.foreground
        }

        Label {
            width: layout.contentWidth
            visible: root.rows.length === 0
            role: "body"
            wrapMode: Text.Wrap
            text: root.usage === null ? "Checking your sign-ins." : "No visible account is signed in. Check your AI Usage settings."
        }

        // Keyed by account: Time.now's minute tick, a new check and any
        // other status write each give fresh rows, and a model of the rows
        // themselves built every card again at each, taking the keys and
        // an open menu with it (tst_ai_usage_widget.qml). The keys are
        // strings, as DeviceList's are: Quickshell 0.3.1's ScriptModel can
        // leave a moved object's payload stale, so root.rows holds the
        // current row. https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel
        Repeater {
            id: cards
            model: ScriptModel { values: root.rows.map(row => row.id) }
            Card {
                id: card
                // The account's id.
                required property var modelData
                readonly property var current: root.rows.find(row => row.id === card.modelData)
                // The account's row. A Hide drops it from root.rows before
                // the model drops the card, which keeps the row it drew
                // last until then: Binding.RestoreNone leaves the last value
                // while `when` is false
                // (https://doc.qt.io/qt-6/qml-qtqml-binding.html#restoreMode-prop).
                property var entry: current
                Binding on entry {
                    value: card.current
                    when: card.current !== undefined
                    restoreMode: Binding.RestoreNone
                }
                readonly property Item menuButton: moreButton
                // The input that opened the card's menu, KeyNavLogic.opener's.
                property string opener: "pointer"
                width: layout.contentWidth

                Item {
                    width: parent.width
                    implicitHeight: Math.max(identity.implicitHeight, providerLogo.height)
                    Row {
                        id: identity
                        spacing: Theme.stack.inline
                        Label { anchors.verticalCenter: parent.verticalCenter; role: "label"; text: entry.title }
                        Badge { anchors.verticalCenter: parent.verticalCenter; visible: entry.api; text: "[API]"; tone: "info" }
                    }
                    // The button's box overruns the line into the card's
                    // padding, so the card keeps the height it has without
                    // it; a ghost button draws no fill there.
                    IconButton {
                        id: moreButton
                        anchors.right: providerLogo.left
                        anchors.rightMargin: Theme.stack.inline
                        anchors.verticalCenter: parent.verticalCenter
                        size: "sm"
                        iconName: "ellipsis"
                        label: "More actions"
                        onClicked: {
                            card.opener = KeyNavLogic.opener(moreButton);
                            cardMenu.toggle(card.opener);
                        }
                        Menu {
                            id: cardMenu
                            MenuItem {
                                text: "Refresh"
                                iconName: "refresh-cw"
                                onTriggered: root.refresh()
                            }
                            // The menu closes on the trigger, and the hidden
                            // card takes the menu with it, so Hide waits for
                            // that close.
                            MenuItem {
                                text: "Hide"
                                iconName: "eye-off"
                                onTriggered: {
                                    const id = card.modelData;
                                    const opener = card.opener;
                                    Qt.callLater(() => root.hide(id, opener));
                                }
                            }
                        }
                    }
                    // SVG data retains the published mark. Qt renders an
                    // image at its sourceSize times the display scale only
                    // for a URL whose path ends in svg, svgz or pdf
                    // (QQuickPixmap::isScalableImageFormat), which a data
                    // URL's never does, so sourceSize names device pixels,
                    // and the mark states that size (View.logo): read at
                    // scale 2 in the nested sandbox under Qt 6.12.0, a mark
                    // loaded at its logical size draws scaled up.
                    Image {
                        id: providerLogo
                        objectName: "providerLogo"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.icon.size.md
                        height: Theme.icon.size.md
                        sourceSize.width: providerLogo.width * Screen.devicePixelRatio
                        sourceSize.height: providerLogo.height * Screen.devicePixelRatio
                        source: View.logo(entry.provider, Theme.color.text, providerLogo.sourceSize.width)
                        visible: source.toString() !== ""
                    }
                }
                Label {
                    visible: text !== ""
                    role: "hint"
                    text: entry.account
                    // Qt Text reserves padding in addition to contentHeight:
                    // doc.qt.io/qt-6/qml-qtquick-text.html#padding-prop.
                    bottomPadding: Theme.stack.inline
                }
                Label { visible: root.fullView && text !== ""; role: "hint"; text: entry.detail }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: entry.note
                    color: entry.noteTone === "warning" ? Theme.badge.tone.warning.foreground : Theme.text.hint.color
                }

                Column {
                    id: usageRows
                    // Full view separates credits from limits; Compact
                    // keeps the same gap between every row.
                    readonly property real groupGap: root.fullView ? Theme.stack.group : Theme.row.lineGap
                    visible: entry.windows.length > 0
                    width: parent.width
                    spacing: root.fullView ? Theme.stack.inline : Theme.row.lineGap
                    Repeater {
                        model: entry.windows
                        Column {
                            id: usageLimit
                            required property var modelData
                            // A credit with no used share, such as a balance, has no tone.
                            readonly property color usageColor: modelData.tone === "" ? Theme.text.body.color
                                : modelData.started ? Theme.badge.tone[modelData.tone].foreground : Theme.text.hint.color
                            width: parent.width
                            spacing: Theme.row.lineGap
                            // A Column's topPadding adds to its height above
                            // its first child, so the row moves down and the
                            // ones after it with it:
                            // https://doc.qt.io/qt-6/qml-qtquick-column.html#topPadding-prop.
                            topPadding: modelData.opensGroup ? usageRows.groupGap - usageRows.spacing : 0

                            Item {
                                width: parent.width
                                implicitHeight: Math.max(limit.implicitHeight, share.implicitHeight)
                                // A long title wraps; the time and the figure stay
                                // centred on its first line, one lineBox tall.
                                Label {
                                    id: limit
                                    width: parent.width - share.width - Theme.stack.inline
                                    wrapMode: Text.Wrap
                                    role: "body"
                                    text: modelData.label
                                }
                                Row {
                                    id: share
                                    anchors.right: parent.right
                                    y: (limit.lineBox - height) / 2
                                    spacing: Theme.stack.inline
                                    Label {
                                        visible: text !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "hint"
                                        text: modelData.reset
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "body"
                                        text: modelData.text
                                        color: usageLimit.usageColor
                                    }
                                }
                            }
                            // Built only for a row with a used share, so a
                            // balance has no bar and no tone.
                            Loader {
                                width: parent.width
                                active: root.fullView && usageLimit.modelData.bar
                                visible: active
                                sourceComponent: ProgressBar { value: Math.min(usageLimit.modelData.percent, 100) / 100; tone: usageLimit.modelData.tone }
                            }
                        }
                    }
                }

                Section {
                    visible: root.fullView && entry.details.length > 0
                    title: "Details"
                    rowSpacing: Theme.row.lineGap
                    Repeater {
                        model: entry.details
                        Item {
                            required property var modelData
                            width: parent.width
                            implicitHeight: Math.max(detailName.implicitHeight, detailValue.implicitHeight)
                            Label { id: detailName; role: "hint"; text: modelData.label }
                            Label { id: detailValue; anchors.right: parent.right; role: "body"; text: modelData.value }
                        }
                    }
                }
            }
        }

        footer: [
            Row {
                spacing: Theme.stack.inline
                Button {
                    id: refreshButton
                    variant: "secondary"
                    text: "Check now"
                    iconName: "refresh-cw"
                    onClicked: root.refresh()
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    role: "hint"
                    text: root.checked
                }
            }
        ]
    }
}
