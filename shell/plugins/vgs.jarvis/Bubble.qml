import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance
import "Session.js" as Session
import "WidgetView.js" as View
import "AccountProviders.js" as Providers

// Jarvis's overlay at the bottom centre of the focused screen: the particle
// orb in the look of the Session's phase, its icon row beside the orb,
// the state line or the fault under it, the held request in place
// of that line, and Jarvis's words above the orb while its voice is muted.
// It draws in the plugin's own look (Appearance.js). Nothing stands
// behind the orb: its points read on any wallpaper by their own edge. The
// icon row stands on a capsule beside it, and the words and the line or
// the held request each on a card that hugs its lines. Each is a plate of
// the shared glass (qs.Ui GlassSurface) in the lens form, in the look's
// `plate` values, with no drop shadow. No plate's box enters another's:
// the look's `plate.gap` parts them, so each draws as glass
// (GlassSurface.overContent). A plate shows whole and never fades; what
// stands on it fades. A passive layer takes clicks only on `inputItems`
// (D026).
//
// While the overlay is active (listening, thinking, acting, speaking, a
// held request or a fault) the orb takes the pointer on the look's hit
// square over its centre, and each line of text and answer while it
// shows. The icon row shows only while the pointer rests there, fading
// over the look's `icon.fade`; the bridge, one rectangle from inside the
// hit square to the capsule's far edge, and the look's `icon.hold` keep it
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
    // A capture shows only on an orb a pointer can use: one at least as
    // wide as one of its own icon buttons.
    readonly property bool capturePresented: presented && !hidden && orb.visible && orb.width >= icons.width
    readonly property var hold: state !== null && state.approval.kind === "held" ? state.approval : null
    // Judge the centred bottom box, not the fitted box: moving beside the
    // Console or wrapping a line there must not change this decision.
    // Both boxes are in this layer's coordinates (Service.consoleBox).
    readonly property real bottomWidth: Math.min(look.layout.width, Math.max(0, width - 2 * look.layout.margin))
    readonly property real bottomInset: Math.round((1 - look.orb.reach) * look.orb.size / 2)
    readonly property real bottomOrbTop: (words.visible ? words.y + words.height + look.plate.card.paddingY + look.plate.gap : 0) - bottomInset
    readonly property real bottomBelow: hidden ? look.plate.card.paddingY
        : bottomOrbTop + look.orb.size - bottomInset + look.plate.gap + look.plate.card.paddingY
    readonly property real bottomHeight: hold !== null ? overlay.height
        : Math.max(hidden ? 0 : bottomOrbTop + look.orb.size - bottomInset, stateBox.visible ? bottomBelow + bottomMeasure.height + look.plate.card.paddingY : 0)
    // A card's side inset on a side BOX_WIDTH wide whose widest word is
    // WIDEST: the look's padding where that word fits inside it, so the
    // lines break only at spaces; on a narrower side, as much less as the
    // word needs, down to the lens band plus what the rounded rim takes
    // from the first line's edge, past which the text would meet the rim
    // (design-system.md § Glass plates over wallpaper).
    readonly property real cardInsetFloor: {
        const r = look.plate.card.radius, rise = Math.max(0, r - look.plate.card.paddingY);
        return Math.ceil(look.plate.lens.bezel + r - Math.sqrt(r * r - rise * rise));
    }
    function cardInset(boxWidth, widest) {
        return Math.max(cardInsetFloor, Math.min(look.plate.card.paddingX, Math.floor((boxWidth - widest) / 2)));
    }
    readonly property real stateWidest: Math.max(stateWidestWord.implicitWidth, bodyWidestWord.implicitWidth)
    readonly property var consoleBox: service === null ? null : service.consoleBox
    readonly property bool overConsole: consoleBox !== null && screen !== null
        && consoleBox.output === screen.name
        && consoleBox.y + consoleBox.height > height - look.layout.margin - bottomHeight
        && consoleBox.y < height - look.layout.margin
        && consoleBox.x < (width + bottomWidth) / 2 && consoleBox.x + consoleBox.width > (width - bottomWidth) / 2
    // A held request retains its centred top placement and frame contract.
    // Other states fit the roomier side, leaving the plates clear of Console.
    readonly property bool besideConsole: hold === null && overConsole
    readonly property rect placementRoom: {
        if (!besideConsole) return Qt.rect(0, 0, width, height);
        const left = Math.max(0, Math.min(width, consoleBox.x));
        const right = Math.max(0, Math.min(width, width - consoleBox.x - consoleBox.width));
        return left >= right
            ? Qt.rect(0, 0, Math.max(0, left - look.layout.margin), height)
            : Qt.rect(width - right + look.layout.margin, 0, Math.max(0, right - look.layout.margin), height);
    }
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
    readonly property var textItems: [words, stateLine, silenceLine, faultAction, question, fullPath, payloadArea]
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
        // The capsule stands top to bottom, so a tooltip opens beside it.
        tooltipSide: "right"
        restColor: look.icon.rest
        activeColor: look.icon.active
        onColor: look.icon.on
        ringColor: look.icon.ring
        disabledReason: entry.disabledReason || ""
        onClicked: if (service !== null) service.intent(entry.intent)
    }

    // One answer of the approval prompt in the look's form (Appearance.js
    // `answer`): a capsule, Confirm or Yes on the tint, Cancel or No quiet,
    // and the confirming answer of a destructive request quiet too.
    // It is a qs.Ui Button handed the look's values, since a surface draws
    // no private control for what a component draws (design-system.md
    // § Components). Its variant names its role, ghost for the answer that
    // declines and secondary for the one that confirms, which
    // scripts/smoke/rows/jarvis-bubble.sh reads; the look hands every
    // value the variant would draw.
    component Answer: Button {
        required property var look
        property bool quiet: false
        readonly property var form: quiet ? look.answer.quiet : look.answer.tinted
        size: "sm"
        controlHeight: look.answer.height
        paddingX: look.answer.paddingX
        centerContent: true
        radius: look.answer.radius
        restFill: form.fill
        hoverFill: form.hoverFill
        pressedFill: form.pressedFill
        borderColor: look.answer.clear
        textColor: form.ink
        ringColor: look.icon.ring
    }

    visible: shown && (hold === null ? true : placed)
    Component.onCompleted: if (service !== null) service.attachBubble(root)

    // Text implicit sizes measure the un-fitted bottom column without
    // depending on the side's width (Quickshell 0.3.1 size and position:
    // https://quickshell.org/docs/v0.3.1/guide/size-position/).
    // The drawn controls still own their text and typography.
    Item {
        id: bottomMeasure
        visible: false
        width: Math.min(root.look.layout.line, Math.max(0, root.bottomWidth - 2 * root.cardInset(root.bottomWidth, root.stateWidest)))
        height: bottomTitle.implicitHeight
            + (silenceLine.visible ? root.look.layout.gap + bottomSilence.implicitHeight : 0)
            + (faultAction.visible ? root.look.layout.gap + bottomAction.implicitHeight : 0)
        Label {
            id: bottomTitle
            width: parent.width
            role: stateLine.role
            color: stateLine.color
            text: stateLine.text
            wrapMode: stateLine.wrapMode
        }
        LinkText {
            id: bottomSilence
            width: parent.width
            role: silenceLine.role
            color: silenceLine.color
            linkColor: silenceLine.linkColor
            text: silenceLine.text
            wrapMode: silenceLine.wrapMode
        }
        // Each card's words one to a line and never wrapped, so each label
        // is as wide as its widest word.
        Label {
            id: stateWidestWord
            role: stateLine.role
            textFormat: Text.PlainText
            text: root.stateText.trim().split(/\s+/).join("\n")
        }
        Label {
            id: bodyWidestWord
            role: "body"
            textFormat: Text.PlainText
            text: ((silenceLine.visible ? silenceLine.plain : "") + " " + (faultAction.visible ? faultAction.plain : "")).trim().split(/\s+/).join("\n")
        }
        Label {
            id: wordsWidestWord
            role: "body"
            textFormat: Text.PlainText
            text: root.words.trim().split(/\s+/).join("\n")
        }
        LinkText {
            id: bottomAction
            width: parent.width
            role: faultAction.role
            color: faultAction.color
            linkColor: faultAction.linkColor
            text: faultAction.text
            wrapMode: faultAction.wrapMode
        }
    }

    Component.onDestruction: if (service !== null) service.detachBubble(root)

    Item {
        id: overlay
        // The box scripts/smoke/rows/jarvis-bubble.sh places.
        objectName: "overlay"
        readonly property real centre: width / 2
        readonly property real orbMiddle: orb.x + orb.width / 2
        readonly property real orbCentre: orb.y + orb.height / 2
        // REVISIT(D132): change these grounds only if the look no longer
        // owns the plates' lens values and glass-off standard surface.
        readonly property var card: root.look.plate.card
        // Where what the orb draws starts: the top, or the plates' gap under
        // the words' card.
        readonly property real rowTop: words.visible ? words.y + words.height + card.paddingY + root.look.plate.gap : 0
        // The whole group stacked with the capsule under an orb fitted to
        // the full side: the orb's drawn height, the capsule and the state
        // card. It reads only sizes this box's width sets, never this box's
        // height or the chosen orb, which both follow the choice.
        readonly property real belowOrb: Math.min(root.look.orb.size, width)
        readonly property real belowExtent: rowTop + belowOrb - 2 * Math.round((1 - root.look.orb.reach) * belowOrb / 2)
            + root.look.plate.gap + iconPill.height
            + (stateBox.visible ? root.look.plate.gap + 2 * card.paddingY + stateBox.height : 0)
        // The height `presented` lets this box take above the layer's margin.
        readonly property real layerRoom: root.height - root.look.layout.margin
        readonly property real rowRoom: width - iconPill.width - root.look.plate.gap
        // Choose the group arrangement before assigning any box. A row that
        // leaves the orb's normal hover target stays a row. A tighter side
        // stacks the capsule under the orb when the whole stack fits the
        // layer, or when the row would leave the orb narrower than one of
        // its icon buttons; otherwise the smaller row keeps the orb and the
        // cards on the output. A stack that then overflows the layer is not
        // presented. Hidden icons keep the same geometry, so entering the
        // orb cannot move it out from under the pointer.
        readonly property bool capsuleBelow: root.besideConsole
            && width < root.look.layout.hit + iconPill.width + root.look.plate.gap
            && (rowRoom < icons.width || belowExtent <= layerRoom)
        readonly property real orbRoom: root.besideConsole && !capsuleBelow ? rowRoom : width
        // The orb draws nothing in the outer `orbInset` of its canvas, a
        // whole number of pixels, so the plates stand that far inside it.
        readonly property real orbInset: Math.round((1 - root.look.orb.reach) * orb.width / 2)
        readonly property real orbEnd: orb.y + orb.height - orbInset
        readonly property real rowEnd: root.besideConsole ? Math.max(orbEnd, iconPill.y + iconPill.height) : orbEnd
        // A taller capsule beside the orb reserves room above and below the
        // fitted orb so neither it nor the next card is clipped.
        readonly property real orbTop: rowTop - orbInset
            + (root.besideConsole && !capsuleBelow ? Math.max(0, (iconPill.height - orb.height + 2 * orbInset) / 2) : 0)
        // The first line under the orb row: inside its card, the plates'
        // gap under both the orb and its capsule.
        readonly property real below: root.hidden ? card.paddingY
            : rowEnd + root.look.plate.gap + card.paddingY
        // The prompt's width, held inside this overlay's, which the layer
        // bounds, so a narrow screen reflows it.
        readonly property real promptWidth: Math.min(root.look.layout.prompt, Math.max(0, width - 2 * card.paddingX))
        // The state card's and the words card's side insets on this side.
        readonly property real stateInset: root.cardInset(width, root.stateWidest)
        readonly property real wordsInset: root.cardInset(width, wordsWidestWord.implicitWidth)
        width: Math.min(root.look.layout.width, Math.max(0, root.placementRoom.width - 2 * root.look.layout.margin))
        height: Math.max(root.hidden ? 0 : rowEnd,
            root.hold !== null ? approvalText.y + approvalText.height + card.paddingY
            : stateBox.visible ? stateBox.y + stateBox.height + card.paddingY : 0)
        x: root.placementRoom.x + (root.placementRoom.width - width) / 2
        // Qt Quick clips descendants to this box, including overwide
        // words on a side too narrow for their natural size.
        // https://doc.qt.io/qt-6/qml-qtquick-item.html#clip-prop
        clip: root.besideConsole
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.look.layout.margin
        anchors.topMargin: root.look.layout.margin
        // AnchorChanges releases the bottom anchor as it sets the top one,
        // where two bindings could hold both for a moment and stretch the
        // overlay: https://doc.qt.io/qt-6/qml-qtquick-anchorchanges.html
        states: State {
            name: "top"
            when: root.overConsole && root.hold !== null
            AnchorChanges { target: overlay; anchors.bottom: undefined; anchors.top: root.top }
        }

        // An open conversation at rest uses the look's idle pacing.
        ParticleOrb {
            id: orb
            look: root.look
            // On whole pixels, so each point draws on the pixel grid.
            x: Math.round((root.besideConsole ? overlay.orbRoom : overlay.width) / 2 - width / 2)
            y: overlay.orbTop
            width: root.besideConsole ? Math.min(root.look.orb.size, overlay.orbRoom) : root.look.orb.size
            height: width
            phase: root.orbPhase
            capture: root.levels.capture || 0
            playback: root.levels.playback || 0
            visible: !root.hidden
            active: root.shown && visible
        }

        // The words' card is as wide as the caption's column, so no word
        // moves its sides, and as tall as the lines shown, the newest at
        // its bottom: it follows a new line up as that line lifts the
        // others.
        GlassSurface {
            id: wordsCard
            objectName: "wordsCard"
            visible: words.visible
            x: Math.round(overlay.centre - width / 2)
            y: words.y + words.height - words.shownHeight
                + (words.lineCount <= words.window ? words.lift : 0) - overlay.card.paddingY
            width: words.width + 2 * overlay.wordsInset
            height: words.y + words.height + overlay.card.paddingY - y
            optIn: true
            fill: overlay.card.fill
            standard: ({ background: overlay.card.base, border: overlay.card.border, radius: overlay.card.radius })
            elevation: "none"
            lens: root.look.plate.lens
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
            x: overlay.centre - width / 2
            y: overlay.card.paddingY
            width: Math.min(root.look.layout.prompt, Math.max(0, overlay.width - 2 * overlay.wordsInset))
            height: visible ? implicitHeight : 0
            text: root.words
        }

        // The orb's input square while the overlay is active.
        Item {
            id: orbHit
            objectName: "orbHit"
            visible: root.active && !root.hidden
            width: root.besideConsole ? Math.min(root.look.layout.hit, overlay.orbRoom) : root.look.layout.hit
            height: width
            x: overlay.orbMiddle - width / 2
            y: overlay.orbCentre - height / 2
            HoverHandler { id: orbHover }
        }

        // The bridge follows the chosen edge from inside the hit square
        // to the capsule's far edge. Both arrangements keep one connected
        // pointer route, including when the hit square fits a narrow side.
        Item {
            id: bridge
            objectName: "iconBridge"
            visible: root.active && root.iconsShown
            x: overlay.capsuleBelow ? iconPill.x
                : overlay.orbMiddle + root.look.layout.bridge * orbHit.width / root.look.layout.hit
            y: overlay.capsuleBelow ? overlay.orbCentre + root.look.layout.bridge * orbHit.height / root.look.layout.hit
                : iconPill.y
            width: overlay.capsuleBelow ? iconPill.width : iconPill.x + iconPill.width - x
            height: overlay.capsuleBelow ? iconPill.y + iconPill.height - y : iconPill.height
            HoverHandler { id: bridgeHover }
        }

        Timer { id: iconHold; interval: root.look.icon.hold }

        // The capsule follows the group's chosen edge. It shows whole
        // while its icons fade.
        GlassSurface {
            id: iconPill
            objectName: "iconPill"
            readonly property var pad: root.look.plate.pill
            readonly property real rest: orb.x + orb.width - overlay.orbInset + root.look.plate.gap
            x: overlay.capsuleBelow ? Math.round(overlay.centre - width / 2) : rest
            y: overlay.capsuleBelow ? overlay.orbEnd + root.look.plate.gap : Math.round(overlay.orbCentre - height / 2)
            width: icons.width + 2 * pad.paddingX
            height: icons.height + 2 * pad.paddingY
            visible: icons.visible
            optIn: true
            fill: overlay.card.fill
            standard: ({ background: overlay.card.base, border: overlay.card.border, radius: root.look.plate.full })
            elevation: "none"
            lens: root.look.plate.lens
        }

        Column {
            id: icons
            x: iconPill.x + iconPill.pad.paddingX
            y: iconPill.y + iconPill.pad.paddingY
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

        // The card under the orb hugs the state line, the fault's lines
        // or the held request's column. A link's wrapped width is its
        // column's.
        GlassSurface {
            objectName: "textCard"
            readonly property Item column: root.hold !== null ? approvalText : stateBox
            readonly property real lines: root.hold !== null ? approvalText.width
                : Math.min(stateBox.width, Math.max(stateLine.contentWidth,
                    silenceLine.visible ? silenceLine.implicitWidth : 0, faultAction.visible ? faultAction.implicitWidth : 0))
            visible: column.visible
            x: Math.round(overlay.centre - width / 2)
            y: column.y - overlay.card.paddingY
            width: 2 * Math.ceil(lines / 2) + 2 * (root.hold !== null ? overlay.card.paddingX : overlay.stateInset)
            height: column.height + 2 * overlay.card.paddingY
            optIn: true
            fill: overlay.card.fill
            standard: ({ background: overlay.card.base, border: overlay.card.border, radius: overlay.card.radius })
            elevation: "none"
            lens: root.look.plate.lens
        }

        Column {
            id: stateBox
            x: overlay.centre - width / 2
            y: overlay.below
            width: Math.min(root.look.layout.line, Math.max(0, overlay.width - 2 * overlay.stateInset))
            visible: root.hold === null && (!root.hidden || root.fault !== null)
            spacing: root.look.layout.gap
            Label {
                id: stateLine
                width: parent.width
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
                readonly property var others: [question, fullPath, answerButtons].filter(item => item.visible && item.width > 0 && item.height > 0)
                readonly property real room: root.height - root.look.layout.margin - overlay.below - overlay.card.paddingY
                    - others.reduce((sum, item) => sum + item.height + approvalText.spacing, 0)
                width: parent.width
                height: Math.min(payload.implicitHeight, Math.max(root.look.layout.payload, Math.floor(room)))
                // The payload's own text, not its visible, which reads false
                // while this area hides it
                // (https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop).
                visible: payload.text !== ""
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
            Row {
                id: answerButtons
                width: parent.width
                topPadding: root.look.answer.gap
                spacing: root.look.answer.gap
                // keyboard-path: the effective Confirm and Stop shortcuts.
                Answer {
                    id: cancel
                    look: root.look
                    variant: "ghost"
                    quiet: true
                    width: (answerButtons.width - answerButtons.spacing) / 2
                    text: root.hold !== null && root.hold.purpose === "release" ? "No" : "Cancel"
                    onClicked: if (root.service !== null) root.service.cancelApproval(root.displayedHold)
                }
                Answer {
                    id: confirm
                    look: root.look
                    variant: "secondary"
                    // A request that needs a press is the destructive kind,
                    // whose confirming answer takes no tint.
                    quiet: root.hold !== null && root.hold.physical
                    width: (answerButtons.width - answerButtons.spacing) / 2
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
