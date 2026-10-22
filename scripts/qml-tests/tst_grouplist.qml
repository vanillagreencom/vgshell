import QtQuick
import QtQuick.Templates as T
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// GroupList: the groups it holds sit `groupList.gap` apart with one
// hairline in `groupList.divider` in each gap, centred within a pixel
// between the drawn pixels of the two groups, read from the rendered
// image: a hint's leading, a chip or a label centred in a taller row and a
// button that fills its row move it no closer to either group, and the ink
// it reads of a line, a link drawn as the value or a text value, is that
// line's first drawn row, and a wrapped label's last line without a
// descender ends its ink at the glyphs, not the font's descent. A hidden
// group takes neither, a group list inside another divides its own groups
// alike, and a theme moves both. A heading over a group list of files,
// as a Google Drive folder pair, stands as far in drawn rows from the file
// above it as one file from the next. The groups are the Settings page's own Status lines
// and Requirements rows, so the page's rhythm is read where it is drawn:
// a line's own lines, its value and its hint sit `field.gap` apart, less
// than the gap between groups. A state too long for the value column
// elides inside its chip, and its sentence wraps under it, both inside
// the line. A line that is a secret's presence draws Replace and Remove,
// in the danger tone, after its chip, or Add key on the value column while
// nothing is stored, and Replace or Add key opens the masked field, whose
// Save hands on what was typed. A step declared danger draws in that tone.
// A line with no value draws its hint in the value column with its
// `hintLink` words as a link, which emits `hintLinkActivated`.
Item {
    id: root
    width: 880
    height: 2500

    GroupList {
        id: list
        width: 400
        StatusLine { id: warden; width: list.width; label: "Warden"; tone: "success"; text: "Checking"; hint: "Keeps AI agents within their memory and task limits" }
        StatusLine { id: agents; width: list.width; label: "Agents running"; text: "3" }
        StatusLine { id: hidden; width: list.width; label: "Hidden"; text: "gone"; visible: false }
        RequirementRow { id: vsys; width: list.width; requirement: ({ name: "vsys", title: "vsys", bus: null, state: "present", badge: { text: "Present", tone: "success" }, optional: false, purpose: "The agent dashboard that ships the warden" }) }
    }

    GroupList {
        id: outer
        y: 520
        width: 400
        StatusLine { id: single; width: outer.width; label: "Scheduler"; text: "systemd" }
        GroupList {
            id: inner
            width: outer.width
            StatusLine { id: tokens; width: inner.width; label: "Slack tokens"; hint: "One token per workspace" }
            StatusLine { id: acme; width: inner.width; label: "Acme"; tone: "success"; text: "Present" }
        }
    }

    // The groups of a Setup tab on a solid surface, so the image shows
    // where each group's pixels start and end: Requirements rows whose
    // hints end with and without a descender, the Install row's filled
    // button, a step with a text value, one whose action stands alone, a
    // step whose chip centres in a row as tall as a key/value row, as the
    // Setup tab's steps do, a label alone, and status lines whose value is
    // a hint or a chip with its step.
    Rectangle {
        id: inkFrame
        y: 1860
        width: 400
        height: inkList.height
        color: Theme.color.surface
        GroupList {
            id: inkList
            width: inkFrame.width
            RequirementRow { width: inkList.width; requirement: ({ name: "sh", title: "sh", bus: null, state: "present", badge: { text: "Present", tone: "success" }, optional: false, purpose: "A command every sandbox has" }) }
            RequirementRow { width: inkList.width; requirement: ({ name: "absent", title: "absent", bus: null, state: "missing", badge: { text: "Optional", tone: "info" }, optional: true, purpose: "A command no sandbox has" }) }
            Field {
                width: inkList.width
                label: "Missing"
                inline: true
                hint: "Review the missing tools before you install them"
                Button { text: "Install all missing"; iconName: "download"; variant: "primary" }
            }
            Field { width: inkList.width; label: "Mode"; inline: true; hint: "The voice runs here."; Label { role: "value"; text: "Local" } }
            Field { width: inkList.width; label: "Browser"; inline: true; RowAction { text: "Set up browser" } }
            Field {
                width: inkList.width
                label: "Voice"
                inline: true
                hint: "Jarvis hears you."
                Row { height: Theme.row.height; Badge { anchors.verticalCenter: parent.verticalCenter; text: "Done"; tone: "success" } }
            }
            Field { width: inkList.width; label: "Keys"; inline: true; hint: "One key per account." }
            StatusLine { width: inkList.width; label: "Accounts"; hint: "Signed in does not prove that the AI answers." }
            StatusLine { width: inkList.width; label: "Token"; tone: "warning"; text: "Absent"; hint: "Needed to sign in."; actionLabel: "Set up token"; actionOffered: true }
        }
    }

    // Status lines on a solid surface whose value's ink starts below its
    // box and above the label's: a hint drawn as the value with its link,
    // on one line, and a text value centred on the row.
    Rectangle {
        id: valueInkFrame
        x: 460
        width: 400
        height: valueInkList.height
        color: Theme.color.surface
        GroupList {
            id: valueInkList
            width: valueInkFrame.width
            StatusLine { width: valueInkList.width; label: "Token"; tone: "warning"; text: "Absent" }
            StatusLine { id: linkInk; width: valueInkList.width; label: "Keys"; hint: "Get a key from Acme."; hintLink: "Acme" }
            StatusLine { id: textInk; width: valueInkList.width; label: "Mode"; text: "Local" }
        }
    }

    // Groups that are a Row of an icon and its lines, on a solid surface.
    // The icon is centred on the name's capitals and taller than them, so
    // it starts above the text, and under a single line with no descender it
    // ends below it. The last group's folder wraps, as Google Drive's does,
    // and its last line, a timestamp path, draws no descender.
    Rectangle {
        id: iconInkFrame
        x: 460
        y: 400
        width: 400
        height: iconInkList.height
        color: Theme.color.surface
        GroupList {
            id: iconInkList
            width: iconInkFrame.width
            Repeater {
                model: [["Taxes", "Kept the older copy"], ["Rent"], ["Notes", "Restored the removed file"], ["Report", "The copy is kept in this folder: home/method/state/conflicts/20261013T094545Z-9829"]]
                Row {
                    id: iconGroup
                    required property var modelData
                    readonly property Item lines: iconLines
                    spacing: Theme.listItem.iconGap
                    Icon { y: Math.round(iconName.capCentre - height / 2); name: "file-exclamation-point"; size: Theme.icon.size.lg }
                    Column {
                        id: iconLines
                        width: 240
                        spacing: Theme.row.lineGap
                        Label { id: iconName; role: "item"; text: iconGroup.modelData[0] }
                        Label { width: parent.width; visible: iconGroup.modelData.length > 1; role: "itemHint"; textFormat: Text.PlainText; wrapMode: Text.Wrap; text: iconGroup.modelData[1] ?? "" }
                    }
                }
            }
        }
    }

    // Groups that are a heading over a group list of files, as Cloud
    // Sync's folder pairs: the first holds two files, the second one, so
    // the image draws a gap between two files and a gap between a file and
    // the next pair's heading.
    Rectangle {
        id: pairFrame
        x: 460
        y: 1900
        width: 400
        height: pairList.height
        color: Theme.color.surface
        GroupList {
            id: pairList
            width: pairFrame.width
            Repeater {
                model: [["Documents", ["Taxes", "Rent"]], ["Agent uploads", ["Report"]]]
                Column {
                    id: pair
                    required property var modelData
                    readonly property Item files: pairFiles
                    width: pairList.width
                    spacing: Theme.stack.row
                    Label { width: parent.width; role: "bodyStrong"; text: pair.modelData[0] }
                    GroupList {
                        id: pairFiles
                        Repeater {
                            model: pair.modelData[1]
                            Row {
                                required property string modelData
                                spacing: Theme.listItem.iconGap
                                Icon { y: Math.round(fileName.capCentre - height / 2); name: "file-exclamation-point"; size: Theme.icon.size.md }
                                Column {
                                    width: 300
                                    spacing: Theme.row.lineGap
                                    Label { id: fileName; role: "item"; text: modelData }
                                    Label { role: "itemHint"; text: "Kept the older copy in home/method/state" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A group that ends in a wrapped label whose last line has no
    // descender, as Google Drive's folder line, or with `descent` the same
    // label read by a descender's ink, as Label.inkBelow() read every
    // wrapped label by the font's descent: the control the centring must
    // refuse. Built after the theme sets its size, so the list lays out
    // once.
    Component {
        id: wrapFrame
        Rectangle {
            property bool descent: false
            readonly property alias list: wrapList
            readonly property alias label: wrapped
            x: 460
            y: 900
            width: 400
            height: wrapList.height
            color: Theme.color.surface
            GroupList {
                id: wrapList
                width: parent.width
                Item {
                    width: wrapList.width
                    implicitHeight: wrapped.implicitHeight
                    function inkBelow() { return descent ? wrapped.inkBelow("gjpqy") : wrapped.inkBelow(); }
                    Label { id: wrapped; width: parent.width; role: "hint"; textFormat: Text.PlainText; wrapMode: Text.Wrap; text: "Quietly gripping jumps, the older one sits in that folder and the rest is here" }
                }
                Label { width: wrapList.width; role: "hint"; text: "Next" }
            }
        }
    }

    // A padded control whose content is the list, as the Jarvis console's
    // audit records: each record takes the list's width and wraps in it,
    // and the control's height follows the list's.
    Component {
        id: paddedFrame
        T.Control {
            id: padded
            property var records: []
            readonly property alias list: paddedList
            x: 460
            y: 900
            width: 400
            padding: Theme.listItem.paddingX
            implicitHeight: implicitContentHeight + topPadding + bottomPadding
            contentItem: GroupList {
                id: paddedList
                Repeater {
                    model: padded.records
                    Label { required property string modelData; width: paddedList.width; role: "body"; textFormat: Text.PlainText; wrapMode: Text.Wrap; text: modelData }
                }
            }
        }
    }

    // Status lines with a step: a short chip keeps the step beside it, a
    // chip too long for both puts the step under it.
    StatusLine { id: shortStep; x: 0; y: 760; width: 400; label: "Token"; tone: "warning"; text: "Absent"; actionLabel: "Set up token"; actionOffered: true }
    StatusLine { id: linedStep; x: 0; y: 880; width: 400; label: "Setup"; tone: "warning"; text: "Set up needed"; lines: ["The model is missing.", "The service is off."]; actionLabel: "Set up"; actionOffered: true }
    StatusLine { id: shortText; x: 0; y: 1080; width: 400; label: "Mode"; text: "Local"; actionLabel: "Change"; actionOffered: true }
    StatusLine { id: longText; x: 0; y: 1140; width: 400; label: "Model"; text: "A model name far too long to share its line with the step beside it"; actionLabel: "Choose a model"; actionOffered: true }
    StatusLine { id: longHint; x: 0; y: 1000; width: 400; label: "Accounts"; hint: "Signed in does not prove that the AI answers. A test request may cost money, so check it yourself." }
    StatusLine { id: longStep; x: 0; y: 820; width: 400; label: "While logged out"; tone: "warning"; text: "Automations run only while you are logged in"; actionLabel: "Enable while logged out"; actionOffered: true }
    StatusLine { id: longState; x: 0; y: 1220; width: 260; label: "Check"; tone: "danger"; text: "The update check failed. Select Refresh to try again."; hint: "The update source could not be reached. Check your connection and select Refresh." }

    StatusLine { id: storedKey; x: 0; y: 1420; width: 400; label: "Acme"; tone: "success"; text: "Present"; access: "disconnect"; secretLabel: "Acme key" }
    StatusLine { id: absentKey; x: 0; y: 1480; width: 400; label: "Globex"; access: "connect"; secretLabel: "Acme key" }
    StatusLine { id: linkedHint; x: 0; y: 1740; width: 400; label: "Keys"; hint: "Get a client ID and secret for each direction from Google Cloud credentials."; hintLink: "Google Cloud credentials" }
    SignalSpy { id: linkPresses; target: linkedHint; signalName: "hintLinkActivated" }
    // A page reference in a hint drawn as the value, and in one under a value.
    StatusLine { id: pagedHint; x: 420; y: 1740; width: 400; label: "Keys"; hint: "Add a key on the [Models page](page:acme.models/Setup)." }
    StatusLine { id: pagedState; x: 420; y: 1800; width: 400; label: "Model"; text: "None"; hint: "Choose one on the [Models page](page:acme.models)." }
    SignalSpy { id: pagedHintPages; target: pagedHint; signalName: "hintPageActivated" }
    SignalSpy { id: pagedStatePages; target: pagedState; signalName: "hintPageActivated" }
    StatusLine { id: dangerStep; x: 0; y: 1540; width: 400; label: "Sign-in"; tone: "success"; text: "Signed in"; actionLabel: "Sign out"; actionOffered: true; actionTone: "danger" }
    SignalSpy { id: stores; target: storedKey; signalName: "storeSecret" }

    TestCase {
        name: "grouplist"
        when: windowShown

        function init() { UnitTheme.reset(); hidden.visible = false; }
        function cleanup() {
            storedKey.entering = false;
            storedKey.busy = false;
            storedKey.access = "disconnect";
            storedKey.width = 400;
            storedKey.label = "Acme";
            absentKey.entering = false;
        }

        function hairlinesOf(owner) {
            return owner.children.filter(child => child.vertical !== undefined && child.visible);
        }

        function shownGroups(owner) {
            return owner.children.find(child => child.tops !== undefined).shown;
        }

        // What breaks the rule that each gap between two shown groups is
        // `groupList.gap`, with one hairline centred in it, in its own
        // colour, across the list; [] when it holds. A positioner lays out
        // a turn after a change, so a check waits for it.
        function dividedProblems(owner) {
            const groups = shownGroups(owner);
            const lines = hairlinesOf(owner);
            const out = [];
            if (lines.length !== groups.length - 1) return ["hairlines=" + lines.length + " groups=" + groups.length];
            for (let i = 1; i < groups.length; i++) {
                const top = groups[i - 1].y + groups[i - 1].height;
                const line = lines[i - 1];
                if (groups[i].y - top !== Theme.groupList.gap) out.push("gap" + i + "=" + (groups[i].y - top));
                if (line.height !== Theme.divider.thickness || line.width !== owner.width) out.push("hairline" + i + ".size=" + line.width + "x" + line.height);
                if (line.y <= top || line.y + line.height > groups[i].y) out.push("hairline" + i + ".y=" + line.y + " outside " + top + " to " + groups[i].y);
                if (String(line.color) !== String(Qt.color(Theme.groupList.divider))) out.push("hairline" + i + ".color=" + line.color);
            }
            return out;
        }
        function checkDivided(owner) {
            tryVerify(() => dividedProblems(owner).length === 0, 1000, "the groups are divided: " + JSON.stringify(dividedProblems(owner)));
        }

        function test_groups_are_divided() {
            compare(shownGroups(list).length, 3);
            checkDivided(list);
            verify(Theme.groupList.gap > Theme.field.gap, "groups sit farther apart than the lines of one");
        }

        // A hidden group takes no gap and no hairline, and one shown again
        // takes both.
        function test_a_hidden_group_takes_no_hairline() {
            checkDivided(list);
            compare(hairlinesOf(list).length, 2);
            hidden.visible = true;
            checkDivided(list);
            compare(hairlinesOf(list).length, 3);
        }

        function test_a_nested_list_divides_its_own_groups() {
            checkDivided(outer);
            checkDivided(inner);
            compare(hairlinesOf(outer).length, 1);
            compare(hairlinesOf(inner).length, 1);
        }

        // The image cases call no waitForRendering: it waits for the next
        // frameSwapped (qtdeclarative 6.11 quicktestresult.cpp), which an
        // idle scene whose last frame swapped first never schedules, while
        // grabImage's grabWindow polishes, syncs and renders the scene itself
        // (qsgthreadedrenderloop.cpp and qsgrenderloop.cpp grab()).
        // Whether row Y of IMG, in device pixels, holds a pixel apart from
        // the surface: ink, or the hairline itself.
        function rowDrawn(img, y, surface) {
            for (let x = 0; x < img.width; x++) {
                if (Math.abs(img.red(x, y) - surface.r * 255) + Math.abs(img.green(x, y) - surface.g * 255) + Math.abs(img.blue(x, y) - surface.b * 255) > 30) return true;
            }
            return false;
        }

        // Each hairline of the list on the surface is drawn, and the blank
        // rows above it, to the group above's last drawn row, and below it,
        // to the group below's first, differ by at most two: the hairline
        // sits within a pixel of the middle of what the eye sees as the
        // gap. The rows are read from the image, not from the list.
        function test_each_hairline_is_centred_between_the_drawn_groups() {
            checkDivided(inkList);
            compare(offCentre(inkFrame, inkList, 8), [], "every hairline is centred between the drawn groups");
        }

        // The hairlines of OWNER, drawn on FRAME, that sit off the middle
        // of the blank rows between the drawn groups; [] when each is
        // centred.
        function offCentre(frame, owner, count) {
            verify(frame.y + frame.height <= root.height, "the list fits the window, so its image is whole");
            const img = grabImage(frame);
            const scale = img.width / frame.width;
            verify(Math.abs(img.height - frame.height * scale) <= 1, "the image holds the whole list");
            const surface = Qt.color(Theme.color.surface);
            const lines = hairlinesOf(owner).map(line => line.y).sort((a, b) => a - b);
            compare(lines.length, count, "one hairline between each two groups");
            const out = [];
            for (const y of lines) {
                const row = Math.round(y * scale);
                verify(rowDrawn(img, row, surface), "the hairline at " + y + " is drawn");
                let above = row - 1;
                while (above >= 0 && !rowDrawn(img, above, surface)) above--;
                let below = row + Theme.divider.thickness * scale;
                while (below < img.height && !rowDrawn(img, below, surface)) below++;
                const blankAbove = (row - above - 1) / scale, blankBelow = (below - row - Theme.divider.thickness * scale) / scale;
                if (Math.abs(blankAbove - blankBelow) > 2) out.push("hairline@" + y + " blank above=" + blankAbove + " below=" + blankBelow);
            }
            return out;
        }

        // The drawn rows from the last ink above each hairline of LISTS,
        // drawn on FRAME, to the first ink under it, the hairline included,
        // in the order LISTS names them.
        function inkSpans(frame, lists) {
            const img = grabImage(frame);
            const scale = img.width / frame.width;
            const surface = Qt.color(Theme.color.surface);
            const out = [];
            for (const owner of lists) {
                for (const line of hairlinesOf(owner)) {
                    const row = Math.round(line.mapToItem(frame, 0, 0).y * scale);
                    let above = row - 1;
                    while (above >= 0 && !rowDrawn(img, above, surface)) above--;
                    let below = row + Theme.divider.thickness * scale;
                    while (below < img.height && !rowDrawn(img, below, surface)) below++;
                    out.push((below - above - 1) / scale);
                }
            }
            return out;
        }

        // The span from a file's ink to the next pair's heading is the span
        // from one file's ink to the next's, within a pixel, and the
        // hairline stays centred in it. With the gap set by the groups'
        // boxes, the heading's leading puts it farther.
        function test_a_heading_over_its_files_stands_a_file_gap_under_the_file_above() {
            const pairs = shownGroups(pairList);
            compare(pairs.length, 2);
            tryVerify(() => shownGroups(pairs[0].files).length === 2 && hairlinesOf(pairs[0].files).length === 1 && hairlinesOf(pairList).length === 1, 1000, "the pairs lay out their files");
            verify(Theme.inkAbove(pairs[1]) - Theme.inkAbove(pairs[1].files) > 1, "the heading's ink starts more than a pixel below where a file's does");
            const spans = inkSpans(pairFrame, [pairs[0].files, pairList]);
            compare(spans.length, 2);
            verify(Math.abs(spans[1] - spans[0]) <= 1, "file to heading " + spans[1] + " rows, file to file " + spans[0]);
            compare(offCentre(pairFrame, pairList, 1), [], "the hairline over the heading is centred");
        }

        // At 40 px the font's descent lies 8 px or more under the
        // baseline, past the pixel the centring allows. The first line
        // has descenders and the last none, so the reading is the last
        // line's glyphs, not the whole text's.
        function test_a_hairline_under_a_wrapped_line_without_descenders_data() {
            return [
                { tag: "glyphs", control: false },
                { tag: "descent", control: true }
            ];
        }

        function test_a_hairline_under_a_wrapped_line_without_descenders(data) {
            compare(UnitTheme.override({ text: { hint: { size: 40 } } }), "ok");
            const frame = createTemporaryObject(wrapFrame, root, { descent: data.control });
            verify(frame !== null);
            const label = frame.label;
            tryVerify(() => label.lineCount > 2 && label.lastLineText() !== null, 2000, "the label wraps and names its last line");
            const last = label.lastLineText();
            verify(last.length > 0 && label.text.endsWith(last) && !/[gjpqy]/.test(last) && /[gjpqy]/.test(label.text), "the last line \"" + last + "\" has no descender, the text has");
            // At 40 px the label's leading holds the centred hairline, so
            // the list's box gap is not read here, only the drawn rows.
            tryVerify(() => shownGroups(frame.list).length === 2 && hairlinesOf(frame.list).length === 1, 1000, "the list lays out its two groups");
            const out = offCentre(frame, frame.list, 1);
            if (data.control) compare(out.length, 1, "the centring refuses a descent reading");
            else compare(out, [], "the hairline is centred under the last line's glyphs");
        }

        // The list keeps the one width its control gives it, inside the
        // padding, while records arrive and the control narrows, so no
        // binding of its layout runs again inside itself. A list that
        // follows the control's whole width is written two widths, and
        // logs a binding loop.
        function test_a_list_in_a_padded_control_takes_the_width_inside_the_padding() {
            failOnWarning(/Binding loop detected/);
            const frame = createTemporaryObject(paddedFrame, root);
            verify(frame !== null);
            verify(frame.padding > 0, "the control pads its content");
            frame.records = ["A record long enough to wrap onto a second line once its control narrows to half its width", "Next"];
            tryVerify(() => shownGroups(frame.list).length === 2, 1000, "the list lays out its two records");
            compare(frame.list.width, frame.availableWidth);
            const wide = frame.height;
            frame.width = 200;
            compare(frame.list.width, frame.availableWidth);
            tryVerify(() => frame.height > wide, 1000, "the narrower control grows with its wrapped record");
            compare(frame.height, frame.list.implicitHeight + 2 * frame.padding);
            checkDivided(frame.list);
        }

        // The ink a hairline reads of the group under it, the line's own
        // `inkAbove()`, is the line's first drawn row in the image, within
        // a pixel, for a link drawn as the value and a text value whose
        // ink starts below their boxes. A line that reports its value's
        // box top in place of its ink is off by that ink offset, which
        // the image shows is more than the pixel allowed: the line draws
        // nothing, label or value, within 1.5 of its value's box top.
        function test_a_lines_ink_starts_at_its_first_drawn_row() {
            checkDivided(valueInkList);
            const link = findChild(linkInk, LinkText);
            verify(link !== null && link.lineCount === 1, "the hint is drawn as the value, as one line of a link");
            verify(link.linked, "the hint cites its link's words");
            // The Loader that holds a line's value, in the frame.
            const valueTop = line => {
                const stack = [line];
                while (stack.length > 0) {
                    const at = stack.pop();
                    if (at.firstLine !== undefined) return at.children.find(child => child instanceof Loader).mapToItem(valueInkFrame, 0, 0).y;
                    for (const child of at.children) stack.push(child);
                }
                return null;
            };
            const img = grabImage(valueInkFrame);
            const scale = img.width / valueInkFrame.width;
            const surface = Qt.color(Theme.color.surface);
            const out = [];
            for (const line of shownGroups(valueInkList)) {
                const top = line.mapToItem(valueInkFrame, 0, 0).y;
                let row = Math.round(top * scale);
                while (row < img.height && !rowDrawn(img, row, surface)) row++;
                const ink = top + Theme.inkAbove(line);
                if (Math.abs(row / scale - ink) > 1) out.push(line.label + " ink=" + ink + " drawn=" + row / scale);
                if ((line === linkInk || line === textInk) && !(row / scale - valueTop(line) > 1.5)) out.push(line.label + " drawn=" + row / scale + " within 1.5 of its value's box top " + valueTop(line));
            }
            compare(out, [], "each line's ink starts at its first drawn row");
        }

        // A group that is a Row of an icon and its lines reports the ink of
        // both: where it starts is its first drawn row in the image and
        // where it ends its last, within a pixel, so the hairlines between
        // such groups are centred. The lines alone are the control: their
        // ink starts more than the pixel allowed below every group's first
        // drawn row, and ends as far above the last drawn row of the group
        // with a single line.
        function test_a_row_reports_the_ink_of_its_icon_and_its_lines() {
            checkDivided(iconInkList);
            const groups = shownGroups(iconInkList);
            compare(groups.length, 4);
            const folder = groups[3].lines.children[1];
            verify(folder.lineCount > 1 && folder.lastLineText() !== null && !/[gjpqy,]/.test(folder.lastLineText()) && /[gjpqy]/.test(folder.text),
                "the folder wraps to a last line with no descender: " + folder.lastLineText());
            const img = grabImage(iconInkFrame);
            const scale = img.width / iconInkFrame.width;
            const surface = Qt.color(Theme.color.surface);
            const hairlines = hairlinesOf(iconInkList).map(line => Math.round(line.y * scale));
            const out = [];
            groups.forEach((group, i) => {
                const top = group.mapToItem(iconInkFrame, 0, 0).y;
                let first = i === 0 ? 0 : hairlines[i - 1] + Theme.divider.thickness * scale;
                while (first < img.height && !rowDrawn(img, first, surface)) first++;
                let last = i === groups.length - 1 ? img.height - 1 : hairlines[i] - 1;
                while (last >= 0 && !rowDrawn(img, last, surface)) last--;
                const drawn = { top: first / scale, bottom: (last + 1) / scale };
                const row = { top: top + Theme.inkAbove(group), bottom: top + group.height - Theme.inkBelow(group) };
                const lines = { top: top + Theme.inkAbove(group.lines), bottom: top + group.lines.height - Theme.inkBelow(group.lines) };
                if (Math.abs(row.top - drawn.top) > 1 || Math.abs(row.bottom - drawn.bottom) > 1) out.push(group.modelData[0] + " ink=" + JSON.stringify(row) + " drawn=" + JSON.stringify(drawn));
                if (!(lines.top - drawn.top > 1)) out.push(group.modelData[0] + " lines start at " + lines.top + ", within a pixel of the drawn " + drawn.top);
                if (group.modelData.length === 1 && !(drawn.bottom - lines.bottom > 1)) out.push(group.modelData[0] + " line ends at " + lines.bottom + ", within a pixel of the drawn " + drawn.bottom);
            });
            compare(out, [], "each group's ink is what the image draws, and its lines alone are not");
        }

        function test_a_theme_moves_the_gap_and_the_hairline() {
            compare(UnitTheme.override({ groupList: { gap: 20, divider: "#ff000080" } }), "ok");
            compare(Theme.groupList.gap, 20);
            checkDivided(list);
            compare(String(hairlinesOf(list)[0].color), String(Qt.color("#80ff0000")));
        }

        // The lines of one group sit `field.gap` apart: the key/value row
        // and its hint.
        // The step's RowAction and the value's chip of a status line, in
        // the line's frame.
        function stepOf(line) { return findChild(line, RowAction); }
        function chipOf(line) { return findChild(line, Badge); }
        function findChild(item, type) {
            for (const child of item.children) {
                if (child instanceof type && child.visible) return child;
                const found = findChild(child, type);
                if (found !== null) return found;
            }
            return null;
        }
        function box(item, line) { const at = item.mapToItem(line, 0, 0); return { x: at.x, y: at.y, right: at.x + item.width, bottom: at.y + item.height }; }

        function test_a_step_stands_beside_a_short_value_and_under_a_long_one() {
            const chip = box(chipOf(shortStep), shortStep), step = box(stepOf(shortStep), shortStep);
            compare(step.x, chip.right + Theme.stack.inline, "the step stands right after the chip");
            fuzzyCompare(step.y + (step.bottom - step.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            const longChip = box(chipOf(longStep), longStep), longAction = box(stepOf(longStep), longStep);
            verify(longAction.y >= longChip.bottom, "the step sits under a chip too long for both");
            compare(longAction.x, longChip.x, "the step starts on the value column");
        }

        // A step beside a chip with further lines centres on the first
        // chip, and a hint that stands as the value grows the row with
        // its wrapped lines.
        function test_a_step_centres_on_the_first_chip_and_a_wrapped_value_fits() {
            const chip = box(chipOf(linedStep), linedStep), step = box(stepOf(linedStep), linedStep);
            fuzzyCompare(step.y + (step.bottom - step.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            const hint = findChild(longHint, Label);
            let wrapped = null;
            for (const item of [longHint]) {
                const stack = [item];
                while (stack.length > 0) {
                    const at = stack.pop();
                    if (at.role === "hint" && at.text !== "" && at.visible) wrapped = at;
                    for (const child of at.children) stack.push(child);
                }
            }
            verify(wrapped !== null && wrapped.lineCount > 1, "the hint wraps");
            verify(box(wrapped, longHint).bottom <= longHint.height + 0.5, "the row holds every wrapped line");
        }

        // A text value with a step: the step stands beside a short text,
        // and under a text too long for both, which then takes the whole
        // value column; the choice is the same however the line is built.
        function test_a_text_value_keeps_its_step_beside_or_under() {
            // The line's shown text in the value role.
            const value = line => {
                const stack = [line];
                while (stack.length > 0) {
                    const at = stack.shift();
                    if (at !== line && at.role === "value" && at.visible) return at;
                    for (const child of at.children) stack.push(child);
                }
                return null;
            };
            const shortValue = box(value(shortText), shortText), shortAction = box(stepOf(shortText), shortText);
            compare(shortAction.x, shortValue.right + Theme.stack.inline, "the step stands right after a short text");
            const longValue = box(value(longText), longText), longAction = box(stepOf(longText), longText);
            verify(longAction.y >= longValue.bottom, "the step sits under a text too long for both");
            compare(longAction.x, longValue.x, "the step starts on the value column");
            longText.width = 0;
            longText.width = 400;
            tryVerify(() => box(stepOf(longText), longText).y >= box(value(longText), longText).bottom, 1000, "the step stays under the text after a relayout");
        }

        // A state too long for the value column keeps its chip, and the
        // chip's label, inside the line; its sentence wraps under it,
        // inside the line too.
        function test_a_long_state_and_its_sentence_stay_inside_the_line() {
            const chip = chipOf(longState);
            const chipBox = box(chip, longState);
            verify(chipBox.right <= longState.width + 0.5, "the chip ends inside the line: " + chipBox.right + " > " + longState.width);
            verify(chip.width < chip.implicitWidth, "the fixture's state is too long for the value column");
            const label = chip.children.find(child => child.role === "label");
            verify(label !== undefined, "the chip holds its label");
            verify(label.truncated, "the label elides");
            verify(box(label, longState).x + label.contentWidth <= chipBox.right + 0.5, "the label's text ends inside the chip");
            let sentence = null;
            const stack = [longState];
            while (stack.length > 0) {
                const at = stack.pop();
                if (at.role === "hint" && at.text === longState.hint && at.visible) sentence = at;
                for (const child of at.children) stack.push(child);
            }
            verify(sentence !== null, "the line draws its sentence");
            verify(sentence.lineCount > 1, "the sentence wraps");
            const sentenceBox = box(sentence, longState);
            verify(sentenceBox.y >= chipBox.bottom, "the sentence sits under the chip");
            verify(sentenceBox.x + sentence.contentWidth <= longState.width + 0.5, "the sentence ends inside the line");
            verify(sentenceBox.bottom <= longState.height + 0.5, "the line holds every wrapped line of the sentence");
        }

        // The shown RowActions of a status line, in drawn order.
        function actionsOf(line) {
            const out = [];
            const stack = [line];
            while (stack.length > 0) {
                const at = stack.shift();
                if (at instanceof RowAction && at.visible) out.push(at);
                for (const child of at.children) stack.push(child);
            }
            return out.sort((a, b) => box(a, line).x - box(b, line).x);
        }

        // A stored secret's line: its chip, Replace and Remove on one
        // centre, Replace right after the chip and Remove `rowAction.gap`
        // after it in the danger tone, and no icon button. A secret nothing
        // is stored for draws no chip, and Add key starts on the value
        // column.
        function test_a_secret_line_draws_its_steps() {
            const chip = box(chipOf(storedKey), storedKey);
            const actions = actionsOf(storedKey);
            compare(actions.map(action => [action.text, action.tone]), [["Replace", "accent"], ["Remove", "danger"]]);
            compare(findChild(storedKey, IconButton), null, "a stored secret's line draws no icon button");
            const replaceBox = box(actions[0], storedKey), removeBox = box(actions[1], storedKey);
            compare(replaceBox.x, chip.right + Theme.stack.inline, "Replace stands right after the chip");
            compare(removeBox.x, replaceBox.right + Theme.rowAction.gap, "Remove stands right after Replace");
            fuzzyCompare(replaceBox.y + (replaceBox.bottom - replaceBox.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            fuzzyCompare(removeBox.y + (removeBox.bottom - removeBox.y) / 2, chip.y + (chip.bottom - chip.y) / 2, 1);
            compare(chipOf(absentKey), null, "a secret nothing is stored for draws no chip");
            compare(actionsOf(absentKey).map(action => action.text), ["Add key"], "it draws Add key alone");
            const add = stepOf(absentKey);
            verify(add !== null && add.text === "Add key", "it draws Add key");
            const field = absentKey.children.find(child => child.valueX !== undefined);
            compare(box(add, absentKey).x, field.valueX, "Add key starts on the value column");
        }

        // A hint drawn as the value keeps its link: the shown LinkText on
        // the value column cites the link's words, and its press emits
        // the line's hintLinkActivated.
        function test_a_hint_value_keeps_its_link() {
            linkPresses.clear();
            const field = linkedHint.children.find(child => child.valueX !== undefined);
            const links = [];
            const stack = [linkedHint];
            while (stack.length > 0) {
                const at = stack.pop();
                if (at instanceof LinkText && at.visible && at.text === linkedHint.hint) links.push(at);
                for (const child of at.children) stack.push(child);
            }
            compare(links.length, 1, "the hint is drawn once, as one LinkText");
            verify(links[0].linked, "the hint cites its link's words");
            compare(links[0].link, "Google Cloud credentials");
            compare(box(links[0], linkedHint).x, field.valueX, "the hint starts on the value column");
            links[0].clicked();
            compare(linkPresses.count, 1, "a press on the link emits hintLinkActivated");
        }

        // A page reference in a line's hint, drawn as the value or under
        // one, emits the line's hintPageActivated with its page and tab.
        function test_a_hint_page_reference_asks_for_its_page() {
            for (const [line, spy, tab] of [[pagedHint, pagedHintPages, "Setup"], [pagedState, pagedStatePages, ""]]) {
                spy.clear();
                const links = [];
                const stack = [line];
                while (stack.length > 0) {
                    const at = stack.pop();
                    if (at instanceof LinkText && at.visible && at.text === line.hint) links.push(at);
                    for (const child of at.children) stack.push(child);
                }
                compare(links.length, 1, "the hint is drawn once, as one LinkText");
                links[0].clicked();
                compare(spy.count, 1, "a press on the reference emits hintPageActivated");
                compare(spy.signalArguments[0][0], "acme.models");
                compare(spy.signalArguments[0][1], tab);
            }
        }

        // A step declared danger draws in the danger tone.
        function test_a_danger_step_draws_in_the_danger_tone() {
            compare(actionsOf(dangerStep).map(action => [action.text, action.tone]), [["Sign out", "danger"]]);
            compare(actionsOf(shortStep).map(action => action.tone), ["accent"], "a step with no tone draws as an accent action");
        }

        // Replace and Add key open the masked field in the steps' place;
        // Enter hands on what was typed and closes it, and Escape closes it
        // with nothing handed on.
        function test_a_secret_step_opens_the_masked_field() {
            stores.clear();
            compare(findChild(storedKey, TextField), null, "a closed line holds no field");
            let closedAtStore = false;
            const inspectStore = () => closedAtStore = findChild(storedKey, TextField) === null;
            storedKey.storeSecret.connect(inspectStore);
            actionsOf(storedKey)[0].clicked();
            tryVerify(() => findChild(storedKey, TextField) !== null);
            let input = findChild(storedKey, TextField);
            verify(input.password);
            compare(input.text, "");
            verify(input.activeFocus);
            compare(actionsOf(storedKey).length, 2);
            input.accepted();
            compare(stores.count, 0, "empty input cannot save");
            storedKey.saveSecret("two\nlines");
            storedKey.saveSecret("two\rlines");
            compare(stores.count, 0, "a multiline key cannot reach the writer");
            input.text = "typed-key";
            storedKey.busy = true;
            input.accepted();
            compare(stores.count, 0, "busy Enter cannot save");
            verify(storedKey.entering);
            storedKey.busy = false;
            input.accepted();
            compare(stores.count, 1);
            compare(stores.signalArguments[0][0], "typed-key");
            verify(closedAtStore, "the field is destroyed before the direct writer is called");
            storedKey.storeSecret.disconnect(inspectStore);
            tryVerify(() => findChild(storedKey, TextField) === null);
            verify(actionsOf(storedKey)[0].activeFocus, "Save returns focus to Replace");
            actionsOf(storedKey)[0].clicked();
            input = findChild(storedKey, TextField);
            compare(input.text, "", "reopening retains no input");
            input.text = "discarded-key";
            actionsOf(storedKey).find(action => action.text === "Cancel").clicked();
            tryVerify(() => findChild(storedKey, TextField) === null);
            verify(actionsOf(storedKey)[0].activeFocus);
            stepOf(absentKey).clicked();
            tryVerify(() => findChild(absentKey, TextField) !== null);
            findChild(absentKey, TextField).text = "discarded-key";
            keyClick(Qt.Key_Escape);
            tryVerify(() => findChild(absentKey, TextField) === null);
            verify(stepOf(absentKey).activeFocus, "Escape returns focus to Add key");
            storedKey.text = "Updated status";
            wait(0);
            verify(stepOf(absentKey).activeFocus, "another status publish does not steal focus");
            storedKey.text = "Present";
            compare(stores.count, 1);
            actionsOf(storedKey)[0].clicked();
            findChild(storedKey, TextField).text = "discarded-on-navigation";
            storedKey.visible = false;
            tryVerify(() => findChild(storedKey, TextField) === null);
            storedKey.visible = true;
            actionsOf(storedKey)[0].clicked();
            compare(findChild(storedKey, TextField).text, "");
            storedKey.cancelEntry();
            const beginWrite = () => storedKey.busy = true;
            storedKey.storeSecret.connect(beginWrite);
            actionsOf(storedKey)[0].clicked();
            findChild(storedKey, TextField).text = "replacement-key";
            findChild(storedKey, TextField).accepted();
            verify(storedKey.busy);
            storedKey.storeSecret.disconnect(beginWrite);
            storedKey.busy = false;
            verify(actionsOf(storedKey)[0].activeFocus, "write completion restores Replace");
        }

        function test_a_secret_editor_uses_the_value_row() {
            for (const width of [400, 320]) {
                storedKey.width = width;
                storedKey.label = width === 320 ? "A long workspace label that wraps" : "Acme";
                actionsOf(storedKey)[0].clicked();
                tryVerify(() => findChild(storedKey, TextField) !== null);
                wait(0);
                const input = findChild(storedKey, TextField);
                const field = storedKey.children.find(child => child.valueX !== undefined);
                const row = field.children.find(child => child.objectName === "fieldRow");
                const label = row.children.find(child => child.objectName === "fieldLabel");
                const inputBox = box(input, field), rowBox = box(row, field);
                compare(inputBox.x, field.valueX);
                verify(inputBox.y < rowBox.bottom && inputBox.bottom <= rowBox.bottom,
                       "the editor replaces the value inside the original row, above its end");
                verify(input.width >= input.minimumWidth, "the input retains its shared usable width");
                for (const action of actionsOf(storedKey)) {
                    const actionBox = box(action, field);
                    verify(actionBox.right <= field.width, "actions remain inside the value column");
                    verify(actionBox.x >= inputBox.right || actionBox.y >= inputBox.bottom,
                           "wrapped actions do not overlap the input");
                }
                if (label !== undefined) verify(box(label, field).right <= inputBox.x, "a wrapping label stays clear");
                storedKey.cancelEntry();
            }
        }

        function test_a_first_key_write_returns_focus_after_presence_publishes() {
            const beginWrite = () => absentKey.busy = true;
            absentKey.storeSecret.connect(beginWrite);
            for (const destination of ["same-row", "other-row", "navigation"]) {
                absentKey.access = "connect";
                stepOf(absentKey).clicked();
                const input = findChild(absentKey, TextField);
                input.text = "first-key";
                input.accepted();
                verify(absentKey.busy);
                // SecretWriter.finish calls done before the plugin's asynchronous
                // presence probe publishes its new access, so busy ends first.
                if (destination === "navigation") {
                    absentKey.visible = false;
                    actionsOf(storedKey)[0].forceActiveFocus();
                }
                absentKey.busy = false;
                if (destination === "other-row") actionsOf(storedKey)[0].forceActiveFocus();
                absentKey.access = "disconnect";
                wait(0);
                verify(destination === "same-row" ? actionsOf(absentKey)[0].activeFocus : actionsOf(storedKey)[0].activeFocus,
                       "presence transfers focus to Replace only while this row still owns it");
                absentKey.visible = true;
            }
            absentKey.storeSecret.disconnect(beginWrite);
            absentKey.access = "connect";
        }

        function test_a_groups_own_lines_sit_close() {
            const field = warden.children.find(child => child.valueX !== undefined);
            verify(field !== undefined, "the line holds its field");
            compare(warden.spacing, Theme.field.gap);
            const row = field.children.find(child => child.objectName === "fieldRow");
            const hint = field.children.find(child => child.height > 0 && child.children.length > 0 && child.children[0].role === "hint");
            verify(row !== undefined && hint !== undefined, "the field holds its row and its hint");
            compare(hint.children[0].mapToItem(field, 0, 0).y - (row.y + row.valueBottom), Theme.field.gap, "the hint sits under the value");
        }
    }
}
