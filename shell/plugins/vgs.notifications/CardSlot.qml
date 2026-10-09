import QtQuick
import QtQuick.Layouts

// One toast row of the stack on one screen. While the toast draws glass,
// the card morphs in from a dot and collapses back into one when it leaves;
// without glass it fades in at full size as it drops, and fades out. The
// service owns the row, its lifetime and its end. In a stack at the top the
// row's gap is above the card and the dot drops in from above; at the
// bottom the gap is below it and the dot rises from below.
Item {
    id: slot

    // The stack this row is drawn in, which says whether the service is
    // still there.
    required property var host
    // Null once the service or the stack is gone, while the host destroys
    // this copy; every binding on it checks for that.
    readonly property var service: host ? host.service : null
    readonly property bool rising: host ? host.fromBottom : false
    required property var look
    // The stack's text column, which the card's text starts on.
    required property real textColumn
    required property int index
    required property string key
    required property string app
    required property string appIcon
    required property string summary
    required property string body
    required property string image
    required property string desktopEntry
    required property int urgency
    required property string hintIcon
    required property string hintTone
    required property string leaving

    Layout.preferredWidth: look.card.width
    Layout.alignment: Qt.AlignHCenter
    // The slot grows with the morph, so the rows under it slide rather than
    // jump.
    implicitHeight: look.card.gap * stretch + face.height + drop

    // The container transform: `stretch` morphs the dot into the capsule,
    // `drop`, from minus card.drop to nothing, brings the dot in from the
    // stack's edge: at the top it lowers the dot inside the slot, whose top
    // stays put; at the bottom the slot's top moves with it and its bottom
    // stays put, so the dot rises with the slot's growth alone. `squash`
    // flattens the dot for a beat as it lands, and `hover` lifts it while
    // the pointer is on it.
    property real stretch: 0
    property real drop: 0
    property real squash: 0
    property real hover: face.hovered && leaving === "" ? 1 : 0
    Behavior on hover { Anim { duration: slot.look.motion.duration.short4; curve: slot.look.motion.curve.standard } }
    readonly property real orbness: 1 - stretch
    readonly property bool fadeActive: face.hovered && leaving === ""
    readonly property rect fadeArea: host ? Qt.rect(host.look.stack.pad + x + face.x,
        y + face.y - host.scrollView.contentY, face.width, face.height) : Qt.rect(0, 0, 0, 0)

    // The hover actions, read when the pointer arrives, since a live
    // notification's actions are not observable.
    property var actions: []

    Component.onCompleted: {
        if (leaving !== "") play();
        else (face.glassOn ? enterAnim : plainEnter).start();
    }
    onLeavingChanged: play()

    function play() {
        enterAnim.stop();
        plainEnter.stop();
        if (leaving !== "") (face.glassOn ? exitAnim : plainExit).start();
    }

    SequentialAnimation {
        id: enterAnim
        PropertyAction { target: face.card; property: "contentOpacity"; value: 0 }
        PropertyAction { target: face.card; property: "opacity"; value: 0 }
        PropertyAction { target: slot; property: "drop"; value: -slot.look.card.drop }
        ParallelAnimation {
            Anim { target: face.card; property: "opacity"; to: 1; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.standard }
            Anim { target: slot; property: "drop"; to: 0; duration: slot.look.motion.duration.medium1; curve: slot.look.motion.curve.emphasizedDecel }
        }
        Anim { target: slot; property: "squash"; to: 1; duration: slot.look.motion.duration.short2; curve: slot.look.motion.curve.standardDecel }
        ParallelAnimation {
            Anim { target: slot; property: "squash"; to: 0; duration: slot.look.motion.duration.medium2; curve: slot.look.motion.curve.emphasizedDecel }
            Anim { target: slot; property: "stretch"; from: 0; to: 1; duration: slot.look.motion.duration.medium4; curve: slot.look.motion.curve.standard }
            SequentialAnimation {
                PauseAnimation { duration: slot.look.motion.duration.short4 }
                Anim { target: face.card; property: "contentOpacity"; to: 1; duration: slot.look.motion.duration.short4; curve: slot.look.motion.curve.standard }
            }
        }
    }

    // Without glass the toast is a card from the start: it fades in as it
    // drops, its text with it.
    SequentialAnimation {
        id: plainEnter
        PropertyAction { target: slot; property: "stretch"; value: 1 }
        PropertyAction { target: face.card; property: "opacity"; value: 0 }
        PropertyAction { target: slot; property: "drop"; value: -slot.look.card.drop }
        ParallelAnimation {
            Anim { target: face.card; property: "opacity"; to: 1; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.standard }
            Anim { target: slot; property: "drop"; to: 0; duration: slot.look.motion.duration.medium1; curve: slot.look.motion.curve.emphasizedDecel }
        }
    }

    // Without glass a toast leaving fades out, and only then its row
    // closes, so the rows under it slide up with nothing shown shrinking.
    SequentialAnimation {
        id: plainExit
        Anim { target: face.card; property: "opacity"; to: 0; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.standard }
        Anim { target: slot; property: "stretch"; to: 0; duration: slot.look.motion.duration.medium3; curve: slot.look.motion.curve.emphasizedAccel }
    }

    // A toast leaving collapses to a dot and shrinks away. The text is gone
    // early in the collapse, so it never looks clipped.
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            Anim { target: face.card; property: "contentOpacity"; to: 0; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.emphasizedAccel }
            Anim { target: slot; property: "stretch"; to: 0; duration: slot.look.motion.duration.medium3; curve: slot.look.motion.curve.emphasizedAccel }
        }
        ParallelAnimation {
            Anim { target: face.card; property: "opacity"; to: 0; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.standard }
            Anim { target: face.card; property: "scale"; to: slot.look.card.exitScale; duration: slot.look.motion.duration.short3; curve: slot.look.motion.curve.emphasizedAccel }
        }
    }

    CardFace {
        id: face
        look: slot.look
        key: slot.key
        textColumn: slot.textColumn
        anchors.horizontalCenter: parent.horizontalCenter
        y: (slot.rising ? 0 : slot.look.card.gap * slot.stretch + slot.drop) - slot.look.card.lift * slot.hover
        width: slot.look.card.dot * (1 + slot.look.card.squashWide * slot.squash) + (face.card.fullWidth - slot.look.card.dot) * slot.stretch
        height: slot.look.card.dot * (1 - slot.look.card.squashFlat * slot.squash) + (face.card.fullHeight - slot.look.card.dot) * slot.stretch
        app: slot.app
        appIcon: slot.appIcon
        summary: slot.summary
        body: slot.body
        image: slot.image
        desktopEntry: slot.desktopEntry
        urgency: slot.urgency
        hintIcon: slot.hintIcon
        hintTone: slot.hintTone
        glassChoice: slot.service !== null && slot.service.glassChoice
        workspace: slot.service !== null ? slot.service.workspaceOf(face.card.enrichment) : ""
        workspaceIcon: slot.service !== null && face.card.enrichment !== null ? slot.service.workspaceIcon(face.card.enrichment.rule, face.card.workspace) : ""
        faceImages: slot.service !== null && face.card.enrichment !== null ? slot.service.faceImages(face.card.enrichment, slot.image, face.card.workspace) : []
        emoji: slot.service !== null ? slot.service.emojiFor(face.card.enrichment, face.card.workspace) : null
        actions: slot.actions
        showActions: face.card.hovered && slot.leaving === ""
        orb: slot.orbness * slot.orbness
        edgeVisible: slot.hover > 0 || (slot.service !== null && !slot.service.panelOpen)
        edgeSpin: slot.look.edge.spin * slot.orbness
        edgeBoost: 1 + slot.look.edge.orbBoost * slot.orbness + slot.look.edge.hoverBoost * slot.hover
        onHoverRequested: (key, on) => {
            if (slot.service === null) return;
            if (on) slot.actions = slot.service.actionsFor(key);
            slot.service.hover(key, on);
        }
        onActionTriggered: id => slot.service.choose(slot.key, id)
        onCloseRequested: slot.service.choose(slot.key, "dismiss")
        onCardClicked: slot.service.choose(slot.key, "open")
    }
}
