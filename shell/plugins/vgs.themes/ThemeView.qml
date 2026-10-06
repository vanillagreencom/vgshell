import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic

// The theme view of the browser: every shipped, installed and catalog
// theme as an angled card on one rail, a typed filter, and Enter or a
// click on the selected card installing a catalog theme if it needs it and
// applying it. At rest the view draws the cards, the tabs and the
// selected theme's name under the rail: the selection, which opens on the
// applied theme, marks it, and a busy card turns its own Spinner while its
// install or apply runs. After an apply of a theme whose wallpapers are
// not downloaded, a Dialog offers the download; Download runs it on the
// download lane, shows its progress from `last.downloading` and applies the
// theme again, so its first wallpaper shows. A step that fails leaves the
// view open with a line naming it and the reason; a step that succeeds and
// offers nothing asks the browser to close.
//
// Keys: Left, Right, Home, End and the wheel move through the rail, and Up
// and Down step as Left and Right do. Tab and Shift+Tab switch the top
// tabs. A printable character types into the filter, Backspace erases a character, Ctrl+Backspace a word and Ctrl+U
// the whole filter. Escape clears the filter, then asks to close. Enter
// applies the selected card.
//
// The view is built with the overlay. It draws retained service data
// without starting a catalog, list or image read on open.
FocusScope {
    id: root

    property var shell: null
    readonly property Item initialFocus: carousel

    // Asks the browser to close; the browser holds it while `busy`.
    signal closeRequested()
    signal switchRequested(int direction)

    // The last answers: the list's packages, the catalog's entries and
    // every package's images, each null before it arrives or after it
    // failed, beside the reason it failed or "".
    property var packages: null
    property string listReason: ""
    property var entries: null
    property string catalogReason: ""
    property var images: null
    property string imagesReason: ""
    // Whether the first list, catalog and image list have all answered.
    property bool loaded: packages !== null
    property bool started: false

    property var cards: []
    property string filterText: ""
    readonly property var shownCards: BrowserLogic.shown(cards, filterText)
    // The selected theme's name, kept across a filter and a refresh; the
    // displayed theme's until the first card is chosen.
    property string selectedName: ""
    readonly property var selected: carousel.currentIndex >= 0 && carousel.currentIndex < shownCards.length ? shownCards[carousel.currentIndex] : null

    // The step this view runs, { step, name } with `step` `install`,
    // `apply` or `download`, or null.
    property var job: null
    // Only a successful catalog install lends its imagery to an installed
    // card before the catalog's installed flag has caught up.
    property var installedImagery: ({})
    // An apply result can arrive before Theme publishes the applied package.
    // Keep that result here until the theme name confirms the same package.
    property var pendingApply: null
    readonly property bool busy: job !== null
    // The card whose wallpapers the Dialog offers, or null.
    property var offer: null
    // `last.downloading` as last read while a download this view started
    // runs, else null.
    property var downloading: null
    // The browser's previews, assigned before the shell starts the view.
    property ThemePreviews previews: null
    // What the last step that failed answered, "" when none did.
    property string problem: ""
    // The service advances only the changed package's image stamp. A
    // reopen uses the same URL and Qt's decoded pixmap cache.
    readonly property var generations: browserData.snapshot === null ? ({}) : browserData.snapshot.generations
    function imageGeneration(name) { return generations[name] || 0; }

    BrowserData {
        id: browserData
        shell: root.shell
        onSnapshotChanged: root.refresh()
    }

    // Draw the shell-known packages and the service's retained answer.
    function refresh(then) {
        if (shell === null) return;
        const data = browserData.snapshot;
        const known = shell.theme.listing;
        packages = known === null ? null : known.packages;
        if (data !== null) {
            listReason = data.listReason;
            catalogReason = data.catalog.reason === null ? "" : data.catalog.reason;
            imagesReason = data.images.reason === null ? "" : data.images.reason;
            entries = data.catalog.entries;
            images = data.images.images;
        }
        if (selectedName === "") selectedName = Theme.name;
        const next = data !== null ? data.cards : packages === null ? [] : BrowserLogic.cards(packages, null, null, Theme.name);
        if (JSON.stringify(next) !== JSON.stringify(cards)) cards = next;
        if (then !== undefined) then();
    }

    // Keep the selection on its theme when the shown cards change, else on
    // the first card.
    onShownCardsChanged: {
        const index = BrowserLogic.selection(shownCards, selectedName);
        carousel.currentIndex = index;
        if (index < shownCards.length) selectedName = shownCards[index].name;
    }

    function focusRail() { carousel.forceActiveFocus(); }

    function navigate(direction) {
        switch (direction) {
        case "left":
        case "up":
            carousel.step(-1);
            break;
        case "right":
        case "down":
            carousel.step(1);
            break;
        default:
            throw new Error("themes: direction=" + direction);
        }
    }

    // End the running step with LINE, "" for none. A step that failed may
    // still have changed what is on disk, an install before the apply after
    // it failed, so the cards are read again and Enter retries the step
    // that failed, not one that landed.
    function finish(line) {
        job = null;
        problem = line;
        if (line !== "") refresh();
    }

    // Enter or a click on the selected card.
    function activate() {
        const card = selected;
        if (busy || offer !== null || card === null) return;
        problem = "";
        if (card.state !== "ok") {
            problem = card.label + " is unavailable. " + BrowserLogic.reasonText(card.reason);
            return;
        }

        if (card.installed) apply(card.name);
        else install(card.name);
    }

    // A card with a catalog wallpaper pin and no image on disk wants the
    // pin's first wallpaper fetched, started once the rail rests on it.
    function requestPreview(card) {
        if (previews.want(card === null || card.previewImage !== null || card.image !== null || card.imagery === null ? "" : card.name))
            previewTimer.restart();
    }

    function install(name) {
        const card = cards.find(c => c.name === name);
        job = { step: "install", name: name };
        const reply = shell.theme.install(name, result => {
            const line = BrowserLogic.problem("install", name, result);
            if (line !== "") root.finish(line);
            else {
                const next = Object.assign({}, root.installedImagery);
                next[name] = card === undefined ? null : card.imagery;
                root.installedImagery = next;
                browserData.refresh(); root.apply(name);
            }
        });
        if (reply !== "ok") finish(BrowserLogic.reasonText(reply));
    }

    // Apply NAME; once the refreshed cards hold its catalog state, offer its
    // wallpapers or ask to close.
    function apply(name, downloaded = false) {
        job = { step: "apply", name: name };
        const reply = shell.theme.apply(name, result => {
            const line = BrowserLogic.problem("apply", name, result);
            if (!BrowserLogic.applied(result)) {
                root.finish(line);
                return;
            }
            root.completeApply(name, line, downloaded);
        });
        if (reply !== "ok") finish(BrowserLogic.reasonText(reply));
    }

    function completeApply(name, line, downloaded = false) {
        if (Theme.name !== name) {
            pendingApply = { name: name, line: line, downloaded: downloaded };
            return;
        }
        pendingApply = null;
        root.refresh(() => {
            const found = root.cards.find(c => c.name === name) || null;
            const card = found === null ? null : Object.assign({}, found, { installed: true, displayed: true,
                imagery: found.imagery === null ? root.installedImagery[name] || null : found.imagery });
            root.finish(line);
            if (!downloaded && BrowserLogic.downloadOffer(card)) root.offer = card;
            else if (line === "") root.closeRequested();
        });
    }

    function download() {
        const name = offer.name;
        job = { step: "download", name: name };
        const reply = shell.theme.wallpapers(name, result => {
            root.offer = null;
            root.downloading = null;
            root.focusRail();
            const line = BrowserLogic.problem("download", name, result);
            if (line !== "") root.finish(line);
            else root.apply(name, true);
        });
        if (reply !== "ok") {
            offer = null;
            finish(BrowserLogic.reasonText(reply));
            focusRail();
            return;
        }
        downloading = shell.theme.last.downloading;
    }

    function declineOffer() {
        offer = null;
        focusRail();
    }

    // Escape: the filter first, then the browser.
    function cancel() {
        if (filterText !== "") filterText = "";
        else closeRequested();
    }

    function editFilter(edit) {
        filterText = BrowserLogic.editFilter(filterText, edit);
    }

    function start() {
        if (started || shell === null) return;
        started = true;
        browserData.read();
        refresh();
        focusRail();
    }

    Component.onCompleted: start()
    // A preview that finishes after the view is gone starts no other: the
    // card wanted is one a shown theme view rests on.
    Component.onDestruction: previews.want("")
    onShellChanged: start()
    // The selection moves while the view builds, before the browser hands
    // it the previews and the shell that starts it.
    onSelectedChanged: if (started) requestPreview(selected)

    // An apply from elsewhere changes the cards' applied and installed state.
    Connections {
        target: Theme
        function onRevisionChanged() {
            if (root.pendingApply !== null) root.completeApply(root.pendingApply.name, root.pendingApply.line, root.pendingApply.downloaded);
            else if (!root.busy) root.refresh();
        }
    }

    Timer {
        interval: BrowserLogic.PROGRESS_POLL_MS
        repeat: true
        running: root.job !== null && root.job.step === "download"
        onTriggered: root.downloading = root.shell.theme.last.downloading
    }

    Timer {
        id: previewTimer
        interval: Theme.carousel.previewDwell
        onTriggered: root.previews.start()
    }

    function handleKey(event) {
        // The Dialog holds the keys while it shows; what it passes on edits
        // nothing under it.
        if (offer !== null) {
            event.accepted = true;
            return;
        }
        const control = (event.modifiers & Qt.ControlModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const meta = (event.modifiers & Qt.MetaModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const action = BrowserLogic.themeAction(event.key, shift, control, alt, meta);
        switch (action) {
        case "back":
            carousel.step(-1);
            break;
        case "forward":
            carousel.step(1);
            break;
        case "first":
            carousel.currentIndex = 0;
            break;
        case "last":
            carousel.currentIndex = root.shownCards.length - 1;
            break;
        case "activate":
            activate();
            break;
        case "close":
            cancel();
            break;
        case "tab-next":
            switchRequested(1);
            break;
        case "tab-previous":
            switchRequested(-1);
            break;
        case "":
            if (event.key === Qt.Key_Backspace && !alt && !meta) editFilter({ kind: control ? "eraseWord" : "erase" });
            else if (event.key === Qt.Key_U && control && !alt && !meta && !shift) editFilter({ kind: "clear" });
            else if (!control && !alt && !meta && BrowserLogic.typable(event.text)) editFilter({ kind: "type", text: event.text });
            else return;
            break;
        default:
            throw new Error("themes: theme action=" + action);
        }
        event.accepted = true;
    }

    // Keys the carousel passes on.
    Keys.onPressed: event => root.handleKey(event)

    // One inset box centred on the output: the tabs in the header, the rail
    // in the body, and the typed filter and the failures in the footer.
    Pane {
        id: layout
        anchors.centerIn: parent
        width: parent.width
        container: "overlay"
        fitToContent: true
        maximumHeight: parent.height

        header: [
            Column {
                width: layout.contentWidth

                Tabs {
                    anchors.horizontalCenter: parent.horizontalCenter
                    model: BrowserLogic.VIEWS.map(v => v.label)
                    currentIndex: 0
                    onActiveFocusChanged: if (activeFocus) Qt.callLater(root.focusRail)
                    onCurrentIndexChanged: if (currentIndex !== 0) root.switchRequested(1)
                }
            }
        ]

        // The rail takes the height its width asks for, or the room the
        // pane leaves its body on the output.
        Item {
            width: layout.contentWidth
            height: Math.min(carousel.implicitHeight, layout.bodyRoom)

            CardCarousel {
                id: carousel
                anchors.fill: parent
                focus: true
                devicePixelRatio: root.shell === null || root.shell.screens.current === null ? Screen.devicePixelRatio : root.shell.screens.current.devicePixelRatio
                tabSteps: false
                spaceActivates: false
                onTabStepped: delta => root.switchRequested(delta)
                Keys.forwardTo: [root]
                Keys.onTabPressed: event => { root.switchRequested(1); event.accepted = true; }
                Keys.onBacktabPressed: event => { root.switchRequested(-1); event.accepted = true; }
                model: ScriptModel {
                    values: root.shownCards.map(card => {
                        const sharpened = root.previews.cache[card.name] === undefined ? card : Object.assign({}, card, { sharpenedImage: root.previews.cache[card.name] });
                        return Object.assign({ key: BrowserLogic.railKey(card.contentKey || BrowserLogic.cardKey(sharpened), root.imageGeneration(card.name)), generation: root.imageGeneration(card.name) }, sharpened);
                    })
                    objectProp: "key"
                }
                delegate: ThemeCard {
                    busy: root.job !== null && root.job.name === modelData.name
                }
                onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < root.shownCards.length) {
                    root.selectedName = root.shownCards[currentIndex].name;
                    root.requestPreview(root.shownCards[currentIndex]);
                }
                onActivated: root.activate()
            }

            // No card to show: the list loading, no theme at all, or a
            // filter no card matches, which Clear filter, as Escape, undoes.
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.carousel.expandedWidth)
                visible: root.shownCards.length === 0 && root.listReason === ""
                iconName: !root.loaded ? "" : root.filterText === "" ? "palette" : "search-x"
                text: !root.loaded ? "" : root.filterText === "" ? "No theme is installed" : "No theme matches " + JSON.stringify(root.filterText)
                actionText: root.loaded && root.filterText !== "" ? "Clear filter" : ""
                onActivated: {
                    root.editFilter({ kind: "clear" });
                    Qt.callLater(root.focusRail);
                }
            }
        }

        footer: [
            Column {
                id: caption
                x: (layout.contentWidth - width) / 2
                width: Math.min(layout.contentWidth, Theme.carousel.expandedWidth)
                spacing: Theme.stack.group

                Label {
                    role: "display"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: root.selected !== null
                    text: root.selected === null ? "" : root.selected.label
                }

                Label {
                    role: "h3"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    visible: root.filterText !== ""
                    text: root.filterText
                }

                Repeater {
                    model: [
                        root.problem,
                        root.listReason === "" ? "" : "The theme list is unavailable. " + BrowserLogic.reasonText(root.listReason),
                        root.catalogReason === "" ? "" : "The catalog is unavailable. " + BrowserLogic.reasonText(root.catalogReason),
                        root.imagesReason === "" ? "" : "The image list is unavailable. " + BrowserLogic.reasonText(root.imagesReason)
                    ].filter(line => line !== "")
                    Label {
                        required property string modelData
                        role: "body"
                        width: caption.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Theme.color.danger
                        text: modelData
                    }
                }
            }

        ]
    }

    Scrim {
        visible: root.offer !== null
        onClicked: if (!root.busy) root.declineOffer()
    }

    Dialog {
        id: prompt
        anchors.centerIn: parent
        visible: root.offer !== null
        busy: root.job !== null && root.job.step === "download"
        title: root.offer === null ? "" : "Download wallpapers for " + root.offer.label + " (" + BrowserLogic.sizeText(root.offer.imagery.size) + ")?"
        message: root.offer === null ? "" : root.offer.label + " is applied without its wallpapers."
        actions: [
            { label: "Download", role: "accept" },
            { label: "Not now", role: "cancel" }
        ]
        onVisibleChanged: if (visible) forceActiveFocus()
        onAccepted: root.download()
        onRejected: root.declineOffer()

        ProgressBar {
            width: parent.width
            visible: prompt.busy
            indeterminate: BrowserLogic.progressValue(root.downloading) === null
            value: BrowserLogic.progressValue(root.downloading) === null ? 0 : BrowserLogic.progressValue(root.downloading)
        }
        Label {
            role: "hint"
            width: parent.width
            visible: prompt.busy
            text: BrowserLogic.progressText(root.downloading)
        }
    }
}
