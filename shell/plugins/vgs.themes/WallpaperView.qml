import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic

// The wallpaper view of the browser: the applied theme's wallpapers, or
// every package's and the user folder's, as angled cards on a rail, one
// dim hint line under it, naming what typing searches beside Show all or
// Show theme, and with two screens or more the scope words, All monitors and This
// monitor. At rest the view draws the cards, the tabs, that line and those
// words alone: the selection, which
// opens on the image the scope shows, marks it. Enter or a click on the selected
// image sets it for the scope: on every screen, each screen's own image
// cleared, or on the screen the browser shows on. The browser stays open
// while the set runs, closes once it lands, and shows a line naming the
// reason when it fails. Under Theme, a last card downloads the applied
// catalog theme's wallpapers when they are missing, or updates them when
// the catalog pins a newer archive; it shows the download's progress from
// `last.downloading`, applies the theme again so its image shows, reads
// the lists again and stays open.
//
// Keys, BrowserLogic.WALLPAPER_KEYS: Left and Up step back, Right and Down
// step forward, Home and End go to the first and the last card, and Enter
// sets the selected image or runs the selected card. Tab and Shift+Tab
// switch the top tabs. A printable character types into the filter, which
// shows under the rail, Backspace erases a character, Ctrl+Backspace a
// word and Ctrl+U the whole filter. Escape clears the filter, then asks to
// close. Alt+S or a click on Show all flips the source, and Alt+M or a
// click on a scope word flips the scope while the words show. An item of
// the view holds the keyboard and the rail never takes the focus, so Tab
// cannot leave the view before the view handles it.
//
// The view is built with each open and destroyed with the browser, so the
// scope starts on All monitors every time. It reads every image and the
// catalog on open, again after a download and whenever the applied theme
// changes. The selection starts on the image the chosen scope shows, and
// follows it until a key or a click moves it.
FocusScope {
    id: root

    property var shell: null
    readonly property Item initialFocus: keyboard

    // Asks the browser to close; the browser holds it while `busy`.
    signal closeRequested()
    signal switchRequested(int direction)

    // The last answers: every source's images and the catalog's entries,
    // each null before it arrives or after it failed, beside the reason it
    // failed or "".
    property var images: null
    property string imagesReason: ""
    property var entries: null
    property string catalogReason: ""
    // Whether the first image list and catalog have both answered.
    property bool loaded: images !== null
    property bool started: false

    property int sourceIndex: 0
    property int scopeIndex: 0
    readonly property string source: BrowserLogic.WALLPAPER_SOURCES[sourceIndex].source
    readonly property int screenCount: shell === null ? 0 : shell.screens.all.length
    readonly property bool scoped: BrowserLogic.scopeShown(screenCount)
    readonly property string scope: BrowserLogic.screenScope(scopeIndex, screenCount)
    // The output the browser shows on, "" before the shell arrives.
    readonly property string screenName: shell === null || shell.screens.current === null ? "" : shell.screens.current.name
    readonly property string applied: Theme.name
    // The last list's packages, which title the applied theme; null before it arrives.
    readonly property var packages: shell === null || shell.theme.listing === null ? null : shell.theme.listing.packages
    readonly property var cards: images === null ? [] : BrowserLogic.wallpaperCards(images, entries, applied, source)
    property string filterText: ""
    readonly property var shownCards: BrowserLogic.wallpaperShown(cards, filterText)
    readonly property var emptyState: BrowserLogic.wallpaperEmpty(loaded, source, applied, cards, filterText, packages)
    // The image the chosen scope shows now, "" for none.
    readonly property string shownPath: BrowserLogic.shownPath(scope, wallpaper.path, wallpaper.screenPaths, screenName)
    // The selected card's key once a key or a click moved it.
    property string selectedKey: ""
    property bool moved: false
    // True while the view itself moves the rail, so the move is no choice.
    property bool seeding: false
    readonly property var selected: carousel.currentIndex >= 0 && carousel.currentIndex < shownCards.length ? shownCards[carousel.currentIndex] : null

    // The step this view runs, { step, key, name } with `step` `set`,
    // `download`, `update` or `apply`, `key` the card it runs for and
    // `name` the image file or the package, or null.
    property var job: null
    readonly property bool busy: job !== null
    // The service advances only the changed package's image stamp. A
    // reopen uses the same URL and Qt's decoded pixmap cache.
    readonly property var generations: browserData.snapshot === null ? ({}) : browserData.snapshot.generations
    function imageGeneration(name) { return generations[name] || 0; }

    BrowserData {
        id: browserData
        shell: root.shell
        onSnapshotChanged: root.refresh()
    }
    // `last.downloading` as last read while a download this view started
    // runs, else null.
    property var downloading: null
    // What the last step that failed answered, "" when none did.
    property string problem: ""

    WallpaperState { id: wallpaper }

    // The view's keyboard: it holds the focus and runs the key table. A
    // FocusScope that takes the focus again hands it to the child that
    // last held it, a clicked segmented control included, so the view
    // takes the keyboard back through this item and not through itself.
    // The table runs on the focused item itself because Qt moves the focus
    // on a Tab that item leaves unaccepted before a parent's Keys see it.
    Item {
        id: keyboard
        focus: true
        Keys.onPressed: event => {
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const control = (event.modifiers & Qt.ControlModifier) !== 0;
            const alt = (event.modifiers & Qt.AltModifier) !== 0;
            const meta = (event.modifiers & Qt.MetaModifier) !== 0;
            const action = BrowserLogic.wallpaperAction(
                event.key,
                shift,
                control,
                alt,
                meta,
                root.scoped
            );
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
                carousel.currentIndex = Math.max(0, root.shownCards.length - 1);
                break;
            case "activate":
                root.activate();
                break;
            case "close":
                root.cancel();
                break;
            case "source":
                root.flipSource();
                break;
            case "scope":
                root.flipScope();
                break;
            case "tab-next":
                root.switchRequested(1);
                break;
            case "tab-previous":
                root.switchRequested(-1);
                break;
            case "":
                if (event.key === Qt.Key_Backspace && !alt && !meta) root.editFilter({ kind: control ? "eraseWord" : "erase" });
                else if (event.key === Qt.Key_U && control && !alt && !meta && !shift) root.editFilter({ kind: "clear" });
                else if (!control && !alt && !meta && BrowserLogic.typable(event.text)) root.editFilter({ kind: "type", text: event.text });
                else return;
                break;
            default:
                throw new Error("themes: wallpaper action=" + action);
            }
            event.accepted = true;
        }
    }

    // Read every image and the catalog; each answer is kept as it arrives.
    function refresh() {
        const data = browserData.snapshot;
        if (data === null) return;
        imagesReason = data.images.reason === null ? "" : data.images.reason;
        catalogReason = data.catalog.reason === null ? "" : data.catalog.reason;
        if (JSON.stringify(images) !== JSON.stringify(data.images.images)) images = data.images.images;
        if (JSON.stringify(entries) !== JSON.stringify(data.catalog.entries)) entries = data.catalog.entries;
    }

    // Select the card the user chose, or until one moved the rail, the
    // image the chosen scope shows; the first card when neither is shown.
    function reselect() {
        seeding = true;
        carousel.currentIndex = BrowserLogic.wallpaperSelection(shownCards, moved ? selectedKey : shownPath);
        seeding = false;
    }

    // shownCards follows cards, so its change alone reselects: a handler on
    // cards ran while the view was built, before shownCards held a list.
    onShownCardsChanged: reselect()
    onShownPathChanged: if (!moved) reselect()

    function flipSource() {
        sourceIndex = (sourceIndex + 1) % BrowserLogic.WALLPAPER_SOURCES.length;
    }

    // A new scope selects the image it shows.
    function chooseScope(index) {
        scopeIndex = index;
        moved = false;
        reselect();
    }

    function flipScope() {
        chooseScope((scopeIndex + 1) % BrowserLogic.SCREEN_SCOPES.length);
    }

    function takeKeys() { keyboard.forceActiveFocus(); }

    function cancel() {
        if (filterText !== "") filterText = "";
        else closeRequested();
    }

    function editFilter(edit) {
        filterText = BrowserLogic.editFilter(filterText, edit);
    }

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

    // End the running step with LINE, "" for none, and read the lists
    // again: a step that failed may still have changed what is on disk, so
    // the rail loads every image again too.
    function finish(line) {
        job = null;
        problem = line;
        browserData.refresh();
        refresh();
    }

    // Enter or a click on the selected card.
    function activate() {
        const card = selected;
        if (busy || card === null) return;
        problem = "";
        switch (card.kind) {
        case "image":
            setImage(card);
            break;
        case "download":
        case "update":
            download(card.kind);
            break;
        default:
            throw new Error("themes: wallpaper card kind=" + card.kind);
        }
    }

    function setImage(card) {
        job = { step: "set", key: card.key, name: card.background };
        const reply = shell.theme.set(card.path, BrowserLogic.setScreen(scope, screenName), result => {
            const line = BrowserLogic.problem("set", card.background, result, root.packages);
            root.job = null;
            if (line === "") root.closeRequested();
            else root.problem = line;
        });
        if (reply !== "ok") {
            job = null;
            problem = BrowserLogic.reasonText(reply);
        }
    }

    // Download or update, as KIND names, the applied theme's wallpapers,
    // then apply it again so its image shows.
    function download(kind) {
        const name = applied;
        job = { step: kind, key: kind, name: name };
        const reply = shell.theme.wallpapers(name, result => {
            root.downloading = null;
            const line = BrowserLogic.problem(kind, name, result, root.packages);
            if (line !== "") root.finish(line);
            else root.reapply(name, kind);
        }, kind === "update" ? { update: true } : undefined);
        if (reply !== "ok") {
            finish(BrowserLogic.reasonText(reply));
            return;
        }
        downloading = shell.theme.last.downloading;
    }

    // Apply NAME again after the download card KEY ran, the card's Spinner
    // turning until the lists are read again.
    function reapply(name, key) {
        job = { step: "apply", key: key, name: name };
        const reply = shell.theme.apply(name, result => {
            // The selection follows the image the apply shows.
            root.moved = false;
            root.finish(BrowserLogic.problem("apply", name, result, root.packages));
        });
        if (reply !== "ok") finish(BrowserLogic.reasonText(reply));
    }

    function start() {
        if (started || shell === null) return;
        started = true;
        browserData.read();
        refresh();
        takeKeys();
    }

    Component.onCompleted: start()
    onShellChanged: start()

    // An apply from elsewhere changes the applied theme's images.
    Connections {
        target: Theme
        function onDocumentRevisionChanged() {
            if (!root.busy) root.refresh();
        }
    }

    Timer {
        interval: BrowserLogic.PROGRESS_POLL_MS
        repeat: true
        running: root.job !== null && (root.job.step === "download" || root.job.step === "update")
        onTriggered: root.downloading = root.shell.theme.last.downloading
    }

    // One inset box centred on the output, as the theme view's: the tabs and
    // the scope words in the header, the rail in the body, and the typed
    // filter or its hint line and a download's progress in the footer.
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
                spacing: Theme.stack.group

                // The tabs sit on the scrim, as the rail's text does.
                Tabs {
                    anchors.horizontalCenter: parent.horizontalCenter
                    foreground: Theme.carousel.hint
                    hover: Theme.carousel.hintActive
                    active: Theme.carousel.hintActive
                    indicatorColor: Theme.carousel.tabIndicator
                    hoverMark: true
                    model: BrowserLogic.VIEWS.map(v => v.label)
                    currentIndex: 1
                    onActiveFocusChanged: if (activeFocus) Qt.callLater(root.takeKeys)
                    onCurrentIndexChanged: if (currentIndex !== 1) root.switchRequested(-1)
                }

                // The scope line: Apply to: and the scope words with a slash
                // between them, the chosen word brighter. The label and the
                // slash take no pointer and draw at `scopeLabelOpacity`, the
                // words at `scopeOpacity`. A MouseArea takes no focus, so the
                // view keeps the keyboard.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.scoped
                    spacing: Theme.stack.inline

                    Label {
                        role: "itemHint"
                        text: "Apply to:"
                        color: Theme.carousel.hint
                        opacity: Theme.carousel.scopeLabelOpacity
                    }

                    Repeater {
                        model: BrowserLogic.SCREEN_SCOPES

                        Row {
                            id: scopeEntry
                            required property var modelData
                            required property int index
                            spacing: Theme.stack.inline

                            Label {
                                visible: scopeEntry.index > 0
                                role: "itemHint"
                                text: "/"
                                color: Theme.carousel.hint
                                opacity: Theme.carousel.scopeLabelOpacity
                                Accessible.ignored: true
                            }

                            // keyboard-path: Alt+M flips the scope as a click does
                            MouseArea {
                                id: scopeWord
                                width: scopeText.implicitWidth
                                height: scopeText.implicitHeight
                                opacity: Theme.carousel.scopeOpacity
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: scopeEntry.modelData.label
                                Accessible.checked: scopeEntry.index === root.scopeIndex
                                hoverEnabled: true
                                onClicked: root.chooseScope(scopeEntry.index)
                                PointerCursor {}

                                // The chosen word also draws at bodyStrong's weight, and
                                // the other word under the pointer underlined: hintActive
                                // and hint are both near the same black or white.
                                Label {
                                    id: scopeText
                                    readonly property bool chosen: scopeEntry.index === root.scopeIndex
                                    readonly property int weight: chosen ? Theme.text.bodyStrong.weight : typography.weight
                                    role: "itemHint"
                                    text: scopeEntry.modelData.label
                                    color: chosen ? Theme.carousel.hintActive : Theme.carousel.hint
                                    font.weight: weight
                                    font.variableAxes: ({ wght: weight })
                                    font.underline: scopeWord.containsMouse && !chosen
                                }
                            }
                        }
                    }
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
                devicePixelRatio: root.shell === null || root.shell.screens.current === null ? Screen.devicePixelRatio : root.shell.screens.current.devicePixelRatio
                tabSteps: false
                model: ScriptModel {
                    values: root.shownCards.map(card => Object.assign({ railKey: BrowserLogic.railKey(card.key, root.imageGeneration(card.theme || "")), generation: root.imageGeneration(card.theme || "") }, card))
                    objectProp: "railKey"
                }
                delegate: WallpaperCard {
                    busy: root.job !== null && root.job.key === modelData.key
                }
                onCurrentIndexChanged: {
                    if (root.seeding || currentIndex < 0 || currentIndex >= root.shownCards.length) return;
                    root.moved = true;
                    root.selectedKey = root.shownCards[currentIndex].key;
                }
                onActivated: root.activate()
            }

            // No card to show: the lists loading, or no image under the
            // source, which the source line under the rail flips.
            BrowserEmptyState {
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.min(parent.width, Theme.carousel.expandedWidth)
                visible: root.shownCards.length === 0 && root.imagesReason === ""
                iconName: root.emptyState.iconName
                text: root.emptyState.text
                actionText: root.emptyState.actionText
                // Clear filter takes no focus, so the view keeps the keyboard.
                onActivated: root.editFilter({ kind: "clear" })
            }
        }

        footer: [
            Column {
                id: caption
                x: Math.round((layout.contentWidth - width) / 2)
                width: Math.min(layout.contentWidth, Theme.carousel.expandedWidth)
                spacing: Theme.stack.group

                // The search line, the hint while no filter is typed and the
                // typed filter in its place, sits on the scrim as the tabs
                // and the scope words do: the filter in `carousel.hintActive`
                // and the rest in `carousel.hint`. The line is as tall for
                // either, so typing moves nothing above it. The line and
                // each of its items start on a whole pixel, every width
                // whole: a text at a fractional x spreads each stem over
                // two columns, so Show all would read fainter for some typed
                // filters than others.
                BrowserSlot {
                    id: searchSlot
                    x: Math.round((parent.width - width) / 2)
                    width: searchLine.width
                    height: Math.max(searchText.height, typed.height, sourceLine.height)

                    // Each item of the line centres its own ink on the slot,
                    // never on the Row, whose height follows the taller typed
                    // filter: typing moves neither the divider nor Show all. A
                    // Row sets its children's x alone, so each sets its own y.
                    Row {
                        id: searchLine
                        spacing: Theme.stack.inline

                        Label {
                            id: typed
                            y: BrowserLogic.inkCentredTop(searchSlot.height, capTop(), lastBaseline())
                            visible: root.filterText !== ""
                            role: "h3"
                            width: Math.ceil(Math.min(implicitWidth, caption.width - searchDivider.width - sourceLine.width - 2 * searchLine.spacing))
                            elide: Text.ElideMiddle
                            color: Theme.carousel.hintActive
                            text: root.filterText
                        }
                        Label {
                            id: searchText
                            y: BrowserLogic.inkCentredTop(searchSlot.height, capTop(), lastBaseline())
                            width: Math.ceil(implicitWidth)
                            visible: root.filterText === ""
                            role: "itemHint"
                            text: "Type a wallpaper or image file name to search"
                            color: Theme.carousel.hint
                        }
                        // The divider belongs to the source line: it stays
                        // between the typed filter and Show all too.
                        Label {
                            id: searchDivider
                            y: BrowserLogic.inkCentredTop(searchSlot.height, capTop(), lastBaseline())
                            width: Math.ceil(implicitWidth)
                            role: "itemHint"
                            text: "|"
                            color: Theme.carousel.hint
                        }

                        // The source line names the source a click shows, its eye
                        // open while it offers every image and shut while it offers
                        // the theme's alone. A MouseArea takes no focus, so the view
                        // keeps the keyboard.
                        // keyboard-path: Alt+S flips the source as a click does
                        MouseArea {
                            id: sourceLine
                            y: BrowserLogic.inkCentredTop(searchSlot.height, sourceText.y + sourceText.capTop(), sourceText.y + sourceText.lastBaseline())
                            width: Math.ceil(sourceRow.implicitWidth)
                            height: sourceRow.implicitHeight
                            hoverEnabled: true
                            Accessible.role: Accessible.Button
                            Accessible.name: sourceText.text
                            onClicked: root.flipSource()
                            PointerCursor {}

                            Row {
                                id: sourceRow
                                spacing: Theme.stack.inline

                                Icon {
                                    y: Math.round(sourceText.y) + sourceText.topForLeadingIcon(height)
                                    name: BrowserLogic.WALLPAPER_SOURCES[root.sourceIndex].icon
                                    size: Theme.icon.size.sm
                                    color: sourceText.color
                                }
                                Label {
                                    id: sourceText
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "itemHint"
                                    text: BrowserLogic.WALLPAPER_SOURCES[root.sourceIndex].switchLabel
                                    color: sourceLine.containsMouse ? Theme.carousel.hintActive : Theme.carousel.hint
                                    font.underline: sourceLine.containsMouse
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.job !== null && (root.job.step === "download" || root.job.step === "update")

                    ProgressBar {
                        width: parent.width
                        indeterminate: BrowserLogic.progressValue(root.downloading) === null
                        value: BrowserLogic.progressValue(root.downloading) === null ? 0 : BrowserLogic.progressValue(root.downloading)
                    }
                    Label {
                        role: "hint"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: BrowserLogic.progressText(root.downloading)
                    }
                }
            }

        ]
    }

    // The failures lie under the pane, in the room it leaves on the output,
    // and outside its footer: a centred pane that grew with a failure would
    // move the rail and the caption under the pointer. On an output with no
    // room under the pane they lie over its foot.
    Column {
        id: failures
        x: (root.width - width) / 2
        y: Math.min(layout.y + layout.height - layout.contentInset + Theme.stack.group, root.height - height)
        width: caption.width
        spacing: Theme.stack.group

        Repeater {
            model: [
                root.problem,
                root.imagesReason === "" ? "" : "The image list is unavailable. " + BrowserLogic.reasonText(root.imagesReason),
                root.catalogReason === "" ? "" : "The catalog is unavailable. " + BrowserLogic.reasonText(root.catalogReason)
            ].filter(line => line !== "")
            // A failure reads by its mark, not by its colour, on a solid
            // plate of the theme's surface that no wallpaper reaches, so
            // `hintDanger` reads 4.5:1 over any wallpaper. The plate hugs
            // the line, never wider than the caption, and centres it by
            // its ink; under a rounded theme the line sits in from its
            // sides until it clears the drawn corner.
            Rectangle {
                id: plate
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                width: failure.width + 2 * plateInset.inset
                height: failure.height + 2 * Theme.surface.padding
                radius: Theme.surface.radius
                color: Theme.carousel.failurePlate

                Row {
                    id: failure
                    x: plateInset.inset
                    y: BrowserLogic.inkCentredTop(plate.height, failureText.capTop(), failureText.lastBaseline())
                    spacing: Theme.stack.inline

                    Icon {
                        id: failureMark
                        y: failureText.topForLeadingIcon(height)
                        name: "circle-alert"
                        size: Theme.icon.size.md
                        color: failureText.color
                    }
                    Label {
                        id: failureText
                        role: "body"
                        width: Math.min(implicitWidth, caption.width - 2 * plateInset.inset - failureMark.width - failure.spacing)
                        wrapMode: Text.Wrap
                        color: Theme.carousel.hintDanger
                        text: plate.modelData
                    }
                }

                // The caption's width bounds the plate's, and a wider
                // bound only rounds the corner more (Inset.clearing), so
                // the inset never falls short; the plate's own width
                // depends on the inset and would feed back.
                ClearingInset {
                    id: plateInset
                    pad: Theme.surface.padding
                    radius: plate.radius
                    width: caption.width
                    height: plate.height
                    top: Theme.surface.padding
                }
            }
        }
    }
}
