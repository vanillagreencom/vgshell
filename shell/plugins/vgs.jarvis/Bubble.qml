import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance
import "Field.js" as Field
import "Session.js" as Session
import "WidgetView.js" as View
import "AccountProviders.js" as Providers

// Jarvis's overlay at the bottom centre of the focused screen: the particle
// orb in the look of the Session's phase, its icon row at the orb's top
// right, the state line or the fault under it, the held request in place
// of that line, and Jarvis's words above the orb while its voice is muted.
// It draws in the plugin's own look (Appearance.js) on no card: one fading
// field, dark or white (qs.Ui RadialBackdrop, the look's `field`), each line
// of text over the look's shadow. A passive layer takes clicks only on
// `inputItems` (D026).
//
// While the overlay is active (listening, thinking, acting, speaking, a
// held request or a fault) the orb takes the pointer on the look's hit
// square over its centre, and each line of text and answer while it
// shows. The icon row shows only while the pointer rests there, fading
// over the look's `icon.fade`; the bridge, one rectangle from inside the
// hit square to the row's far corner, and the look's `icon.hold` keep it
// shown on the way to an icon. A right click on any of them opens the
// Jarvis menu (WidgetView.menuEntries) at the click; the overlay stays
// shown while it is open. A conversation at rest keeps its icon row
// reachable. An unavailable service takes no pointer.
Item {
    id: root
    property var screen: null
    property var service: null
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property var host: QsWindow.window
    readonly property var state: service === null ? null : service.sessionState
    readonly property string phase: state === null ? "down" : Session.phaseOf(state)
    readonly property bool hidden: state !== null && state.visibility.kind === "hidden"
    // The menu holds the overlay shown: qs.Ui's Menu closes when the item
    // it opened from hides.
    readonly property bool shown: service !== null && screen !== null
        && (menuOpened || service.bubbleWanted && screen.name === service.focusedOutput)
    readonly property bool presented: shown && visible && host !== null && host.presented === true
        && overlay.width > 0 && overlay.height > 0 && overlay.x >= 0 && overlay.y >= 0
        && overlay.width <= width && overlay.height + look.layout.margin <= height
    readonly property bool capturePresented: presented && !hidden && orb.visible
    readonly property var hold: state !== null && state.approval.kind === "held" ? state.approval : null
    // A held request would cover the console's message field and hint line
    // where the console on this screen reaches the band the overlay draws in
    // at the bottom; the overlay then takes the top edge. Both boxes are in this
    // layer's coordinates (Service.consoleBox).
    readonly property var consoleBox: service === null ? null : service.consoleBox
    readonly property bool overConsole: hold !== null && consoleBox !== null && screen !== null
        && consoleBox.output === screen.name
        && consoleBox.y + consoleBox.height > height - look.layout.margin - overlay.height
        && consoleBox.y < height - look.layout.margin
        && consoleBox.x < overlay.x + overlay.width && consoleBox.x + consoleBox.width > overlay.x
    // The current hold's placement is known: the service's last finished
    // read answers this hold. Until then the request neither draws nor
    // acknowledges a frame, so its first drawn frame is the placed one.
    readonly property bool placed: service !== null && service.consoleKey === service.heldKey
    property var displayedHold: null
    property var approvalFrames: []
    property var synchronizedHold: null
    // The held request's column laid out whole inside the layer: it draws
    // every line it acknowledges, a payload past the room the layer leaves
    // in its scrolled region, which the pointer reaches.
    readonly property bool approvalWhole: hold !== null && approvalText.text === hold.text
        && approvalText.height >= approvalText.implicitHeight
        && overlay.x + approvalText.x >= 0 && overlay.x + approvalText.x + approvalText.width <= width
        && overlay.y + approvalText.y >= 0 && overlay.y + approvalText.y + approvalText.height <= height
    readonly property bool approvalPresented: presented && displayedHold !== null && hold !== null
        && displayedHold.id === hold.id && displayedHold.digest === hold.digest && displayedHold.gen === hold.gen
        && approvalWhole
    onHoldChanged: {
        if (hold === null || displayedHold === null || hold.id !== displayedHold.id
                || hold.gen !== displayedHold.gen || hold.digest !== displayedHold.digest) displayedHold = null;
    }
    // Qt 6.11 afterAnimating runs on the GUI thread after polish, before sync.
    // afterSynchronizing and frameSwapped queue from the render thread in order.
    // Pair each sync with its polish snapshot, including frames without a hold:
    // a queued old swap must not consume a newer request's GUI state.
    // https://doc.qt.io/qt-6/qquickwindow.html#afterSynchronizing
    function approvalPolished() {
        approvalFrames.push(shown && visible && placed && approvalWhole ? hold : null);
    }
    function approvalSynchronized() {
        synchronizedHold = approvalFrames.length === 0 ? null : approvalFrames.shift();
    }
    function approvalSwapped() {
        const drawn = synchronizedHold;
        if (drawn === null || displayedHold !== null) return;
        // LayerHost observes this swap too. Its presented value must settle
        // before the service checks this frame's unchanged request identity.
        Qt.callLater(() => {
            if (!root.presented || root.hold === null || root.hold.id !== drawn.id
                    || root.hold.gen !== drawn.gen || root.hold.digest !== drawn.digest) return;
            root.displayedHold = drawn;
            if (root.service !== null) root.service.shownApproval(root, drawn);
        });
    }
    Connections {
        target: root.Window.window
        function onAfterAnimating() { root.approvalPolished(); }
        function onAfterSynchronizing() { root.approvalSynchronized(); }
        function onFrameSwapped() { root.approvalSwapped(); }
    }
    readonly property var microphoneMute: service === null ? null : View.microphoneMuted(service.microphoneMute)
    readonly property bool micMuted: microphoneMute === true
    readonly property bool voiceMuted: state !== null && state.voiceMute.kind === "on"
    // A fault reads as the bar says it: what went wrong, then what to do.
    // A restart after a failed turn reads the same way while the orb shows.
    readonly property var fault: phase === "error" ? View.faultText(state.fault, state.engine.kind,
        service.shell === null ? null : Providers.cloudVoice(service.shell.settings.voiceProvider))
        : state === null || hidden ? null : View.restartLine(state.restart, state.conversation.kind !== "ended")
    readonly property string stateText: state === null ? "" : hidden && fault !== null ? fault.title : micMuted ? "Microphone muted"
        : fault !== null ? fault.title
        : stateWords[phase]
    readonly property var levels: service === null || service.shell === null ? {}
        : service.shell.status.values.level || {}
    readonly property var caption: service === null || service.shell === null ? null
        : service.shell.status.values.transcript || null
    // Jarvis's words for this conversation, shown only while its voice is
    // muted. The caption is the conversation's latest line, the user's or
    // Jarvis's; only Jarvis's draws, so the user's words clear it. The
    // status keeps an ended conversation's caption until the next one.
    // A held request shows its own question in their place.
    readonly property string words: state === null || hidden || !voiceMuted || root.hold !== null ? ""
        : caption !== null && caption.role === "assistant" && caption.gen === state.gen ? caption.text : ""
    readonly property var shortcutKeys: service === null ? null : service.effectiveKeys
    // The ring of the orb at rest, which the icon row and the line under
    // the orb stand against.
    readonly property real ring: look.state.idle.radius * look.orb.size / 2
    readonly property string orbPhase: micMuted ? "muting" : phase
    readonly property bool active: state !== null && state.conversation.kind !== "ended"
        || ["listening", "thinking", "acting", "speaking", "confirming", "error"].indexOf(orbPhase) !== -1
    // The pointer rests on the orb, the bridge or an icon; the icons stay
    // `icon.hold` after it leaves all three.
    readonly property bool pointerOver: orbHover.hovered || bridgeHover.hovered || mic.hovered || voice.hovered || stop.hovered
    onPointerOverChanged: if (pointerOver) iconHold.stop(); else iconHold.restart()
    readonly property bool iconsWanted: !hidden && active && (pointerOver || iconHold.running)
    property real iconOpacity: iconsWanted ? 1 : 0
    Behavior on iconOpacity { NumberAnimation { duration: root.look.icon.fade; easing.type: root.look.icon.easing } }
    readonly property bool iconsShown: !hidden && iconOpacity > 0
    readonly property var menuEntries: View.menuEntries(microphoneMute, voiceMuted, hidden, Session.hideRefusal(state))
    // The Jarvis menu's entry that sends INTENT.
    function entryFor(intent) {
        return menuEntries.find(entry => entry.intent === intent);
    }
    readonly property bool menuOpened: menuUi.item !== null && menuUi.item.opened
    // The open menu's entries, which scripts/smoke/rows/jarvis-bubble.sh
    // reads, [] while it is closed.
    readonly property var menuTexts: menuUi.item === null ? [] : menuUi.item.texts
    readonly property var textItems: [words, stateLine, silenceLine, faultAction, question, fullPath, payloadArea, physicalHint]
    readonly property var inputItems: !shown || !visible ? [] : (active && !hidden ? [orbHit] : [])
        .concat(active && iconsShown ? [bridge] : [])
        .concat(active ? textItems.filter(item => root.drawn(item)) : [])
        .concat(hold === null || !approvalText.visible ? [] : [cancel, confirm])
        // A fault behind the muted microphone's look keeps its link.
        .concat(!active && faultAction.visible && faultAction.linked ? [faultAction] : [])
    // Whether ITEM and every item over it up to the overlay show.
    function drawn(item) {
        for (let at = item; at !== null && at !== overlay; at = at.parent)
            if (!at.visible) return false;
        return true;
    }
    // A Jarvis menu entry: its intent, as its key sends it, or the page it
    // opens.
    function runEntry(entry) {
        if (service === null || entry.disabledReason) return;
        if (entry.intent !== undefined) service.intent(entry.intent);
        else if (service.shell !== null) service.shell.surfaces.openPage(entry.page, entry.tab);
    }
    readonly property var stateWords: ({
        idle: "Ready to talk", listening: "Listening", thinking: "Thinking",
        acting: "Working", speaking: "Speaking", confirming: "Waiting for you", error: "", down: "Stopping"
    })

    // One button of the icon row: the look's glyph and ring colours, and
    // its Jarvis menu entry, whose intent it sends and whose label it
    // reads, with the effective key, or the label alone with none. An
    // inline component does not share this file's scope
    // (https://doc.qt.io/qt-6/qtqml-documents-definetypes.html#inline-components),
    // so each takes the look, the service and the keys. Its instances read
    // as type RowButton, not IconButton (qml-unit run, Qt 6.12.0), which
    // scripts/smoke/rows/jarvis-bubble.sh names.
    component RowButton: IconButton {
        required property var look
        required property var service
        required property var keys
        required property var entry
        size: "sm"
        label: entry.label
        tooltip: keys === null || !keys[entry.intent] ? label : label + " (" + keys[entry.intent] + ")"
        restColor: look.icon.rest
        activeColor: look.icon.active
        onColor: look.palette.accent
        ringColor: look.icon.ring
        disabledReason: entry.disabledReason || ""
        onClicked: if (service !== null) service.intent(entry.intent)
    }

    // One answer of the approval prompt in the look's form (Appearance.js
    // `answer`): Confirm or Yes on its fill with the shimmer, Cancel or No
    // as bare words. It is a qs.Ui Button handed the look's values, since a
    // surface draws no private control for what a component draws
    // (design-system.md § Components). The variant names the answer for
    // scripts/smoke/rows/jarvis-bubble.sh and sets the label's weight.
    component Answer: Button {
        required property var look
        property bool bare: false
        size: "sm"
        variant: bare ? "ghost" : "secondary"
        controlHeight: look.answer.height
        paddingX: look.answer.paddingX
        radius: look.answer.radius
        restFill: bare ? look.answer.clear : look.answer.fill
        hoverFill: bare ? look.answer.clear : look.answer.hoverFill
        pressedFill: look.answer.pressedFill
        borderColor: look.answer.clear
        textColor: bare ? look.answer.bareInk : look.answer.ink
        hoverTextColor: bare ? look.answer.bareHoverInk : look.answer.hoverInk
        ringColor: look.icon.ring
        shimmer: bare ? null : look.answer.shimmer
        shadow: look.shadow
    }

    // The field's boxes in this item's coordinates (Field.js), each the box
    // its items lay out in, so the field and the content share one size: the
    // orb's disc, the icon row while it shows, receding as it fades, the
    // line or the held request under the orb, and Jarvis's words over it.
    readonly property var fieldBoxes: {
        const at = item => ({ x: overlay.x + item.x, y: overlay.y + item.y, w: item.width, h: item.height });
        const rects = [];
        if (iconsShown) rects.push({ rect: at(icons), values: look.field.icons, recede: -Math.log(Math.max(iconOpacity, 1e-4)) });
        if (hold !== null || stateBox.visible) rects.push({ rect: at(hold === null ? stateBox : approvalText), values: look.field.content, recede: 0 });
        if (words.visible) rects.push({ rect: at(words), values: look.field.content, recede: 0 });
        const boxes = Field.boxes(look.field, { x: overlay.x + overlay.centre, y: overlay.y + overlay.orbCentre }, ring, rects, width);
        return hidden ? boxes.slice(1) : boxes;
    }

    visible: shown && (hold === null ? true : placed)
    Component.onCompleted: if (service !== null) service.attachBubble(root)

    // The field, drawn only over the boxes' reach inside this layer.
    RadialBackdrop {
        id: field
        objectName: "field"
        visible: root.fieldBoxes.length > 0
        readonly property var extent: Field.extent(root.fieldBoxes, root.width, root.height)
        x: extent.x
        y: extent.y
        width: extent.w
        height: extent.h
        boxes: root.fieldBoxes.map(b => Object.assign({}, b, { x: b.x - extent.x, y: b.y - extent.y }))
        join: root.look.field.join
        blend: root.look.field.blend
        falloff: root.look.field.falloff
        halo: ({ strength: root.hidden ? 0 : root.look.field.orb.halo.strength, width: root.look.field.orb.halo.width,
                 ring: root.look.field.orb.halo.ring * root.ring, stops: orb.stops })
    }
    Component.onDestruction: if (service !== null) service.detachBubble(root)

    Item {
        id: overlay
        // The box scripts/smoke/rows/jarvis-bubble.sh places.
        objectName: "overlay"
        readonly property real centre: width / 2
        readonly property real orbCentre: orb.y + orb.height / 2
        readonly property real below: root.hidden ? 0 : orbCentre + root.ring + root.look.layout.below
        // The prompt's and the words' width, held to this overlay's, which
        // the layer bounds, so a narrow screen reflows them.
        readonly property real promptWidth: Math.min(root.look.layout.prompt, width)
        width: Math.min(root.look.layout.width, Math.max(0, root.width - 2 * root.look.layout.margin))
        height: Math.max(root.hidden ? 0 : orb.y + orb.height,
            root.hold !== null ? approvalText.y + approvalText.height : stateBox.visible ? stateBox.y + stateBox.height : 0)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.look.layout.margin
        anchors.topMargin: root.look.layout.margin
        // AnchorChanges releases the bottom anchor as it sets the top one,
        // where two bindings could hold both for a moment and stretch the
        // overlay: https://doc.qt.io/qt-6/qml-qtquick-anchorchanges.html
        states: State {
            name: "top"
            when: root.overConsole
            AnchorChanges { target: overlay; anchors.bottom: undefined; anchors.top: root.top }
        }

        Words {
            id: words
            window: root.look.words.lines
            stepDuration: root.look.words.step
            fadeDuration: root.look.words.fade
            liftDuration: root.look.words.lift
            newestInk: root.look.ink.words
            olderInk: root.look.ink.words
            newestOpacity: root.look.words.newest
            middleOpacity: root.look.words.middle
            oldestOpacity: root.look.words.oldest
            shadow: root.look.shadow
            x: overlay.centre - width / 2
            width: overlay.promptWidth
            height: visible ? implicitHeight : 0
            text: root.words
        }

        // An open conversation at rest uses the look's idle pacing.
        ParticleOrb {
            id: orb
            look: root.look
            x: overlay.centre - width / 2
            y: words.height
            width: root.look.orb.size
            height: root.look.orb.size
            phase: root.orbPhase
            capture: root.levels.capture || 0
            playback: root.levels.playback || 0
            visible: !root.hidden
            active: root.shown && visible
        }

        // The orb's input square while the overlay is active.
        Item {
            id: orbHit
            objectName: "orbHit"
            visible: root.active && !root.hidden
            width: root.look.layout.hit
            height: root.look.layout.hit
            x: overlay.centre - width / 2
            y: overlay.orbCentre - height / 2
            HoverHandler { id: orbHover }
        }

        // The icon row's input while it shows: from inside the hit square,
        // `layout.bridge` right of and above the orb's centre, to the row's
        // far corner, so it holds the row and meets the square.
        Item {
            id: bridge
            objectName: "iconBridge"
            visible: root.active && root.iconsShown
            x: overlay.centre + root.look.layout.bridge
            y: icons.y
            width: icons.x + icons.width - x
            height: overlay.orbCentre - root.look.layout.bridge - y
            HoverHandler { id: bridgeHover }
        }

        Timer { id: iconHold; interval: root.look.icon.hold }

        Row {
            id: icons
            x: overlay.centre + root.ring
            y: overlay.orbCentre - root.ring - height / 2
            opacity: root.iconOpacity
            visible: root.iconsShown
            RowButton {
                id: voice
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                entry: root.entryFor("voice-mute")
                iconName: root.voiceMuted ? "volume-x" : "volume-2"
                checked: root.voiceMuted
            }
            RowButton {
                id: mic
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                entry: root.entryFor("microphone-mute")
                iconName: root.micMuted ? "mic-off" : "mic"
                checked: root.micMuted
            }
            RowButton {
                id: stop
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                entry: root.entryFor("stop")
                iconName: "square"
            }
        }

        Column {
            id: stateBox
            x: overlay.centre - width / 2
            y: overlay.below
            width: Math.min(root.look.layout.line, overlay.width)
            visible: root.hold === null && (!root.hidden || root.fault !== null)
            spacing: root.look.layout.gap
            Label {
                id: stateLine
                width: parent.width
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                role: root.fault !== null ? "bodyStrong" : "label"
                color: root.fault !== null ? root.look.ink.title : root.look.ink.state
                text: root.stateText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            LinkText {
                id: silenceLine
                width: parent.width
                visible: !root.hidden && root.state !== null && root.state.sound.kind === "silent" && !root.micMuted
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                role: "body"
                color: root.look.ink.action
                linkColor: root.look.ink.link
                text: visible ? "Jarvis hears no sound from " + root.state.sound.device + ". [Microphone](page:vgs.jarvis/Settings/microphone)" : ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => {
                    if (root.service !== null && root.service.shell !== null) root.service.shell.surfaces.openPage(page, tab);
                }
            }
            // The fault's action, its page reference drawn as a link that
            // opens the page (design-system.md § Copy).
            LinkText {
                id: faultAction
                width: parent.width
                visible: root.fault !== null
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                role: "body"
                color: root.look.ink.action
                linkColor: root.look.ink.link
                text: root.fault === null ? "" : root.fault.action
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => {
                    if (root.service !== null && root.service.shell !== null) root.service.shell.surfaces.openPage(page, tab);
                }
            }
        }

        Column {
            id: approvalText
            x: overlay.centre - width / 2
            y: overlay.below
            width: overlay.promptWidth
            visible: root.hold !== null
            spacing: root.look.layout.gap
            readonly property var prompt: View.approvalPrompt(root.hold)
            // Recombine the actual drawn labels for the existing frame
            // identity check; a missing path or detail cannot acknowledge.
            readonly property string text: question.text + (prompt !== null && prompt.filePrompt ? "\n" + (fullPath.visible ? fullPath.text : "")
                + (prompt.detail ? "\n" + (payload.visible ? payload.text : "") : "") : "")
            Label {
                id: question
                width: parent.width
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                role: "bodyStrong"
                color: root.look.ink.question
                text: approvalText.prompt === null ? "" : approvalText.prompt.question
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Label {
                id: fullPath
                width: parent.width
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                visible: text !== ""
                role: "hint"
                color: root.look.ink.path
                text: approvalText.prompt === null ? "" : approvalText.prompt.path
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            // The payload, whole while it fits the room the layer leaves it
            // under the orb, beside the column's other lines and the answers,
            // so a keyboard user, whom this passive layer gives no keys
            // (D026), reads every line Confirm confirms. A payload past that
            // room scrolls in the larger of the room and the look's
            // `layout.payload`, keeping the answers on the screen; it takes
            // the wheel and a touchpad swipe while the overlay takes the
            // pointer. On a layer shorter than that floor the column leaves
            // the layer, and `approvalWhole` holds the request unanswered.
            ScrollArea {
                id: payloadArea
                // The column's other lines and gaps: Column lays out only an
                // item that is visible and whose width and height are not 0, with
                // one spacing between each two it lays out
                // (https://doc.qt.io/qt-6/qml-qtquick-column.html). The
                // overlay keeps the margin to the layer's edge at its bottom,
                // or at its top over the console.
                readonly property var others: [question, fullPath, physicalHint, answerButtons].filter(item => item.visible && item.width > 0 && item.height > 0)
                readonly property real room: root.height - root.look.layout.margin - overlay.below
                    - others.reduce((sum, item) => sum + item.height + approvalText.spacing, 0)
                width: parent.width
                height: Math.min(payload.implicitHeight, Math.max(root.look.layout.payload, Math.floor(room)))
                // The payload's own text, not its visible, which reads false
                // while this area hides it
                // (https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop).
                visible: payload.text !== ""
                // The text shadow's layer is this region's, not the
                // payload's. Qt sizes an Item layer to the item's own
                // bounding rectangle whatever an ancestor clips
                // (QQuickItemLayer::updateGeometry, qtdeclarative 6.12), and
                // bounds its texture to the RHI's maximum texture size,
                // warning "Unsupported size requested"
                // (QSGRhiLayer::setSize, qtdeclarative 6.12): a 16 KiB
                // payload's layer, past 16384 px tall, would not draw at
                // its size.
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                Label {
                    id: payload
                    width: parent.width
                    // The area keeps its bar's inset on the right; the same
                    // inset on the left centres the lines on the column.
                    leftPadding: payloadArea.rightInset
                    visible: text !== ""
                    role: "body"
                    color: root.look.ink.payload
                    text: approvalText.prompt === null ? "" : approvalText.prompt.payload
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
            Label {
                id: physicalHint
                width: parent.width
                layer.enabled: true
                layer.effect: TextShadow { shadow: root.look.shadow }
                visible: root.hold !== null && root.hold.physical
                role: "hint"
                color: root.look.ink.hint
                text: "Use the button or key to confirm."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Row {
                id: answerButtons
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.look.answer.gap
                // keyboard-path: the effective Confirm and Stop shortcuts.
                Answer {
                    id: cancel
                    look: root.look
                    bare: true
                    text: root.hold !== null && root.hold.purpose === "release" ? "No" : "Cancel"
                    onClicked: if (root.service !== null) root.service.cancelApproval(root.displayedHold)
                }
                Answer {
                    id: confirm
                    look: root.look
                    text: root.hold !== null && root.hold.purpose === "release" ? "Yes" : "Confirm"
                    onClicked: if (root.service !== null) root.service.confirmApproval(root.displayedHold, "button")
                }
            }
        }

        // TapHandler's default DragThreshold policy takes a passive grab
        // (Qt Quick TapHandler gesturePolicy reference), and the answers and
        // icons take the left button alone, so a right click anywhere the
        // layer takes the pointer reaches this handler.
        // pointer-cursor-exempt: a right click on the orb or its text, which show no control
        // keyboard-path: voice mute and Stop have shortcuts; the bar widget's menu holds the same system microphone action
        TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: root.active
            onTapped: eventPoint => {
                menuUi.active = true;
                menuUi.item.openAt(eventPoint.position.x, eventPoint.position.y);
            }
        }

        // The menu is built on the first right click and released once
        // closed, so an overlay at rest holds none.
        Loader {
            id: menuUi

            function release() {
                if (item !== null && !item.opened) active = false;
            }

            active: false
            sourceComponent: Item {
                id: menuAnchor

                readonly property bool opened: orbMenu.opened
                readonly property var texts: orbMenu.opened ? orbMenu.items().map(entry => entry.text) : []

                // The menu opens at this item's bottom-left corner, the
                // click.
                function openAt(clickX, clickY) {
                    x = clickX;
                    y = clickY;
                    orbMenu.open("pointer");
                }

                width: root.look.layout.anchor
                height: root.look.layout.anchor
                onOpenedChanged: if (!opened) Qt.callLater(menuUi.release)

                Menu {
                    id: orbMenu

                    Repeater {
                        model: root.menuEntries
                        MenuItem {
                            required property var modelData
                            text: modelData.label
                            iconName: modelData.icon
                            disabledReason: modelData.disabledReason || ""
                            onTriggered: root.runEntry(modelData)
                        }
                    }
                }
            }
        }
    }
}
