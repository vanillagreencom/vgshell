import QtQuick
import qs.Commons
import qs.Ui

// Text with one cited substring as a link. The text property is plain
// text; every occurrence of `link` is drawn as a link and activates the
// component. `lineCount` is the wrapped label's line count, for owners that
// measure whether the message stayed on one line. Use it where a consumer
// surface cites a file that the core can open through `vgshell edit`.
Item {
    id: root

    property string text: ""
    property string link: ""
    property string role: "body"
    property alias color: label.color
    property alias wrapMode: label.wrapMode
    property alias horizontalAlignment: label.horizontalAlignment
    readonly property alias lineCount: label.lineCount
    readonly property bool linked: link !== "" && text.indexOf(link) !== -1
    readonly property bool hoveredLink: linked && pointer.containsMouse && label.linkAt(pointer.mouseX, pointer.mouseY) !== ""
    signal activated()
    signal clicked()

    function htmlEscaped(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function markup(plain, cited) {
        const escaped = htmlEscaped(plain);
        const needle = htmlEscaped(cited);
        if (needle === "") return escaped;
        const parts = escaped.split(needle);
        const anchor = "<a href=\"file\"><u>" + needle + "</u></a>";
        return parts.join(anchor);
    }

    onClicked: activated()

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    height: implicitHeight
    activeFocusOnTab: linked

    Keys.onReturnPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onEnterPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onSpacePressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }

    Label {
        id: label
        role: root.role
        width: root.width
        text: root.markup(root.text, root.link)
        textFormat: Text.StyledText
        linkColor: Theme.color.accent
    }

    FocusRing {
        target: root
        outside: true
    }

    // keyboard-path: Return, Enter and Space activate the focused link
    MouseArea {
        id: pointer
        anchors.fill: label
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => { mouse.accepted = label.linkAt(mouse.x, mouse.y) !== ""; }
        onClicked: root.clicked()
        PointerCursor {
            enabled: root.hoveredLink
        }
    }
}
