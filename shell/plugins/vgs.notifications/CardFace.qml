import QtQuick
import qs.Ui
import "NotificationLogic.js" as Logic

Item {
    id: face

    required property var look
    required property real textColumn
    required property string key
    property string app: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property string desktopEntry: ""
    property int urgency: Logic.URGENCY.normal
    property string hintAvatar: ""
    property string hintIcon: ""
    property string hintTone: ""
    property string hintPage: ""
    property string workspace: ""
    property string workspaceIcon: ""
    property var faceImages: []
    property var emoji: null
    property var actions: []
    property bool showActions: false
    property string caption: ""
    property bool captionOnly: false
    property int actionIndex: -1
    property bool keyboardActions: false
    property real orb: 0
    property real edgeSpin: 0
    property real edgeBoost: 1
    property bool edgeVisible: false
    property bool reportHover: true
    // Whether the pointer is on the card: the card's own hover, unless the
    // surface hands the hover of the slot that holds the card.
    property bool hovered: card.hovered
    readonly property alias card: card

    signal actionTriggered(string id)
    signal closeRequested()
    signal cardClicked()
    signal hoverRequested(string key, bool on)

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    property bool hoverReported: false
    readonly property bool interactionHeld: hovered || card.menuOpened
    onInteractionHeldChanged: {
        if (!reportHover || key === "" || interactionHeld === hoverReported) return;
        hoverReported = interactionHeld;
        hoverRequested(key, interactionHeld);
    }
    Component.onDestruction: {
        if (hoverReported && reportHover && key !== "") hoverRequested(key, false);
    }

    NotificationCard {
        id: card
        look: face.look
        textColumn: face.textColumn
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: parent.height
        app: face.app
        appIcon: face.appIcon
        summary: face.summary
        body: face.body
        image: face.image
        desktopEntry: face.desktopEntry
        hintAvatar: face.hintAvatar
        hintIcon: face.hintIcon
        hintTone: face.hintTone
        hintPage: face.hintPage
        workspace: face.workspace
        workspaceIcon: face.workspaceIcon
        faceImages: face.faceImages
        emoji: face.emoji
        actions: face.actions
        showActions: face.showActions
        caption: face.caption
        captionOnly: face.captionOnly
        actionIndex: face.actionIndex
        keyboardActions: face.keyboardActions
        onActionTriggered: id => face.actionTriggered(id)
        onCloseRequested: face.closeRequested()
        onCardClicked: face.cardClicked()
    }

    // The card's glass: its edge light shows while the face asks, turns to
    // the accent on a critical notification, and whirls and brightens as
    // the card asks.
    GlassSurface {
        id: glass
        z: -1
        surface: "notifications"
        follow: card
        radius: card.radius
        edgeShown: face.edgeVisible
        lit: face.urgency === Logic.URGENCY.critical
        edgeSpin: face.edgeSpin
        edgeBoost: face.edgeBoost

        Orb {
            look: face.look
            radius: card.radius
            amount: glass.drawn ? face.orb : 0
        }
    }
}
