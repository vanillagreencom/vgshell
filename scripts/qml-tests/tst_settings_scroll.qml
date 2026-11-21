import QtQuick
import QtQuick.Window
import QtTest
import qs.Unit
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// A status-fed custom field loses its offers when its plugin stops. The
// page must leave the pressed switch in place when that exposes an editor.
Item {
    id: root
    width: 680
    height: 460
    property Item page: null
    property var fixtures: ({})
    Component {
        id: geometryObserver
        Connections {
            required property var watched
            required property var sample
            target: watched
            ignoreUnknownSignals: true
            function onPressed() { sample("pressed", watched); }
            function onReleased() { sample("released", watched); }
            function onClicked() { sample("clicked", watched); }
            function onCanceled() { sample("canceled", watched); }
            function onPressedChanged() { sample("pressedChanged", watched); }
            function onDownChanged() { sample("downChanged", watched); }
            function onActiveFocusChanged() { sample("activeFocusChanged", watched); }
            function onActiveFocusItemChanged() { sample("activeFocusItemChanged", watched); }
            function onFocusChanged() { sample("focusChanged", watched); }
            function onXChanged() { sample("xChanged", watched); }
            function onYChanged() { sample("yChanged", watched); }
            function onWidthChanged() { sample("widthChanged", watched); }
            function onHeightChanged() { sample("heightChanged", watched); }
            function onVisibleChanged() { sample("visibleChanged", watched); }
            function onContentYChanged() { sample("contentYChanged", watched); }
            function onContentHeightChanged() { sample("contentHeightChanged", watched); }
            function onCurrentIndexChanged() { sample("currentIndexChanged", watched); }
            function onCurrentPageChanged() { sample("currentPageChanged", watched); }
            function onCustomVisibleChanged() { sample("customVisibleChanged", watched); }
            function onAfterAnimating() { sample("afterAnimating", watched); }
            function onFrameSwapped() { sample("frameSwapped", watched); }
        }
    }
    QtObject {
        id: geometryProbe
        function identity(item) {
            if (item === null || item === undefined) return null;
            const out = { object: String(item) };
            for (const name of ["objectName", "key", "text", "label", "visible", "enabled", "opacity", "clip", "focus", "active", "activeFocus", "focusReason", "pressed", "down", "hovered", "containsMouse"])
                if (name in item && ["string", "number", "boolean"].includes(typeof item[name])) out[name] = item[name];
            return out;
        }

        function rectangle(item, boundary) {
            if (!item || typeof item.mapToItem !== "function") return null;
            const at = item.mapToItem(boundary, 0, 0);
            const end = item.mapToItem(boundary, item.width, item.height);
            return [at.x, at.y, end.x - at.x, end.y - at.y];
        }

        function describe(item, boundary) {
            const out = identity(item);
            if (out === null) return null;
            for (const name of ["x", "y", "width", "height", "implicitWidth", "implicitHeight", "contentY", "contentHeight", "currentIndex", "focusInset", "clipPadding", "fadeTopInset", "fadeExtent", "fadeAbove", "fadeBelow"])
                if (name in item) out[name] = item[name];
            out.mapped = rectangle(item, boundary);
            return out;
        }

        function ancestors(item, boundary) {
            const out = [];
            for (let at = item; at; at = at.parent) out.push(describe(at, boundary));
            return out;
        }

        // childAt is a visual lookup, not evidence of which item accepted input.
        // The signal emitter recorded beside it supplies the event recipient.
        function visualPath(item, point) {
            const out = [];
            for (let at = item; at;) {
                out.push(identity(at));
                const next = at.childAt(point.x, point.y);
                if (next === null) break;
                point = next.mapFromItem(at, point.x, point.y);
                at = next;
            }
            return out;
        }

        function descendants(item) {
            const out = [item];
            for (let i = 0; i < out.length; i++)
                for (const child of out[i].children || []) out.push(child);
            return out;
        }

        function install(testCase, component, owner, context) {
            function sample(stage, emitter) {
                const subject = context.subject();
                const native = context.nativeWindow;
                const nativeRoot = native === null ? null : native.contentItem;
                const nativePoint = subject && nativeRoot ? subject.mapToItem(nativeRoot, subject.width / 2, subject.height / 2) : null;
                const strip = context.tabs.tabs;
                const record = {
                    caseName: context.caseName, qt: context.qtVersion, stage: stage, timeMs: Date.now(),
                    emitter: identity(emitter), subject: describe(subject, context.boundary),
                    subjectObserved: unique.indexOf(subject) !== -1,
                    sceneRect: rectangle(subject, nativeRoot), clickPoint: nativePoint,
                    visualPath: nativePoint === null ? [] : visualPath(nativeRoot, nativePoint),
                    ancestors: ancestors(subject, context.boundary),
                    viewport: describe(context.viewport, context.boundary),
                    contentItem: describe(context.viewport.contentItem, context.boundary),
                    tabs: describe(context.tabs, context.boundary),
                    tabPage: describe(context.tabs.currentPage, context.boundary),
                    strip: describe(strip, context.boundary),
                    stripTargetY: context.viewport.contentY + context.viewport.focusInset + context.pane.ringRoom - context.tabs.y,
                    nativeWindow: identity(native), nativeSize: native === null ? null : [native.width, native.height],
                    nativeActiveFocusItem: describe(native === null ? null : native.activeFocusItem, context.boundary),
                    polishScheduled: native === null ? null : testCase.isPolishScheduled(native),
                    slide: context.surface === null ? null : {
                        actualX: context.page.parent.x,
                        targetX: context.surface.page === "" ? 0 : -context.surface.width,
                        surfaceWidth: context.surface.width, page: context.surface.page, tab: context.page.tab
                    },
                    extra: context.extra()
                };
                console.info("vgs2681-geometry " + JSON.stringify(record));
            }
            const watched = [context.nativeWindow, context.viewport, context.tabs, context.tabs.tabs];
            for (let at = context.subject(); at; at = at.parent) watched.push(at);
            for (const item of descendants(owner))
                if (("down" in item && "pressed" in item) || "containsMouse" in item || "customVisible" in item)
                    watched.push(item);
            const unique = watched.filter((item, index) => item !== null && watched.indexOf(item) === index);
            const observers = [];
            for (const item of unique) {
                const observer = testCase.createTemporaryObject(component, owner, { watched: item, sample: sample });
                testCase.verify(observer !== null, "the passive geometry observer is created");
                observers.push(observer);
            }
            console.info("vgs2681-observers " + JSON.stringify({ caseName: context.caseName, targets: unique.map(identity) }));
            return {
                snapshot: stage => sample(stage, null),
                stop: () => {
                    for (const observer of observers) {
                        observer.enabled = false;
                        observer.target = null;
                    }
                }
            };
        }
    }

    function row(enabled, listCase) {
        // Registry.managerRows retains m.schema/m.fieldRows while replacing
        // state rows. Match that producer so a toggle is no manifest reload.
        const fixtureKey = listCase ? "list" : "flat";
        if (fixtures[fixtureKey] !== undefined)
            return Object.assign({}, fixtures[fixtureKey], { enabled: enabled, settingChoices: { home: enabled ? [{ label: "None", value: "none" }] : [] } });
        const schema = {};
        const settings = {};
        for (let i = 0; i < 15; i++) {
            schema["toggle" + i] = { type: "boolean", label: "Option " + i, group: "Options" };
            settings["toggle" + i] = true;
        }
        if (listCase) {
            schema.pads = { type: "list", label: "Pads", items: { command: { type: "string", label: "App", presets: [{ label: "Terminal", value: "terminal" }], allowCustom: true } }, defaults: { command: "terminal" } };
            settings.pads = [{ name: "1", command: "fixture-command-never-run" }];
        } else {
            schema.home = { type: "string", label: "Home folder", group: "Home", optionsFrom: "homes", allowCustom: true };
            settings.home = "none";
        }
        const result = {
            id: "acme.scroll", name: "Scroll", version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: enabled, alwaysOn: false, placed: true, kinds: ["service", "bar-widget"], capabilities: [],
            schema: schema, settings: settings, settingChoices: { home: enabled ? [{ label: "None", value: "none" }] : [] },
            fieldRows: PluginLogic.fieldRows(schema, {}), withheldFields: [], fieldProblems: {}, status: [], secretLabel: "", guide: null,
            tuis: [], builtins: [], opens: "", paneHolder: "", binds: [], requirements: [], errors: []
        };
        fixtures[fixtureKey] = result;
        return result;
    }

    Item {
        id: manager
        property var shell: null
        property var plugins: []
        property var installFailures: ({})
        property bool listCase: false
        property var current: root.row(true)
        function setEnabled(id, enabled) { current = root.row(enabled, listCase); return "ok"; }
        function replyOf() { return ""; }
        function headReplies() { return []; }
    }
    Component {
        id: pageComponent
        PluginPage {
            width: root.width
            height: root.height
            maximumHeight: root.height
            panel: manager
            row: manager.current
        }
    }

    function descendants(item) {
        let out = [];
        for (const child of item.children) out = out.concat([child], descendants(child));
        return out;
    }
    UnitCase {
        id: geometryCase
        name: "SettingsScroll"
        when: windowShown
        function enabledSwitch() {
            const field = descendants(page).find(item => item instanceof Field && semanticLabelItems(item).some(label => displayedText(label) === SettingValues.PAGE_LABELS.enabled));
            return descendants(field).find(item => item instanceof Switch);
        }

        function init() {
            manager.current = root.row(true);
            manager.listCase = false;
            root.page = createTemporaryObject(pageComponent, root);
            verify(root.page !== null);
            verify(renderedFrame(root.page));
            root.page.scrollArea.contentY = 0;
        }

        function test_toggle_keeps_the_page_at_the_pressed_row_data() {
            return [
                { tag: "runtime choices off", list: false, wanted: false },
                { tag: "runtime choices on", list: false, wanted: true },
                { tag: "custom list off", list: true, wanted: false },
                { tag: "custom list on", list: true, wanted: true }
            ];
        }

        function test_toggle_keeps_the_page_at_the_pressed_row(data) {
            manager.listCase = data.list;
            manager.current = root.row(!data.wanted, data.list);
            verify(renderedFrame(page));
            page.scrollArea.contentY = 0;
            const before = page.scrollArea.contentY;
            mouseClick(enabledSwitch());
            tryCompare(manager.current, "enabled", data.wanted);
            verify(waitForPolish(page.Window.window));
            wait(0);
            verify(renderedFrame(page));
            compare(page.scrollArea.contentY, before);
        }

        function test_choosing_custom_still_reveals_the_editor() {
            const home = descendants(page).find(item => item instanceof SettingField && item.key === "home");
            const select = descendants(home).find(item => item instanceof Select);
            const probe = geometryProbe.install(geometryCase, geometryObserver, root, {
                caseName: "custom-editor", qtVersion: UnitQt.VERSION,
                subject: () => descendants(home).find(item => item instanceof TextInput && item.visible) || select,
                boundary: root, page: page, viewport: page.scrollArea,
                tabs: descendants(page).find(item => item instanceof TabPages),
                pane: descendants(page).find(item => item instanceof Pane),
                nativeWindow: root.Window.window, surface: null,
                extra: () => ({ customVisible: home.customVisible, field: geometryProbe.describe(home, root) })
            });
            try {
                probe.snapshot("before-choose");
                select.choose(home.choices.length);
                probe.snapshot("after-choose");
                tryVerify(() => home.customVisible && page.scrollArea.contentY > 0);
                const input = descendants(home).find(item => item instanceof TextInput && item.visible);
                verify(input !== undefined);
                probe.snapshot("before-viewport-assertion");
                verify(input.mapToItem(page.scrollArea, 0, input.height).y <= page.scrollArea.height);
            } finally {
                probe.stop();
            }
        }

        function test_keyboard_focus_still_reveals_the_control() {
            const home = descendants(page).find(item => item instanceof SettingField && item.key === "home");
            const select = descendants(home).find(item => item instanceof Select);
            select.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => select.activeFocus && page.scrollArea.contentY > 0);
            verify(select.mapToItem(page.scrollArea, 0, select.height).y <= page.scrollArea.height);
        }
    }
}
