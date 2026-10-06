import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic

// The wallpaper view of the browser: the applied theme's wallpapers, or
// every package's and the user folder's, as angled cards on a rail, one
// dim source line under it, Show all or Show theme, and with two screens
// or more a scope control, All monitors or This monitor. At rest the view
// draws the cards, the tabs and those controls alone: the selection, which
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
// step forward, Home and End go to the first and the last card, Enter sets
// the selected image or runs the selected card, and Escape asks to close.
// Tab and Shift+Tab switch the top tabs. Alt+S or a click on the source
// line flips the source, and Alt+M flips the scope while its control
// shows. An item of the view holds the
// keyboard and the rail never takes the focus, so Tab cannot leave the
// view before the view handles it.
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
    readonly property var cards: images === null ? [] : BrowserLogic.wallpaperCards(images, entries, applied, source)
    // The image the chosen scope shows now, "" for none.
    readonly property string shownPath: BrowserLogic.shownPath(scope, wallpaper.path, wallpaper.screenPaths, screenName)
    // The selected card's key once a key or a click moved it.
    property string selectedKey: ""
    property bool moved: false
    // True while the view itself moves the rail, so the move is no choice.
    property bool seeding: false
    readonly property var selected: carousel.currentIndex >= 0 && carousel.currentIndex < cards.length ? cards[carousel.currentIndex] : null

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
    // on a Tab that item leaves unaccepted before a parent's Keys see it
    // (runtime-qml.md).
    Item {
        id: keyboard
        focus: true
        Keys.onPressed: event => {
            const action = BrowserLogic.wallpaperAction(
                event.key,
                (event.modifiers & Qt.ShiftModifier) !== 0,
                (event.modifiers & Qt.ControlModifier) !== 0,
                (event.modifiers & Qt.AltModifier) !== 0,
                (event.modifiers & Qt.MetaModifier) !== 0,
                root.scoped
            );
            switch (action) {
            case "":
                return;
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
                carousel.currentIndex = Math.max(0, root.cards.length - 1);
                break;
            case "activate":
                root.activate();
                break;
            case "close":
                root.closeRequested();
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
        carousel.currentIndex = BrowserLogic.wallpaperSelection(cards, moved ? selectedKey : shownPath);
        seeding = false;
    }

    onCardsChanged: reselect()
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
            const line = BrowserLogic.problem("set", card.background, result);
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
            const line = BrowserLogic.problem(kind, name, result);
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
            root.finish(BrowserLogic.problem("apply", name, result));
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
        function onRevisionChanged() {
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
    // the scope in the header, the rail in the body, and the source line, a
    // download's progress and the failures in the footer.
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

                Tabs {
                    anchors.horizontalCenter: parent.horizontalCenter
                    model: BrowserLogic.VIEWS.map(v => v.label)
                    currentIndex: 1
                    onActiveFocusChanged: if (activeFocus) Qt.callLater(root.takeKeys)
                    onCurrentIndexChanged: if (currentIndex !== 1) root.switchRequested(-1)
                }

                // A segment click focuses the control, and a click on the chosen
                // segment emits no `activated`, so the control hands the keyboard
                // back to the view whenever it takes it, after the click ends.
                SegmentedControl {
                    id: scopeControl
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.scoped
                    model: BrowserLogic.SCREEN_SCOPES.map(s => s.label)
                    currentIndex: root.scopeIndex
                    onActiveFocusChanged: if (activeFocus) Qt.callLater(root.takeKeys)
                    onActivated: index => {
                        root.chooseScope(index);
                        currentIndex = Qt.binding(() => root.scopeIndex);
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
                    values: root.cards.map(card => Object.assign({ railKey: BrowserLogic.railKey(card.key, root.imageGeneration(card.theme || "")), generation: root.imageGeneration(card.theme || "") }, card))
                    objectProp: "railKey"
                }
                delegate: WallpaperCard {
                    busy: root.job !== null && root.job.key === modelData.key
                }
                onCurrentIndexChanged: {
                    if (root.seeding || currentIndex >= root.cards.length) return;
                    root.moved = true;
                    root.selectedKey = root.cards[currentIndex].key;
                }
                onActivated: root.activate()
            }

            // No card to show: the lists loading, or no image under the
            // source, which the source line under the rail flips.
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.carousel.expandedWidth)
                visible: root.cards.length === 0 && root.imagesReason === ""
                iconName: root.loaded ? "image-off" : ""
                text: BrowserLogic.wallpaperEmpty(root.loaded, root.source, root.applied)
            }
        }

        footer: [
            Column {
                id: caption
                x: (layout.contentWidth - width) / 2
                width: Math.min(layout.contentWidth, Theme.carousel.expandedWidth)
                spacing: Theme.stack.group

                // The source line names the source a click shows, its eye
                // open while it offers every image and shut while it offers
                // the theme's alone. A MouseArea takes no focus, so the view
                // keeps the keyboard.
                // keyboard-path: Alt+S flips the source as a click does
                MouseArea {
                    id: sourceLine
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: sourceRow.implicitWidth
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
                            anchors.verticalCenter: parent.verticalCenter
                            name: BrowserLogic.WALLPAPER_SOURCES[root.sourceIndex].icon
                            size: Theme.icon.size.sm
                            color: sourceText.color
                        }
                        Label {
                            id: sourceText
                            anchors.verticalCenter: parent.verticalCenter
                            role: "itemHint"
                            text: BrowserLogic.WALLPAPER_SOURCES[root.sourceIndex].switchLabel
                            color: sourceLine.containsMouse ? Theme.color.textMuted : Theme.color.textFaint
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

                Repeater {
                    model: [
                        root.problem,
                        root.imagesReason === "" ? "" : "The image list is unavailable. " + BrowserLogic.reasonText(root.imagesReason),
                        root.catalogReason === "" ? "" : "The catalog is unavailable. " + BrowserLogic.reasonText(root.catalogReason)
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
}
