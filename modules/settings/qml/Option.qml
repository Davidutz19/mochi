import QtQuick
import Quickshell
import qs.island

// One option: its title and description, and the control its kind calls
// for. An option changed here has a dot and, on hover, a button back to
// what the files say. A theme option goes out as it moves, at most every 50 ms; any
// other waits until it stops changing for 400 ms, since it restarts its
// module. `popup` asks the panel for a menu or the color picker, which it
// draws over everything.
//
// A text or a list whose values come from somewhere, its `source`, picks them
// from a menu, with a search and room to type another: apps, audio devices,
// tray apps, players, control center cards, modules, time zones. A command,
// like the idle clock's click, picks a module, then one of its actions, then
// its arguments. A command line with ready-made ones, like the lock, offers
// those that are installed. A file, like the timer's sound, is typed or
// picked with the desktop's file chooser. Time zones pick from the
// island's ZonePicker, with a search the keyboard moves through.
Item {
    id: root

    required property var field
    // Shown before the title while searching, like "CPU".
    property string prefix: ""
    property string error: ""
    property bool highlighted: false
    signal popup(string kind, Item anchor)
    signal editToml

    readonly property bool group: field.kind === "group"
    readonly property bool theme: field.path.startsWith("theme.")
    // Changed in the panel: the reset button takes it back to the files.
    readonly property bool modified: !group && field.changed === true
    // The value the control shows: what's on the way, or the daemon's.
    property var pending: undefined
    readonly property var value: pending !== undefined ? pending : field.value
    readonly property bool ranged: field.min !== undefined && field.max !== undefined
    readonly property string source: field.source ?? ""
    // Picked from a menu rather than typed.
    readonly property bool picks: source !== "" || (field.kind === "list" && (field.choices ?? []).length > 0)

    // Which menu the panel shows for it: its own values, or for a command
    // the module or the action, or the ready-made commands.
    property string menu: "value"
    readonly property bool multiple: menu === "value" && field.kind === "list"
    // The source of the menu open now: the field's, or a command's
    // argument's.
    readonly property string menuSource: menu === "value" ? source : menu.startsWith("arg:") ? (argAt(Number(menu.slice(4)))?.source ?? "") : ""
    readonly property bool searchable: menuSource !== "" || choices().length > 8
    // Something not in the menu may be typed too: names that change.
    readonly property bool custom: menuSource !== "" && !["module", "control-center-card", "control-center-page", "settings-section", "power-profile", "duration", "place"].includes(menuSource)
    // The menu narrows to what's typed in its search; a place search asks
    // Open-Meteo instead, whose answers needn't contain the words.
    readonly property bool filtered: menuSource !== "place"

    // Entries by name, like the launcher's web searches: a heading, then
    // each entry's options under it.
    readonly property bool map: field.kind === "map"
    // A map of plain values, like monitors' labels: one row per entry.
    readonly property bool plainMap: map && (field.entry ?? []).length === 1 && field.entry[0].path === ""

    // A nested option's menu: the panel shows it for that option.
    signal popupFrom(string kind, Item owner, Item anchor)

    // A map's entries: the ones set, and for a plain map every name its
    // source knows, like each monitor connected.
    function mapKeys(): var {
        const set = Object.keys(value ?? {});
        if (!plainMap || !field.keys)
            return set;
        const known = valuesFor(field.keys).map(choice => choice.value);
        return known.concat(set.filter(key => !known.includes(key)));
    }

    function keyLabel(key: string): string {
        return field.keys ? (valuesFor(field.keys).find(choice => choice.value === key)?.label ?? key) : key;
    }

    // One entry's option as a field of its own, at its path under the map.
    function entryField(key: string, option: var): var {
        const entry = (value ?? {})[key];
        const plain = option.path === "";
        return Object.assign({}, option, {
            "path": plain ? `${field.path}.${key}` : `${field.path}.${key}.${option.path}`,
            "title": plain ? keyLabel(key) : option.title,
            "value": (plain ? entry : entry?.[option.path]) ?? option["default"] ?? null,
            "changed": false
        });
    }

    // An entry set to what its map writes to take it out, like an engine
    // with no address.
    function entryOff(key: string): bool {
        const off = field.remove;
        const entry = (value ?? {})[key];
        if (off === undefined || off === null || typeof off !== "object" || typeof entry !== "object")
            return false;
        return Object.keys(off).every(name => entry?.[name] === off[name]);
    }

    function addKey(key: string): void {
        const name = key.trim();
        if (name === "" || (value ?? {})[name] !== undefined)
            return;
        Daemon.command("settings", "set", [`${field.path}.${name}`, "{}"]);
    }

    function removeKey(key: string): void {
        Daemon.command("settings", "set", [`${field.path}.${key}`, "null"]);
    }

    // A place search asks the weather module, a moment after typing stops.
    function searched(text: string): void {
        if (menuSource !== "place")
            return;
        placeQuery = text;
        placeSearch.restart();
    }

    property string placeQuery: ""

    Timer {
        id: placeSearch

        interval: 300
        onTriggered: Daemon.command("weather", "places", [root.placeQuery])
    }

    // "HH:MM", split for the time picker's two menus.
    readonly property var time: {
        const parts = String(value ?? field["default"] ?? "00:00").split(":");
        return [parts[0] ?? "00", parts[1] ?? "00"];
    }

    function pad(number: int): string {
        return String(number).padStart(2, "0");
    }

    // Measures choices' labels in the segments' font.
    FontMetrics {
        id: labels

        font.pixelSize: Theme.textBody
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
    }

    function openMenu(kind: string, anchor: Item): void {
        menu = kind;
        // Time zones have a picker of their own, with a search.
        popup(kind === "value" && source === "timezone" ? "zones" : "choice", anchor);
    }

    // A command's module and action, and the arguments after them.
    readonly property string commandModule: source === "command" ? ((value ?? [])[0] ?? "") : ""
    readonly property string commandAction: source === "command" ? ((value ?? [])[1] ?? "") : ""
    readonly property var commandSpec: source === "command" ? (Daemon.state("settings")?.actions?.[commandModule] ?? []).find(action => action.name === commandAction) ?? null : null
    readonly property var commandArgs: commandSpec?.args ?? []

    function argAt(index: int): var {
        return commandArgs[index] ?? null;
    }

    // What a command's argument is set to, "" when it isn't.
    function argValue(index: int): string {
        return String((value ?? [])[2 + index] ?? "");
    }

    // Sets one of a command's arguments, keeping the ones before it and
    // dropping empty ones at the end, which are optional.
    function setArg(index: int, text: string): void {
        const parts = (value ?? []).slice(0, Math.max(2, (value ?? []).length));
        while (parts.length < 2 + index + 1)
            parts.push("");
        parts[2 + index] = text;
        while (parts.length > 2 && parts[parts.length - 1] === "")
            parts.pop();
        sendNow(parts);
    }

    // The daemon's answer replaces what was on the way.
    onFieldChanged: {
        if (!sending.running && !settle.running)
            pending = undefined;
    }

    function send(value: var): void {
        sending.stop();
        settle.stop();
        Daemon.command("settings", "set", [field.path, JSON.stringify(value)]);
    }

    // For values that move, like a slider being dragged.
    function sendSoon(value: var): void {
        pending = value;
        if (theme) {
            if (!sending.running)
                sending.start();
        } else {
            settle.restart();
        }
    }

    function sendNow(value: var): void {
        pending = value;
        send(value);
    }

    Timer {
        id: sending

        interval: 50
        onTriggered: root.send(root.pending)
    }

    Timer {
        id: settle

        interval: 400
        onTriggered: root.send(root.pending)
    }

    implicitHeight: map ? heading.implicitHeight + mapEntries.implicitHeight + Theme.spaceMedium * 2 : group ? heading.implicitHeight + Theme.spaceMedium : Math.max(texts.implicitHeight, control.height) + Theme.spaceMedium * 2

    Rectangle {
        anchors.fill: parent
        visible: !root.group && !root.map
        radius: Theme.radiusField
        color: root.highlighted ? Theme.raised : hover.hovered ? Theme.surface : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
    }

    HoverHandler {
        id: hover
    }

    // A table's heading, like "CPU" over its levels.
    Column {
        id: heading

        visible: root.group || root.map
        y: Theme.spaceMedium
        x: Theme.spaceMedium
        width: parent.width - Theme.spaceMedium * 2
        spacing: Theme.spaceTiny

        Text {
            text: root.field.title
            color: Theme.foreground
            font.pixelSize: Theme.textBody
            font.family: Theme.fontFamily
            font.weight: Theme.weightTitle
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: root.field.description
            wrapMode: Text.Wrap
            color: Theme.muted
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
        }
    }

    // A map's entries, under its heading: each one's options as rows of
    // their own, and a way to add one.
    Column {
        id: mapEntries

        visible: root.map
        x: Theme.spaceMedium
        y: heading.y + heading.implicitHeight + Theme.spaceSmall
        width: parent.width - Theme.spaceMedium * 2
        spacing: Theme.spaceSmall

        Text {
            visible: root.map && !root.plainMap && root.mapKeys().length === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "None yet."
            color: Theme.muted
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
        }

        Repeater {
            model: root.map ? root.mapKeys() : []

            Rectangle {
                id: entryBlock

                required property string modelData
                readonly property string key: modelData

                width: mapEntries.width
                height: entryColumn.implicitHeight
                radius: Theme.radiusField
                color: root.plainMap ? "transparent" : Theme.surface

                Column {
                    id: entryColumn

                    width: parent.width

                    // The entry's name, and taking it out.
                    Item {
                        visible: !root.plainMap
                        width: parent.width
                        height: Theme.rowHeight

                        Text {
                            x: Theme.spaceMedium
                            anchors.verticalCenter: parent.verticalCenter
                            // Taken out while the file still has it: off.
                            text: root.entryOff(entryBlock.key) ? `${root.keyLabel(entryBlock.key)} · Off` : root.keyLabel(entryBlock.key)
                            color: Theme.foreground
                            font.pixelSize: Theme.textBody
                            font.family: Theme.fontFamily
                            font.weight: Theme.weightTitle
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spaceMedium
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "close"
                            size: 14
                            tone: "neutral"
                            onClicked: root.removeKey(entryBlock.key)
                        }
                    }

                    Repeater {
                        model: root.field.entry ?? []

                        // Option is this file: a nested one loads by name.
                        Loader {
                            id: nested

                            required property var modelData

                            width: entryColumn.width
                            Component.onCompleted: setSource("Option.qml", {
                                "field": root.entryField(entryBlock.key, modelData)
                            })
                            onLoaded: {
                                item.popup.connect((kind, anchor) => root.popupFrom(kind, item, anchor));
                                item.popupFrom.connect(root.popupFrom);
                            }

                            Binding {
                                target: nested.item
                                property: "field"
                                value: root.entryField(entryBlock.key, nested.modelData)
                                when: nested.item !== null
                            }
                        }
                    }
                }
            }
        }

        // Adds an entry: one the source knows, or one typed.
        Row {
            visible: root.map && !root.plainMap
            spacing: Theme.spaceSmall

            DropButton {
                id: addButton

                visible: (root.field.keys ?? "") !== ""
                text: "Add…"
                onClicked: root.openMenu("key", addButton)
            }

            Entry {
                width: 240
                placeholder: (root.field.keys ?? "") !== "" ? "Or a new one, by name" : "Add one, by name"
                onAccepted: name => {
                    root.addKey(name);
                    clear();
                }
            }
        }
    }

    Column {
        id: texts

        visible: !root.group && !root.map
        x: Theme.spaceMedium
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - Theme.spaceMedium * 2 - controls.width
        spacing: 2

        Row {
            spacing: Theme.spaceSmall

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.modified
                width: 6
                height: 6
                radius: width / 2
                color: Theme.accent
            }

            Text {
                text: root.prefix !== "" ? `${root.prefix} › ${root.field.title}` : root.field.title
                color: Theme.foreground
                font.pixelSize: Theme.textBody
                font.family: Theme.fontFamily
                font.weight: Theme.weightLabel
            }
        }

        Text {
            visible: text !== ""
            width: parent.width
            text: root.field.description
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            color: Theme.muted
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
        }

        Text {
            visible: root.error !== ""
            width: parent.width
            text: root.error
            wrapMode: Text.Wrap
            color: Theme.danger
            font.pixelSize: Theme.textCaption
            font.family: Theme.fontFamily
        }
    }

    Row {
        id: controls

        visible: !root.group && !root.map
        anchors.right: parent.right
        anchors.rightMargin: Theme.spaceMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceSmall

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.modified
            opacity: hover.hovered ? 1 : 0
            icon: "restart_alt"
            size: 16
            onClicked: Daemon.command("settings", "reset", [root.field.path])
        }

        Loader {
            id: control

            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: {
                switch (root.field.kind) {
                case "bool":
                    return toggleControl;
                case "choice":
                    return root.field.choices.length <= 4 && root.field.choices.every(choice => choice.value.length <= 10) ? segmentsControl : dropdownControl;
                case "int":
                case "float":
                    return root.ranged ? sliderControl : numberControl;
                case "color":
                    return colorControl;
                case "font":
                    return fontControl;
                case "list":
                    return root.source === "command" ? commandControl : listControl;
                case "text":
                    if (root.field.format === "time")
                        return timeControl;
                    if ((root.field.suggestions ?? []).length > 0)
                        return presetControl;
                    return root.source === "file" ? fileControl : root.source !== "" ? pickControl : textControl;
                case "map":
                    return null;
                default:
                    return tableControl;
                }
            }
        }
    }

    // "focus" reads "Focus", "center-left" "Center left".
    function label(value: string): string {
        if (value === "")
            return "Auto";
        const words = value.replace(/[-_]/g, " ");
        return words.charAt(0).toUpperCase() + words.slice(1);
    }

    // The values a source offers now, as {value, label, detail, icon}.
    function sourceChoices(): var {
        return valuesFor(source);
    }

    function valuesFor(source: string): var {
        const named = (items, detail) => items.map(name => ({
                        "value": name,
                        "label": name,
                        "detail": detail ?? ""
                    }));
        switch (source) {
        case "duration":
            // Lengths a timer is set for, as "5m" or "1h 30m".
            return ["1m", "2m", "3m", "5m", "10m", "15m", "20m", "25m", "30m", "45m", "1h", "1h 30m", "2h", "3h"].map(length => ({
                        "value": length,
                        "label": length.replace("h", " h").replace("m", " min").replace(/\s+/g, " ").trim()
                    }));
        case "place":
            // What the weather module found for the search typed last.
            return Daemon.state("weather")?.places ?? [];
        case "launcher-provider":
            return [["apps", "Apps"], ["calculator", "Calculator"], ["commands", "Commands"], ["files", "Files"]].map(([value, label]) => ({
                        "value": value,
                        "label": label
                    })).concat(Daemon.offered("launcher", "provider").map(offer => ({
                        "value": offer.id,
                        "label": offer.title,
                        "detail": label(offer.module)
                    })));
        case "output":
            return Quickshell.screens.map(screen => screen.name).filter(name => !name.startsWith("MOCHI-")).map(name => ({
                        "value": name,
                        "label": name,
                        "detail": Quickshell.screens.find(screen => screen.name === name)?.model ?? ""
                    }));
        case "control-center-page":
            return Daemon.offered("control-center", "page").map(page => ({
                        "value": `${page.module}/${page.id}`,
                        "label": page.title,
                        "detail": `${page.module}/${page.id}`,
                        "icon": page.icon
                    }));
        case "audio-output":
            return (Daemon.state("audio")?.outputs ?? []).map(device => ({
                        "value": device.name,
                        "label": device.description,
                        "detail": device.name
                    }));
        case "audio-input":
            return (Daemon.state("audio")?.inputs ?? []).map(device => ({
                        "value": device.name,
                        "label": device.description,
                        "detail": device.name
                    }));
        case "audio-app":
            return named((Daemon.state("audio")?.apps ?? []).map(app => app.name), "Playing now");
        case "audio-target":
            return [
                {
                    "value": "output",
                    "label": "Output",
                    "detail": "The output in use"
                },
                {
                    "value": "input",
                    "label": "Input",
                    "detail": "The microphone in use"
                }
            ].concat(valuesFor("audio-output"), valuesFor("audio-input"), valuesFor("audio-app"), (Daemon.state("audio")?.recorders ?? []).map(app => ({
                        "value": app.target,
                        "label": app.name,
                        "detail": "Recording now"
                    })));
        case "bluetooth-device":
            {
                const bluetooth = Daemon.state("bluetooth");
                return (bluetooth?.paired ?? []).concat(bluetooth?.found ?? []).map(device => ({
                            "value": device.name,
                            "label": device.name,
                            "detail": device.address ?? "",
                            "icon": device.icon
                        }));
            }
        case "brightness-display":
            return [
                {
                    "value": "all",
                    "label": "All",
                    "detail": "Every display"
                },
                {
                    "value": "backlight",
                    "label": "Backlight",
                    "detail": "The laptop's screen"
                },
                {
                    "value": "external",
                    "label": "External",
                    "detail": "Monitors over DDC/CI"
                },
                {
                    "value": "keyboard",
                    "label": "Keyboard",
                    "detail": "The keyboard's backlight"
                }
            ].concat((Daemon.state("brightness")?.displays ?? []).filter(display => display.id !== "backlight").map(display => ({
                        "value": display.id,
                        "label": display.name,
                        "detail": display.id
                    })));
        case "desktop-id":
            return valuesFor("app").map(app => Object.assign({}, app, {
                    "value": `${app.value}.desktop`
                }));
        case "power-profile":
            return named(Daemon.state("power")?.profiles ?? []);
        case "settings-section":
            return (Daemon.state("settings")?.sections ?? []).map(section => ({
                        "value": section.id,
                        "label": section.title,
                        "icon": section.icon
                    }));
        case "wifi-network":
            {
                const network = Daemon.state("network");
                return (network?.networks ?? []).map(wifi => ({
                            "value": wifi.ssid,
                            "label": wifi.ssid,
                            "detail": wifi.saved ? "Saved" : "In range"
                        })).concat((network?.vpns ?? []).map(vpn => ({
                            "value": vpn.id,
                            "label": vpn.id,
                            "detail": "VPN"
                        })));
            }
        case "vpn":
            return (Daemon.state("network")?.vpns ?? []).map(vpn => ({
                        "value": vpn.id,
                        "label": vpn.id
                    }));
        case "module":
            return (Daemon.state("settings")?.modules ?? []).map(module => ({
                        "value": module.id,
                        "label": module.title,
                        "icon": module.icon
                    }));
        case "app":
            return DesktopEntries.applications.values.filter(entry => !entry.noDisplay).map(entry => ({
                        "value": entry.id.replace(/\.desktop$/, ""),
                        "label": entry.name,
                        "detail": entry.id.replace(/\.desktop$/, ""),
                        "icon": entry.icon
                    })).sort((a, b) => a.label.localeCompare(b.label));
        case "audio-device":
            {
                const audio = Daemon.state("audio");
                return [
                    {
                        "value": "default_output",
                        "label": "Default output",
                        "detail": "What the speakers play"
                    },
                    {
                        "value": "default_input",
                        "label": "Default input",
                        "detail": "The microphone in use"
                    }
                ].concat((audio?.outputs ?? []).map(output => ({
                            "value": `${output.name}.monitor`,
                            "label": output.description,
                            "detail": "What it plays"
                        }))).concat((audio?.inputs ?? []).map(input => ({
                            "value": input.name,
                            "label": input.description,
                            "detail": "Microphone"
                        })));
            }
        case "tray-app":
            return (Daemon.state("tray")?.apps ?? []).map(app => ({
                        "value": app.id,
                        "label": app.title,
                        "detail": app.id,
                        "icon": app.icon
                    }));
        case "timezone":
            // Read when the panel opens, west to east, like "Tokyo, Asia"
            // with "UTC+9 · Japan" under it.
            return Daemon.state("settings")?.timezones ?? [];
        case "sound-theme":
            return Daemon.state("notifications")?.soundThemes ?? [];
        case "pam-service":
            // The ones installed here that a lock screen can use.
            return Daemon.state("lock")?.services ?? [];
        case "player":
            return (Daemon.state("media")?.players ?? []).map(player => ({
                        "value": player.name,
                        "label": player.name
                    }));
        case "control-center-card":
            return Daemon.offered("control-center", "card").map(card => ({
                        "value": `${card.module}/${card.id}`,
                        "label": card.title,
                        "detail": card.module,
                        "icon": card.icon
                    }));
        }
        return [];
    }

    // What a value reads as: its label in the menu, or itself.
    function labelFor(value: var): string {
        const text = String(value);
        const found = (source !== "" ? sourceChoices() : choices()).find(choice => choice.value === text);
        return found?.label ?? text;
    }

    function choices(): var {
        return choicesFor(menu);
    }

    // The values of the menu `menu` names.
    function choicesFor(menu: string): var {
        switch (menu) {
        case "module":
            return Object.keys(Daemon.state("settings")?.actions ?? {}).filter(module => (Daemon.state("settings").actions[module] ?? []).length > 0).sort().map(module => ({
                        "value": module,
                        "label": label(module)
                    }));
        case "action":
            return (Daemon.state("settings")?.actions?.[commandModule] ?? []).map(action => ({
                        "value": action.name,
                        "label": action.name,
                        "detail": action.help ?? action.description ?? ""
                    }));
        case "suggest":
            // Commands, plain values, or values with a label of their own.
            return (field.suggestions ?? []).map(suggestion => Array.isArray(suggestion) ? {
                    "value": JSON.stringify(suggestion),
                    "label": suggestion.join(" ")
                } : typeof suggestion === "object" ? {
                    "value": JSON.stringify(suggestion.value),
                    "label": suggestion.label ?? String(suggestion.value),
                    "detail": String(suggestion.value)
                } : {
                    "value": JSON.stringify(suggestion),
                    "label": String(suggestion)
                });
        case "key":
            // A map's names its source knows that aren't set yet.
            return valuesFor(field.keys ?? "").filter(choice => (value ?? {})[choice.value] === undefined);
        case "hour":
            return [...Array(24).keys()].map(hour => ({
                        "value": pad(hour),
                        "label": pad(hour)
                    }));
        case "minute":
            return [...Array(12).keys()].map(step => ({
                        "value": pad(step * 5),
                        "label": pad(step * 5)
                    }));
        }
        if (menu.startsWith("arg:")) {
            const arg = argAt(Number(menu.slice(4)));
            const values = arg?.kind?.type === "choice" ? (arg.kind.values ?? []).map(word => ({
                        "value": word,
                        "label": word
                    })) : valuesFor(arg?.source ?? "");
            // An optional one may be left out.
            return arg?.optional ? [
                {
                    "value": "",
                    "label": "Leave out",
                    "detail": "Its default"
                }
            ].concat(values) : values;
        }
        if (source !== "")
            return sourceChoices();
        const options = (root.field.choices ?? []).map(choice => ({
                    "value": choice.value,
                    "label": choice.label ?? label(choice.value),
                    "colors": choice.colors ?? []
                }));
        return root.field.optional ? [
            {
                "value": "",
                "label": "Auto"
            }
        ].concat(options) : options;
    }

    function isPicked(choice: string): bool {
        switch (menu) {
        case "module":
            return commandModule === choice;
        case "action":
            return commandAction === choice;
        case "suggest":
            return JSON.stringify(value ?? []) === choice;
        case "key":
            return false;
        case "hour":
            return time[0] === choice;
        case "minute":
            return time[1] === choice;
        }
        if (menu.startsWith("arg:"))
            return argValue(Number(menu.slice(4))) === choice;
        if (multiple)
            return (value ?? []).map(String).includes(choice);
        return (value ?? "") === choice;
    }

    // A menu's choice: a list gains or loses it and the menu stays; the
    // rest set it.
    function pick(choice: string): void {
        switch (menu) {
        case "module":
            sendNow(choice === commandModule ? value : [choice]);
            return;
        case "action":
            sendNow([commandModule, choice]);
            return;
        case "suggest":
            sendNow(JSON.parse(choice));
            return;
        case "key":
            addKey(choice);
            return;
        case "hour":
            sendNow(`${choice}:${time[1]}`);
            return;
        case "minute":
            sendNow(`${time[0]}:${choice}`);
            return;
        }
        if (menu.startsWith("arg:")) {
            setArg(Number(menu.slice(4)), choice);
            return;
        }
        if (multiple) {
            const items = (value ?? []).slice();
            const at = items.map(String).indexOf(choice);
            if (at >= 0)
                items.splice(at, 1);
            else
                items.push(field.items === "int" || field.items === "float" ? Number(choice) : choice);
            sendNow(items);
            return;
        }
        sendNow(choice === "" ? null : choice);
    }

    Component {
        id: toggleControl

        Switch {
            checked: root.value === true
            onToggled: checked => root.sendNow(checked)
        }
    }

    Component {
        id: segmentsControl

        Segmented {
            // Each as wide as the widest label needs, like "Foreground",
            // and at least 76.
            width: root.choices().length * Math.max(76, Math.max(...root.choices().map(choice => labels.advanceWidth(choice.label ?? ""))) + Theme.spaceLarge * 2)
            height: Theme.controlHeight
            options: root.choices()
            current: root.value ?? ""
            onPicked: value => root.sendNow(value === "" ? null : value)
        }
    }

    Component {
        id: dropdownControl

        Rectangle {
            id: button

            width: 180
            height: Theme.controlHeight
            radius: height / 2
            color: pick.containsMouse ? Theme.highlight : Theme.raised

            Text {
                x: Theme.spaceMedium
                anchors.verticalCenter: parent.verticalCenter
                text: root.label(root.value ?? "")
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
                id: pick

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openMenu("value", button)
            }
        }
    }

    // The font's name, in that font.
    Component {
        id: fontControl

        Rectangle {
            id: button

            readonly property string family: root.value ?? ""

            width: 240
            height: Theme.controlHeight
            radius: height / 2
            color: fontArea.containsMouse ? Theme.highlight : Theme.raised

            Text {
                x: Theme.spaceMedium
                width: parent.width - x - Theme.spaceHuge
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: button.family !== "" ? button.family : "Default"
                color: button.family !== "" && !Fonts.has(button.family) ? Theme.danger : Theme.foreground
                font.pixelSize: Theme.textBody
                font.family: button.family !== "" ? button.family : Theme.fontFamily
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
                id: fontArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.popup("font", button)
            }
        }
    }

    Component {
        id: sliderControl

        Row {
            spacing: Theme.spaceSmall

            readonly property real span: root.field.max - root.field.min

            Slider {
                id: bar

                anchors.verticalCenter: parent.verticalCenter
                width: 160
                thickness: 4
                fill: Theme.accent
                value: ((root.value ?? root.field.min) - root.field.min) / parent.span
                // A double click goes back to what the files say.
                reset: ((root.field.saved ?? root.field["default"] ?? root.field.min) - root.field.min) / parent.span
                onMoved: value => root.sendSoon(parent.snap(value))
                onReleased: value => root.sendNow(parent.snap(value))
            }

            function snap(fraction: real): var {
                const value = root.field.min + fraction * span;
                return root.field.kind === "int" ? Math.round(value) : Math.round(value * 100) / 100;
            }

            Entry {
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                text: String(root.value ?? "")
                horizontalAlignment: TextInput.AlignRight
                onAccepted: text => root.typed(text)
            }
        }
    }

    // A number typed in, kept if it is one.
    function typed(text: string): void {
        const number = Number(text.trim());
        if (text.trim() === "" && root.field.optional)
            sendNow(null);
        else if (!Number.isNaN(number))
            sendNow(root.field.kind === "int" ? Math.round(number) : number);
    }

    // Steps of about a tenth of the default: 100 for 1500 ms, 1 for 50.
    readonly property real step: {
        const base = Math.abs(field["default"] ?? 0);
        if (field.kind === "float")
            return base >= 10 ? 1 : 0.1;
        return base >= 100 ? Math.pow(10, Math.floor(Math.log10(base)) - 1) : 1;
    }

    Component {
        id: numberControl

        Row {
            spacing: Theme.spaceTiny

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "remove"
                size: 14
                onClicked: {
                    const next = (root.value ?? 0) - root.step;
                    root.sendSoon(Math.max(root.field.min ?? -Infinity, Math.round(next * 100) / 100));
                }
            }

            Entry {
                anchors.verticalCenter: parent.verticalCenter
                width: 84
                text: root.value === null || root.value === undefined ? "" : String(root.value)
                placeholder: root.field.optional ? "Auto" : ""
                horizontalAlignment: TextInput.AlignHCenter
                onAccepted: text => root.typed(text)
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"
                size: 14
                onClicked: {
                    const next = (root.value ?? 0) + root.step;
                    root.sendSoon(Math.min(root.field.max ?? Infinity, Math.round(next * 100) / 100));
                }
            }
        }
    }

    Component {
        id: textControl

        Entry {
            width: 240
            text: root.value ?? ""
            placeholder: root.field["default"] === "" ? "Default" : ""
            onAccepted: text => root.sendNow(text)
        }
    }

    // A time of day: an hour and a minute, each from a menu.
    Component {
        id: timeControl

        Row {
            spacing: Theme.spaceTiny

            DropButton {
                id: hourButton

                width: 76
                text: root.time[0]
                onClicked: root.openMenu("hour", hourButton)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ":"
                color: Theme.muted
                font.pixelSize: Theme.textBody
                font.family: Theme.fontFamily
            }

            DropButton {
                id: minuteButton

                width: 76
                text: root.time[1]
                onClicked: root.openMenu("minute", minuteButton)
            }
        }
    }

    // A text with ready-made values, like a time format: picked from a
    // menu that says what each looks like, or typed.
    Component {
        id: presetControl

        Column {
            width: 240
            spacing: Theme.spaceTiny

            DropButton {
                id: presetButton

                width: parent.width
                text: {
                    const shown = root.choicesFor("suggest").find(choice => choice.value === JSON.stringify(root.value ?? ""));
                    return shown?.label ?? "Your own";
                }
                onClicked: root.openMenu("suggest", presetButton)
            }

            Entry {
                width: parent.width
                text: root.value ?? ""
                placeholder: "Or type your own"
                onAccepted: text => root.sendNow(text)
            }
        }
    }

    // A file's path, typed, or picked with the desktop's file chooser,
    // which the settings module opens and sets the option from. The
    // button says so while the chooser is open; pressing it again opens
    // another, in case the first went behind a window.
    Component {
        id: fileControl

        Row {
            readonly property bool choosing: Daemon.state("settings")?.choosing === root.field.path

            spacing: Theme.spaceSmall

            Entry {
                anchors.verticalCenter: parent.verticalCenter
                width: 200
                text: root.value ?? ""
                placeholder: root.field["default"] === "" ? "Default" : ""
                onAccepted: text => root.sendNow(text.trim())
            }

            ActionButton {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.choosing ? "Choosing…" : "Choose…"
                icon: "folder_open"
                onClicked: Daemon.command("settings", "choose-file", [root.field.path])
            }
        }
    }

    Component {
        id: colorControl

        Row {
            spacing: Theme.spaceSmall

            Rectangle {
                id: swatch

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.controlHeight
                height: Theme.controlHeight
                radius: Theme.radiusControl
                color: root.value ?? "transparent"
                border.width: 1
                border.color: Theme.highlight

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.popup("color", swatch)
                }
            }

            Entry {
                anchors.verticalCenter: parent.verticalCenter
                width: 110
                mono: true
                text: root.value ?? ""
                onAccepted: text => root.sendNow(text.trim())
            }
        }
    }

    Component {
        id: listControl

        Column {
            width: 280
            spacing: Theme.spaceTiny

            Flow {
                width: parent.width
                spacing: Theme.spaceTiny

                Repeater {
                    model: root.value ?? []

                    Rectangle {
                        id: chip

                        required property var modelData
                        required property int index

                        width: chipText.implicitWidth + remove.width + Theme.spaceSmall * 2
                        height: 26
                        radius: height / 2
                        color: Theme.raised

                        Text {
                            id: chipText

                            x: Theme.spaceSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labelFor(chip.modelData)
                            color: Theme.foreground
                            font.pixelSize: Theme.textCaption
                            font.family: Theme.fontFamily
                        }

                        IconButton {
                            id: remove

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "close"
                            size: 12
                            onClicked: {
                                const items = (root.value ?? []).slice();
                                items.splice(chip.index, 1);
                                root.sendNow(items);
                            }
                        }
                    }
                }
            }

            // Values from the menu, several at a time.
            DropButton {
                id: menuButton1

                visible: root.picks && root.source !== "file"
                width: parent.width
                text: "Add…"
                onClicked: root.openMenu("value", menuButton1)
            }

            // Ready-made commands, the installed ones.
            DropButton {
                id: menuButton2

                visible: (root.field.suggestions ?? []).length > 0
                width: parent.width
                text: "Pick a ready-made one…"
                onClicked: root.openMenu("suggest", menuButton2)
            }

            // Paths, from the desktop's chooser: a folder, or a file.
            ActionButton {
                visible: root.source === "file"
                text: Daemon.state("settings")?.choosing === root.field.path ? "Choosing…" : root.field.filter === "folder" ? "Add a folder…" : "Add a file…"
                icon: "folder_open"
                onClicked: Daemon.command("settings", "choose-file", [root.field.path])
            }

            Entry {
                visible: !root.picks || root.source === "file"
                width: parent.width
                placeholder: (root.field.suggestions ?? []).length > 0 ? "Or type a word…" : "Add…"
                onAccepted: added => {
                    const item = added.trim();
                    clear();
                    if (item === "")
                        return;
                    const number = Number(item);
                    const numeric = root.field.items === "int" || root.field.items === "float";
                    if (numeric && Number.isNaN(number))
                        return;
                    root.sendNow((root.value ?? []).concat([numeric ? number : item]));
                }
            }
        }
    }

    // A button that opens a menu: its text, and a chevron.
    component DropButton: Rectangle {
        id: drop

        property string text: ""
        property bool muted: false
        signal clicked

        width: 180
        height: Theme.controlHeight
        radius: height / 2
        color: dropArea.containsMouse ? Theme.highlight : Theme.raised
        opacity: enabled ? 1 : 0.4

        Text {
            x: Theme.spaceMedium
            width: parent.width - x - Theme.spaceHuge
            anchors.verticalCenter: parent.verticalCenter
            text: drop.text
            elide: Text.ElideRight
            color: drop.muted ? Theme.muted : Theme.foreground
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
            id: dropArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: drop.clicked()
        }
    }

    // One value from a source, or typed in the menu's search.
    Component {
        id: pickControl

        DropButton {
            id: menuButton3

            width: 240
            text: root.value ? root.labelFor(root.value) : root.source === "place" ? "Search for a place…" : root.field.optional || root.field["default"] === "" ? "Default" : "Choose…"
            muted: !root.value
            onClicked: root.openMenu("value", menuButton3)
        }
    }

    // A command: a module, one of its actions, then the action's arguments.
    Component {
        id: commandControl

        Column {
            width: 280
            spacing: Theme.spaceTiny

            Row {
                spacing: Theme.spaceTiny

                DropButton {
                    id: menuButton4

                    width: 120
                    text: root.commandModule !== "" ? root.label(root.commandModule) : "Nothing"
                    muted: root.commandModule === ""
                    onClicked: root.openMenu("module", menuButton4)
                }

                DropButton {
                    id: menuButton5

                    width: 128
                    enabled: root.commandModule !== ""
                    text: root.commandAction !== "" ? root.commandAction : "Action…"
                    muted: root.commandAction === ""
                    onClicked: root.openMenu("action", menuButton5)
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.value ?? []).length > 0
                    icon: "close"
                    size: 14
                    onClicked: root.sendNow([])
                }
            }

            // What the action takes, one row each: a menu for a choice
            // or for values Mochi knows, a field for the rest.
            Repeater {
                model: root.commandArgs

                Row {
                    id: argRow

                    required property var modelData
                    required property int index
                    readonly property string kind: modelData.kind?.type ?? "string"
                    readonly property bool menuArg: kind === "choice" || (modelData.source ?? "") !== ""

                    spacing: Theme.spaceSmall

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        text: argRow.modelData.optional ? `${argRow.modelData.name}?` : argRow.modelData.name
                        elide: Text.ElideRight
                        color: Theme.muted
                        font.pixelSize: Theme.textCaption
                        font.family: Theme.fontFamily
                    }

                    DropButton {
                        id: argMenu

                        visible: argRow.menuArg
                        width: 200
                        text: {
                            const current = root.argValue(argRow.index);
                            if (current === "")
                                return argRow.modelData.optional ? "Default" : "Choose…";
                            const found = root.valuesFor(argRow.modelData.source ?? "").find(choice => choice.value === current);
                            return found?.label ?? current;
                        }
                        muted: root.argValue(argRow.index) === ""
                        onClicked: root.openMenu(`arg:${argRow.index}`, argMenu)
                    }

                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: argRow.kind === "bool"
                        checked: ["on", "true", "yes"].includes(root.argValue(argRow.index))
                        onToggled: checked => root.setArg(argRow.index, checked ? "on" : "off")
                    }

                    Entry {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !argRow.menuArg && argRow.kind !== "bool"
                        width: 200
                        text: root.argValue(argRow.index)
                        placeholder: argRow.modelData.help ?? ""
                        horizontalAlignment: argRow.kind === "int" || argRow.kind === "float" ? TextInput.AlignRight : TextInput.AlignLeft
                        onAccepted: text => {
                            const trimmed = text.trim();
                            const numeric = argRow.kind === "int" || argRow.kind === "float";
                            if (numeric && trimmed !== "" && Number.isNaN(Number(trimmed.replace(/^\+/, ""))))
                                return;
                            root.setArg(argRow.index, trimmed);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: tableControl

        Button {
            text: "Edit as TOML"
            icon: "code"
            onClicked: root.editToml()
        }
    }
}
