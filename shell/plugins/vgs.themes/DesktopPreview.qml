import QtQuick
import qs.Commons
import qs.Ui

// A theme's desktop drawn from its tokens over the card's wallpaper: the
// VGS bar across the top and, where `desktopPreview` places them, a
// Settings window, the launcher's search and a terminal, the wallpaper
// showing around them. Every colour comes from `tokens` and `terminal`, the
// package's own, never from Theme, which holds the applied theme; Theme
// gives the shapes and the type. The desktop is laid out on a reference
// display of `desktopPreview.referenceWidth` by `referenceHeight` and
// scaled to cover the card, so every length below is a reference pixel.
// Each window keeps `safeInset` from the card's edge plus the card's lean,
// so none crosses the angled edge, ends above the card's `footHeight`, and
// its content clears the theme's own window corner (Inset.clearing).
Item {
    id: root

    property var tokens: ({})
    property var terminal: null
    // The theme's package name and title, which the terminal names.
    property string name: ""
    property string label: "Theme"
    // The card's height, in card pixels, that its palette strip covers.
    property real footHeight: 0

    readonly property color backgroundColor: tokenColor("palette.background", Theme.color.background)
    readonly property color foregroundColor: tokenColor("palette.foreground", Theme.color.text)
    readonly property color accentColor: tokenColor("palette.accent", Theme.color.accent)
    readonly property color surfaceColor: tokenColor("color.surfaceRaised", backgroundColor)
    readonly property color borderColor: tokenColor("color.border", foregroundColor)
    readonly property color activeBorderColor: accentColor
    readonly property color inactiveBorderColor: borderColor
    readonly property color mutedColor: tokenColor("color.textMuted", foregroundColor)
    readonly property color selectedColor: tokenColor("color.accentSubtle", "transparent")
    readonly property color shadowColor: tokenColor("hyprland.shadow.color", Theme.hyprland.shadow.color)
    readonly property real borderSize: tokenNumber("hyprland.border.size", Theme.hyprland.border.size)
    readonly property real windowRadius: tokenNumber("hyprland.window.radius", Theme.hyprland.window.radius)
    readonly property real scale: Math.max(width / Theme.desktopPreview.referenceWidth, height / Theme.desktopPreview.referenceHeight)
    readonly property real safeInset: Theme.desktopPreview.gap + Theme.angledCard.skew / Math.max(scale, 0.1)
    readonly property real safeLeft: safeInset + Math.max(0, -desktop.x / Math.max(scale, 0.1))
    readonly property real safeRight: safeInset + Math.max(0, (desktop.x + desktop.width * scale - root.width) / Math.max(scale, 0.1))
    readonly property rect mockBounds: Qt.rect(desktop.x, desktop.y, desktop.width * scale, desktop.height * scale)
    readonly property string accentHex: accentColor.toString()

    // The inset of a window's content: `desktopPreview.padding`, grown until
    // its corners clear the window's corner.
    function contentInset(box) {
        return Math.ceil(Inset.clearing(Theme.desktopPreview.padding, box.radius, box.width, box.height, Theme.inset.cornerStep, Theme.desktopPreview.padding));
    }

    function token(path) {
        let node = root.tokens;
        const parts = path.split(".");
        for (let i = 0; i < parts.length; i++) {
            if (node === null || node === undefined) return undefined;
            node = node[parts[i]];
        }
        return node;
    }

    function tokenColor(path, fallback) {
        const value = token(path);
        return typeof value === "string" ? Theme.toColor(value) : fallback;
    }

    function tokenNumber(path, fallback) {
        const value = token(path);
        return typeof value === "number" ? value : fallback;
    }

    function terminalColor(index) {
        const key = "color" + index;
        if (root.terminal !== null && typeof root.terminal === "object" && typeof root.terminal[key] === "string")
            return Theme.toColor(root.terminal[key]);
        if (index === 0) return backgroundColor;
        if (index === 7) return foregroundColor;
        if (index === 1) return tokenColor("palette.danger", accentColor);
        if (index === 2) return tokenColor("palette.success", accentColor);
        if (index === 3) return tokenColor("palette.warning", accentColor);
        if (index === 4) return tokenColor("palette.info", accentColor);
        return mutedColor;
    }

    Item {
        id: desktop
        x: (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2
        width: Theme.desktopPreview.referenceWidth
        height: Theme.desktopPreview.referenceHeight
        scale: root.scale
        transformOrigin: Item.TopLeft

        // Where the windows end: `safeInset` above the card's foot, which
        // the card's lean does not reach.
        readonly property real windowBottom: height - root.safeInset - root.footHeight / Math.max(root.scale, 0.1)

        // The x of a window SHARE of the width in, WIDE wide, moved in
        // until it keeps the safe inset on both sides.
        function placeX(share, wide) {
            return Math.max(root.safeLeft, Math.min(width * share, width - root.safeRight - wide));
        }

        Rectangle {
            id: bar
            objectName: "previewBar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Theme.desktopPreview.barHeight
            color: root.backgroundColor

            Row {
                anchors.left: parent.left
                anchors.leftMargin: root.safeLeft
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.bar.item.gap

                Repeater {
                    model: ["1", "2", "3", "5"]
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: Theme.bar.item.height
                        height: Theme.bar.item.height
                        radius: Theme.bar.item.radius
                        color: index === 0 ? root.accentColor : "transparent"

                        Label {
                            anchors.centerIn: parent
                            role: "bar"
                            text: parent.modelData
                            color: parent.index === 0 ? root.backgroundColor : root.mutedColor
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                role: "bar"
                text: "Monday Oct 5, 5:06 PM"
                color: root.foregroundColor
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: root.safeRight
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.bar.gap

                Repeater {
                    model: ["wifi", "vol", "79%"]
                    Label {
                        required property string modelData
                        role: "bar"
                        color: root.mutedColor
                        text: modelData
                    }
                }
            }
        }

        Repeater {
            model: [settings, launcher, terminal]
            Rectangle {
                required property Item modelData
                x: modelData.x + Theme.desktopPreview.shadowOffset
                y: modelData.y + Theme.desktopPreview.shadowOffset
                width: modelData.width
                height: modelData.height
                radius: modelData.radius
                color: root.shadowColor
            }
        }

        // The Settings window, focused: the theme's active border, a
        // sidebar with its search and its selected section, and that
        // section's page.
        Rectangle {
            id: settings
            objectName: "previewWindow"
            width: desktop.width * Theme.desktopPreview.settings.width
            x: desktop.placeX(Theme.desktopPreview.settings.x, width)
            y: desktop.height * Theme.desktopPreview.settings.y
            height: Math.min(desktop.height * Theme.desktopPreview.settings.height, desktop.windowBottom - y)
            radius: root.windowRadius
            color: root.backgroundColor
            border.color: root.activeBorderColor
            border.width: Math.max(Theme.border.thin, root.borderSize)
            clip: true

            Item {
                anchors.fill: parent
                anchors.margins: root.contentInset(settings)

                Column {
                    id: sidebar
                    width: Theme.row.labelWidth
                    spacing: Theme.stack.row

                    Rectangle {
                        width: parent.width
                        height: Theme.size.control.sm
                        color: "transparent"
                        border.color: root.borderColor
                        border.width: Theme.border.thin
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.control.sm.paddingX
                            role: "itemHint"
                            color: root.mutedColor
                            text: "Search sections"
                        }
                    }
                    Repeater {
                        model: [
                            { text: "Connectivity", heading: true },
                            { text: "Bluetooth" },
                            { text: "Network" },
                            { text: "VPN", selected: true },
                            { text: "Hardware", heading: true },
                            { text: "Sound" },
                            { text: "Displays" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: sidebar.width
                            height: Theme.size.control.sm
                            color: modelData.selected === true ? root.selectedColor : "transparent"
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.control.sm.paddingX
                                role: parent.modelData.heading === true ? "label" : "item"
                                color: parent.modelData.heading === true || parent.modelData.selected === true ? root.accentColor : root.foregroundColor
                                text: parent.modelData.text
                            }
                        }
                    }
                }

                Rectangle {
                    id: rule
                    anchors.left: sidebar.right
                    anchors.leftMargin: Theme.desktopPreview.padding
                    width: Theme.border.thin
                    height: parent.height
                    color: root.borderColor
                }

                Column {
                    id: page
                    anchors.left: rule.right
                    anchors.leftMargin: Theme.desktopPreview.padding
                    anchors.right: parent.right
                    spacing: Theme.stack.row

                    Item {
                        width: page.width
                        height: Theme.size.control.sm
                        Label { anchors.verticalCenter: parent.verticalCenter; role: "bodyStrong"; color: root.foregroundColor; text: "Sound" }
                        Rectangle {
                            id: toggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.toggle.size.sm.width
                            height: Theme.toggle.size.sm.height
                            radius: Theme.toggle.radius
                            color: root.accentColor
                            Rectangle {
                                x: parent.width - width - Theme.toggle.inset
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.height - 2 * Theme.toggle.inset
                                height: width
                                radius: Theme.toggle.radius
                                color: root.backgroundColor
                            }
                        }
                    }
                    Repeater {
                        model: [
                            { text: "Output", heading: true },
                            { text: "Device", value: "Studio Display" },
                            { text: "Volume", level: 0.3 },
                            { text: "Input", heading: true },
                            { text: "Device", value: "Shure MV7" },
                            { text: "Volume", level: 1 }
                        ]
                        Item {
                            id: line
                            required property var modelData
                            width: page.width
                            height: Theme.size.control.sm
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "label"
                                color: line.modelData.heading === true ? root.accentColor : root.mutedColor
                                text: line.modelData.text
                            }
                            Rectangle {
                                visible: typeof line.modelData.value === "string"
                                anchors.right: parent.right
                                width: page.width / 2 + Theme.space.xxl
                                height: parent.height
                                color: "transparent"
                                border.color: root.borderColor
                                border.width: Theme.border.thin
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Theme.control.sm.paddingX
                                    role: "item"
                                    color: root.foregroundColor
                                    text: typeof line.modelData.value === "string" ? line.modelData.value : ""
                                }
                            }
                            Rectangle {
                                id: track
                                visible: typeof line.modelData.level === "number"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: page.width / 2 + Theme.space.xxl
                                height: Theme.slider.track
                                radius: Theme.slider.radius
                                color: root.borderColor
                                Rectangle {
                                    width: parent.width * (typeof line.modelData.level === "number" ? line.modelData.level : 0)
                                    height: parent.height
                                    radius: Theme.slider.radius
                                    color: root.accentColor
                                }
                                Rectangle {
                                    x: parent.width * (typeof line.modelData.level === "number" ? line.modelData.level : 0) - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.slider.handle
                                    height: Theme.slider.handle
                                    radius: Theme.slider.radius
                                    color: root.foregroundColor
                                }
                            }
                        }
                    }
                }
            }
        }

        // The launcher's search, open over the desktop.
        Rectangle {
            id: launcher
            objectName: "previewLauncher"
            width: desktop.width * Theme.desktopPreview.launcher.width
            x: (desktop.width - width) / 2
            y: desktop.height * Theme.desktopPreview.launcher.y
            height: Theme.size.control.lg
            radius: Theme.radius.full
            color: root.surfaceColor
            border.color: root.borderColor
            border.width: Theme.border.thin

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.control.lg.paddingX
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.control.gap
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.icon.size.sm
                    height: Theme.icon.size.sm
                    radius: Theme.radius.full
                    color: "transparent"
                    border.color: root.mutedColor
                    border.width: Theme.border.thick
                }
                Label { anchors.verticalCenter: parent.verticalCenter; role: "body"; color: root.mutedColor; text: "Search" }
            }
        }

        Rectangle {
            id: terminal
            objectName: "previewTerminal"
            width: desktop.width * Theme.desktopPreview.terminal.width
            x: desktop.placeX(Theme.desktopPreview.terminal.x, width)
            y: desktop.height * Theme.desktopPreview.terminal.y
            height: Math.min(desktop.height * Theme.desktopPreview.terminal.height, desktop.windowBottom - y)
            radius: root.windowRadius
            color: root.terminalColor(0)
            border.color: root.inactiveBorderColor
            border.width: Math.max(Theme.border.thin, root.borderSize)
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: root.contentInset(terminal)
                spacing: Theme.desktopPreview.lineGap

                Label { role: "code"; color: root.terminalColor(2); text: "~ ❯ ls" }
                // In ls --color's default colours: an archive red, an
                // executable green, a folder blue, an image magenta, a link
                // cyan and a plain file the foreground, listed down the
                // columns in ls's order.
                Grid {
                    rows: 4
                    flow: Grid.TopToBottom
                    columnSpacing: Theme.space.xl
                    rowSpacing: Theme.desktopPreview.lineGap
                    Repeater {
                        model: [
                            { name: "backup.tar.gz", color: 1 },
                            { name: "build.sh", color: 2 },
                            { name: "Desktop", color: 4 },
                            { name: "Documents", color: 4 },
                            { name: "dotfiles", color: 6 },
                            { name: "notes.md", color: 7 },
                            { name: "Pictures", color: 4 },
                            { name: "wallpaper.jpg", color: 5 }
                        ]
                        Label {
                            required property var modelData
                            role: "code"
                            color: root.terminalColor(modelData.color)
                            text: modelData.name
                        }
                    }
                }
                Row {
                    spacing: Theme.space.sm
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            width: Theme.icon.size.xs
                            height: Theme.icon.size.xs
                            radius: Theme.radius.full
                            color: root.terminalColor(index + 8)
                        }
                    }
                }
                Label { role: "code"; color: root.terminalColor(4); text: "~ ❯ vgshell theme apply " + root.name }
                Rectangle { width: Theme.space.md; height: Theme.space.lg; color: root.terminalColor(7) }
            }
        }
    }
}
