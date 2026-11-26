import QtQuick
import QtQuick.Templates as T
import qs.Ui
import qs.Ui as Ui

T.Button {
    id: pill

    required property var look
    property bool emphasized: false
    property bool focusPreview: false
    property bool tabFocusable: true

    implicitWidth: implicitContentWidth + 2 * look.pill.padX
    implicitHeight: look.pill.height
    focusPolicy: tabFocusable ? Qt.StrongFocus : Qt.NoFocus
    hoverEnabled: true
    PointerCursor {}
    Accessible.name: text
    Keys.onReturnPressed: Ui.KeyNavLogic.activate(pill)
    Keys.onEnterPressed: Ui.KeyNavLogic.activate(pill)

    contentItem: Text {
        textFormat: Text.PlainText
        text: pill.text
        color: pill.look.text.foreground
        opacity: pill.hovered || pill.emphasized || pill.visualFocus || pill.focusPreview ? 1 : pill.look.pill.idle
        font.family: pill.look.font.family.sans
        font.pixelSize: pill.look.text.label.size
        font.weight: pill.look.text.label.weight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // The label's glyphs, top and bottom, in this button's coordinates:
    // the card's fade counts a text line as covered only where they meet
    // it. Text.baselineOffset includes the label's vertical centring
    // (Qt 6.12.0 QQuickTextPrivate::updateBaseline), and FontMetrics
    // methods capture no property, so the reading follows the font.
    // https://github.com/qt/qtdeclarative/blob/v6.12.0/src/quick/items/qquicktext.cpp#L406
    readonly property rect labelInk: {
        void labelMetrics.font;
        return labelMetrics.tightBoundingRect(text);
    }
    readonly property real inkTop: contentItem.y + contentItem.baselineOffset + labelInk.y
    readonly property real inkBottom: inkTop + labelInk.height
    FontMetrics {
        id: labelMetrics
        font: pill.contentItem.font
    }

    background: Rectangle {
        radius: pill.look.radius.full
        scale: pill.down ? pill.look.pill.pressScale : 1
        color: pill.down ? pill.look.pill.pressed : (pill.hovered || pill.focusPreview ? pill.look.pill.hover : (pill.emphasized ? pill.look.pill.emphasized : pill.look.pill.rest))
        border.width: pill.look.pill.borderWidth
        border.color: pill.hovered || pill.visualFocus || pill.focusPreview ? pill.look.pill.border : pill.look.pill.borderRest
        Behavior on color { ColorAnim { duration: pill.look.motion.duration.medium2; curve: pill.look.motion.curve.standard } }
        Behavior on scale { Anim { duration: pill.look.motion.duration.short4; curve: pill.look.motion.curve.emphasizedDecel } }
        FocusRing { target: pill }
    }
}
