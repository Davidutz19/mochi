import QtQuick
import qs.island

// The bubble editor at the top of the Bubbles page. Every running module
// that shows bubbles is a chip in the area its bubbles go, the five areas
// left to right as along the screen's edge, with the island where it sits.
// Dragging a chip sorts it, moves it to another area, or hides it in the
// tray under the edge; the arrow keys do the same for the chip with the
// focus. Clicking one shows its options under the edge. Every change goes
// to `[bubbles.<module>]` through the settings' `arrange` action.
Item {
    id: root

    // Asks the panel for the menu of `owner`, under `anchor`.
    signal popup(Item owner, Item anchor)

    readonly property var settings: Daemon.state("settings") ?? ({})
    readonly property var areas: ["left", "center-left", "center", "center-right", "right"]
    readonly property var names: ({
            "left": "Left",
            "center-left": "Center left",
            "center": "Center",
            "center-right": "Center right",
            "right": "Right"
        })

    // A chip per enabled module that has bubbles: one that says where they
    // go, one showing some now, or one the user placed. Sorted as the
    // bubbles are: by order, then by name.
    readonly property var chips: {
        const placements = settings.placements ?? {};
        const live = {};
        for (const bubble of Daemon.bubbles)
            live[bubble.module] = live[bubble.module] ?? bubble;
        const out = [];
        for (const module of settings.modules ?? []) {
            if (!module.enabled)
                continue;
            const home = module.bubbles ?? null;
            const placed = placements[module.id] ?? null;
            const showing = live[module.id] ?? null;
            if (!home && !placed && !showing)
                continue;
            const area = placed?.area ?? home?.area ?? showing?.area ?? "right";
            out.push({
                "id": module.id,
                "title": module.title,
                "icon": module.icon,
                "home": home,
                "area": area,
                "order": placed?.order ?? home?.order ?? 0,
                "shown": placed?.show !== false,
                "group": placed?.group ?? home?.group ?? null,
                "wide": placed?.wide === true,
                "hasWide": home?.wide === true || showing?.wide === true,
                "merge": placed?.merge !== false,
                "live": showing !== null
            });
        }
        return out.sort((a, b) => a.order - b.order || a.title.localeCompare(b.title));
    }
    readonly property var hidden: chips.filter(chip => !chip.shown)

    // The chip whose options show, and the one to give the focus back to
    // once a change rebuilds the chips.
    property string selected: ""
    property string focusId: ""
    readonly property var current: chips.find(chip => chip.id === selected) ?? null

    function inArea(area: string): var {
        return chips.filter(chip => chip.shown && chip.area === area);
    }

    function arrange(placements: var): void {
        Daemon.command("settings", "arrange", [JSON.stringify(placements)]);
    }

    // Puts `id` at `index` among `area`'s chips, shown, and numbers the
    // area's chips in their new order.
    function place(id: string, area: string, index: int): void {
        const chip = chips.find(entry => entry.id === id);
        const list = inArea(area).filter(entry => entry.id !== id).map(entry => entry.id);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, id);
        const placements = {};
        list.forEach((module, at) => placements[module] = {
                "order": at
            });
        // Back home, the area needs no setting of its own.
        placements[id].area = area === chip?.home?.area ? null : area;
        placements[id].show = null;
        arrange(placements);
    }

    function setHidden(id: string, hide: bool): void {
        const placements = {};
        placements[id] = {
            "show": hide ? false : null
        };
        arrange(placements);
    }

    function set(id: string, key: string, value: var): void {
        const placements = {};
        placements[id] = {};
        placements[id][key] = value;
        arrange(placements);
    }

    // One step left or right among its area's chips, and past the ends
    // into the next area.
    function step(id: string, by: int, acrossAreas: bool): void {
        const chip = chips.find(entry => entry.id === id);
        if (!chip)
            return;
        focusId = id;
        if (!chip.shown) {
            place(id, chip.area, inArea(chip.area).length);
            return;
        }
        const list = inArea(chip.area);
        const at = list.findIndex(entry => entry.id === id);
        const next = at + by;
        if (!acrossAreas && next >= 0 && next < list.length) {
            place(id, chip.area, next);
            return;
        }
        const area = areas[areas.indexOf(chip.area) + by];
        if (area)
            place(id, area, by < 0 ? inArea(area).length : 0);
    }

    // Where a dragged chip lands: an area and a place in it, or the tray.
    // What a point in the editor is over: the tray, the area nearest to it
    // along the edge, or nothing.
    function target(point: point): Item {
        const inTray = tray.mapFromItem(root, point.x, point.y);
        if (inTray.y >= 0 && inTray.y <= tray.height)
            return tray;
        const onEdge = edge.mapFromItem(root, point.x, point.y);
        if (onEdge.y < -Theme.spaceHuge || onEdge.y > edge.height + Theme.spaceSmall)
            return null;
        let nearest = null;
        let distance = Infinity;
        for (let index = 0; index < zones.count; index++) {
            const zone = zones.itemAt(index);
            const middle = zone.x + zone.width / 2;
            if (Math.abs(onEdge.x - middle) < distance) {
                distance = Math.abs(onEdge.x - middle);
                nearest = zone;
            }
        }
        return nearest;
    }

    function drop(id: string, point: point): void {
        const over = target(point);
        if (over === tray) {
            setHidden(id, true);
        } else if (over !== null) {
            const zone = over;
            const at = zone.mapFromItem(root, point.x, point.y);
            // Before every chip whose middle comes after the point, reading
            // left to right and row by row.
            const others = zone.chipItems().filter(item => item.chip.id !== id);
            let before = 0;
            for (const item of others) {
                const middle = item.mapToItem(zone, item.width / 2, item.height / 2);
                const sameRow = Math.abs(middle.y - at.y) <= item.height / 2;
                if (middle.y < at.y - item.height / 2 || (sameRow && middle.x < at.x))
                    before += 1;
            }
            place(id, zone.area, before);
        }
    }

    implicitHeight: body.implicitHeight

    Column {
        id: body

        width: parent.width
        spacing: Theme.spaceMedium

        // The edge: five areas side by side, the island in its own.
        Row {
            id: edge

            width: parent.width
            spacing: Theme.spaceSmall

            Repeater {
                id: zones

                model: root.areas

                Rectangle {
                    id: zone

                    required property string modelData
                    required property int index
                    readonly property string area: modelData
                    readonly property bool hostsIsland: Theme.islandArea === area
                    // The island sits at the screen's edge in the side areas and
                    // next to the center otherwise, as in BubbleArea.
                    readonly property bool islandAtEnd: area === "center-left" || area === "right"

                    function chipItems(): var {
                        const items = [];
                        for (let at = 0; at < placedChips.count; at++)
                            items.push(placedChips.itemAt(at));
                        return items.filter(item => item !== null);
                    }

                    width: (edge.width - edge.spacing * (root.areas.length - 1)) / root.areas.length
                    height: Math.max(edge.tallest, zoneColumn.implicitHeight + Theme.spaceSmall * 2)
                    radius: Theme.radiusControl
                    color: Theme.surface
                    border.width: dropping.active && dropping.zone === zone ? 2 : 0
                    border.color: Theme.foreground

                    Column {
                        id: zoneColumn

                        x: Theme.spaceSmall
                        y: Theme.spaceSmall
                        width: parent.width - Theme.spaceSmall * 2
                        spacing: Theme.spaceSmall
                        onImplicitHeightChanged: edge.measure()

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.names[zone.area]
                            color: Theme.muted
                            font.pixelSize: Theme.textCaption
                            font.family: Theme.fontFamily
                            font.weight: Theme.weightLabel
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spaceTiny
                            layoutDirection: Qt.LeftToRight

                            IslandMark {
                                visible: zone.hostsIsland && !zone.islandAtEnd
                            }

                            Repeater {
                                id: placedChips

                                model: root.inArea(zone.area)

                                Chip {}
                            }

                            IslandMark {
                                visible: zone.hostsIsland && zone.islandAtEnd
                            }
                        }
                    }
                }
            }

            // Every area as tall as the tallest.
            property real tallest: 0

            function measure(): void {
                let most = 0;
                for (let index = 0; index < zones.count; index++) {
                    const zone = zones.itemAt(index);
                    if (zone)
                        most = Math.max(most, zone.childrenRect.height + Theme.spaceSmall * 2);
                }
                tallest = most;
            }
        }

        // The tray: what's hidden, to drag back.
        Rectangle {
            id: tray

            width: parent.width
            height: trayColumn.implicitHeight + Theme.spaceSmall * 2
            radius: Theme.radiusControl
            color: "transparent"
            border.width: dropping.active && dropping.zone === tray ? 2 : 1
            border.color: dropping.active && dropping.zone === tray ? Theme.foreground : Theme.muted

            Column {
                id: trayColumn

                x: Theme.spaceSmall
                y: Theme.spaceSmall
                width: parent.width - Theme.spaceSmall * 2
                spacing: Theme.spaceSmall

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.hidden.length > 0 ? "Hidden. Drag one back to an area to show it again." : "Hidden. Drag a bubble here to stop it showing."
                    color: Theme.muted
                    font.pixelSize: Theme.textCaption
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightLabel
                }

                Flow {
                    width: parent.width
                    visible: root.hidden.length > 0
                    spacing: Theme.spaceTiny

                    Repeater {
                        model: root.hidden

                        Chip {}
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.chips.length === 0
            wrapMode: Text.Wrap
            text: "None of the running modules shows bubbles."
            color: Theme.muted
            font.pixelSize: Theme.textBody
            font.family: Theme.fontFamily
        }

        Text {
            width: parent.width
            visible: root.chips.length > 0 && root.current === null
            wrapMode: Text.Wrap
            text: "Drag a bubble to sort it or move it to another area. Click one for its options. With the keyboard, Tab to a bubble, then use the arrows to sort it, Shift and an arrow to change its area, and Delete to hide it."
            color: Theme.muted
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
        }

        // The options of the chip clicked.
        Column {
            width: parent.width
            visible: root.current !== null
            spacing: 2

            ListRow {
                width: parent.width
                height: Theme.rowHeight
                flat: true
                leadingSize: 26
                icon: root.current?.icon ?? ""
                title: root.current?.title ?? ""
                subtitle: root.current?.live ? "Showing a bubble now" : "No bubble right now; it shows one when it has something to show"

                trailing: IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    size: 14
                    tone: "neutral"
                    onClicked: root.selected = ""
                }
            }

            ListRow {
                width: parent.width
                height: Theme.rowHeight
                flat: true
                title: "Show"
                subtitle: "Off keeps its bubbles from showing, wherever they are."

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.current?.shown ?? true
                    onToggled: checked => root.setHidden(root.current.id, !checked)
                }
            }

            ListRow {
                width: parent.width
                height: Theme.rowHeight
                flat: true
                visible: root.current?.hasWide ?? false
                title: "With text"
                subtitle: "A wider pill that says what the bubble is about."

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.current?.wide ?? false
                    onToggled: checked => root.set(root.current.id, "wide", checked ? true : null)
                }
            }

            ListRow {
                width: parent.width
                height: Theme.rowHeight
                flat: true
                title: "Merge"
                subtitle: "In an area that merges its bubbles, off keeps a pill of its own beside the shape."

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.current?.merge ?? true
                    onToggled: checked => root.set(root.current.id, "merge", checked ? null : false)
                }
            }

            ListRow {
                width: parent.width
                height: Theme.rowHeight
                flat: true
                title: "Shares a pill with"
                subtitle: "Bubbles in one pill sit together, in an area that lays them apart."

                trailing: Rectangle {
                    id: pillButton

                    anchors.verticalCenter: parent.verticalCenter
                    width: 180
                    height: Theme.controlHeight
                    radius: height / 2
                    color: pillArea.containsMouse || pillButton.activeFocus ? Theme.highlight : Theme.raised
                    border.width: pillButton.activeFocus ? 2 : 0
                    border.color: Theme.foreground
                    activeFocusOnTab: true
                    Keys.onReturnPressed: root.popup(pillPicker, pillButton)
                    Keys.onSpacePressed: root.popup(pillPicker, pillButton)

                    Text {
                        x: Theme.spaceMedium
                        width: parent.width - x - Theme.spaceHuge
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: pillPicker.label
                        color: Theme.foreground
                        font.pixelSize: Theme.textBody
                        font.family: Theme.fontFamily
                    }

                    Symbol {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spaceMedium
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron"
                        rotation: 90
                        size: 12
                        color: Theme.muted
                    }

                    MouseArea {
                        id: pillArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.popup(pillPicker, pillButton)
                    }
                }
            }
        }
    }

    // What the panel's menu reads for "Shares a pill with": its own pill,
    // or any other bubble in the same area.
    Item {
        id: pillPicker

        readonly property bool multiple: false
        readonly property var others: root.current ? root.inArea(root.current.area).filter(chip => chip.id !== root.current.id) : []
        readonly property var together: root.current?.group ? others.filter(chip => chip.group === root.current.group) : []
        readonly property string label: together.length > 0 ? together.map(chip => chip.title).join(", ") : "No other"

        function choices(): var {
            return [
                {
                    "value": "",
                    "label": "No other",
                    "detail": "A pill of its own"
                }
            ].concat(others.map(chip => ({
                        "value": chip.id,
                        "label": chip.title,
                        "icon": chip.icon
                    })));
        }

        // Joins the other's pill, which takes the other's id for a group
        // when it has none.
        function pick(value: string): void {
            const id = root.current.id;
            const placements = {};
            if (value === "") {
                placements[id] = {
                    "group": root.current.home?.group ? "" : null
                };
            } else {
                const other = root.chips.find(chip => chip.id === value);
                const group = other.group || other.id;
                placements[id] = {
                    "group": group
                };
                if (other.group !== group)
                    placements[other.id] = {
                        "group": group
                    };
            }
            root.arrange(placements);
        }
    }

    // While a chip is dragged: what it is, and where it would land.
    QtObject {
        id: dropping

        property bool active: false
        property Item zone: null
    }

    // What follows the pointer while a chip is dragged.
    Rectangle {
        id: ghost

        property string icon: ""

        parent: root
        visible: dropping.active
        z: 2
        width: Theme.idleHeight
        height: Theme.idleHeight
        radius: height / 2
        color: Theme.highlight
        border.width: 1
        border.color: Theme.accent

        Symbol {
            anchors.centerIn: parent
            name: ghost.icon
            size: Theme.textTitle
            color: Theme.foreground
        }
    }

    // The island, which bubbles sit beside but can't move.
    component IslandMark: Rectangle {
        width: islandText.implicitWidth + Theme.spaceMedium * 2
        height: Theme.idleHeight
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: Theme.muted

        Text {
            id: islandText

            anchors.centerIn: parent
            text: "Island"
            color: Theme.muted
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
            font.weight: Theme.weightLabel
        }
    }

    // One module's bubbles, round like a bubble.
    component Chip: Rectangle {
        id: chipItem

        required property var modelData
        readonly property var chip: modelData
        readonly property bool dragging: dropping.active && mover.pressed

        width: Theme.idleHeight
        height: Theme.idleHeight
        radius: height / 2
        color: mover.containsMouse || activeFocus ? Theme.highlight : Theme.raised
        border.width: root.selected === chip.id ? 1 : 0
        border.color: Theme.accent
        opacity: dragging ? 0.3 : 1
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: `${chip.title}, ${chip.shown ? root.names[chip.area] : "hidden"}`

        Component.onCompleted: {
            if (root.focusId === chip.id)
                forceActiveFocus();
        }

        Keys.onPressed: event => {
            const across = (event.modifiers & Qt.ShiftModifier) !== 0;
            if (event.key === Qt.Key_Left) {
                root.step(chip.id, -1, across);
            } else if (event.key === Qt.Key_Right) {
                root.step(chip.id, 1, across);
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                root.focusId = chip.id;
                root.setHidden(chip.id, chip.shown);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.selected = root.selected === chip.id ? "" : chip.id;
            } else {
                return;
            }
            event.accepted = true;
        }

        Symbol {
            anchors.centerIn: parent
            name: chipItem.chip.icon
            size: Theme.textTitle
            color: chipItem.chip.shown ? Theme.foreground : Theme.muted
        }

        // The keyboard's focus: a ring in the text color, apart from the
        // accent outline of the chip whose options show.
        Rectangle {
            visible: chipItem.activeFocus
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.foreground
        }

        // Showing a bubble now; the options say so in words.
        Rectangle {
            visible: chipItem.chip.live
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Theme.spaceSmall
            height: Theme.spaceSmall
            radius: width / 2
            color: Theme.accent
            border.width: 1
            border.color: Theme.surface
        }

        BubbleTip {
            target: chipItem
            hovered: mover.containsMouse && !dropping.active
            text: chipItem.chip.title
        }

        MouseArea {
            id: mover

            anchors.fill: parent
            // Where the press was, in the editor, to tell a drag from a
            // click.
            property point pressedAt
            // This press became a drag, so its release isn't a click.
            property bool moved: false

            // The page under it would scroll instead of the chip moving.
            preventStealing: true
            hoverEnabled: true
            cursorShape: chipItem.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                pressedAt = mapToItem(root, mouse.x, mouse.y);
                moved = false;
                ghost.icon = chipItem.chip.icon;
                root.focusId = chipItem.chip.id;
                chipItem.forceActiveFocus();
            }
            // The ghost's middle follows the pointer, once it has gone far
            // enough to be a drag.
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const at = mapToItem(root, mouse.x, mouse.y);
                if (!dropping.active && Math.hypot(at.x - pressedAt.x, at.y - pressedAt.y) < Qt.styleHints.startDragDistance)
                    return;
                dropping.active = true;
                moved = true;
                ghost.x = at.x - ghost.width / 2;
                ghost.y = at.y - ghost.height / 2;
                dropping.zone = root.target(at);
            }
            onCanceled: {
                dropping.active = false;
                dropping.zone = null;
            }
            onReleased: mouse => {
                if (!dropping.active)
                    return;
                dropping.active = false;
                dropping.zone = null;
                root.drop(chipItem.chip.id, mapToItem(root, mouse.x, mouse.y));
            }
            onClicked: {
                if (!moved)
                    root.selected = root.selected === chipItem.chip.id ? "" : chipItem.chip.id;
            }
        }
    }
}
