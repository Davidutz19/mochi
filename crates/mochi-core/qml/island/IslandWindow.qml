import QtQuick
import Quickshell
import Quickshell.Wayland

// A fixed, transparent layer surface as tall as the screen, anchored to its
// top or bottom edge, holding five areas from left to right: left, center-left, center,
// center-right and right. The island sits in one of them and bubbles fill
// them. The surface never resizes: everything animates inside it, and the
// input mask follows the island and the pills so clicks anywhere else reach
// the windows underneath.
PanelWindow {
    id: root

    readonly property bool atBottom: Theme.anchor === "bottom"

    // 0 floating, 1 attached to the edge in notch and bar modes. Animated,
    // so switching modes morphs every shape.
    property real attached: Theme.mode === "notch" || Theme.mode === "bar" ? 1 : 0
    readonly property real margin: Theme.margin * (1 - attached)
    // 1 in bar mode: the strip fades in, and the island's and the pills'
    // own backgrounds fade out into it.
    property real barred: Theme.mode === "bar" ? 1 : 0
    // How far the side areas stay from the screen's sides: the margin, or
    // in bar mode a gap inside the bar.
    readonly property real side: margin + Theme.spaceSmall * barred

    Behavior on attached {
        NumberAnimation {
            duration: Theme.duration(350)
            easing.type: Easing.OutCubic
        }
    }

    Behavior on barred {
        NumberAnimation {
            duration: Theme.duration(350)
            easing.type: Easing.OutCubic
        }
    }

    anchors {
        top: !atBottom
        bottom: atBottom
        left: true
        right: true
    }

    // What this monitor's island shows. A modal activity, like the
    // launcher, takes the keyboard and catches every click so one outside
    // the island can close it; the daemon gives a panel to one monitor's
    // island, so two surfaces don't fight over the keyboard.
    readonly property var activity: Daemon.activityFor(screen?.name ?? "")
    readonly property bool modal: activity?.modal ?? false
    // An activity with an overlay covers every monitor and asks for the
    // keyboard on each: Hyprland only sends the pointer to surfaces holding
    // the keyboard, so an overlay without it couldn't be clicked.
    readonly property bool overlaid: activity?.overlay != null
    // Any other activity that closes on a click outside catches every click
    // too, without the keyboard: the click closes it instead of reaching
    // the window underneath. Not on a monitor that isn't showing it, and not
    // after a scroll outside released it. Nor over a fullscreen window, like
    // a game, which a notice shouldn't take clicks from: it times out.
    readonly property bool catching: (activity?.outside ?? false) && !releases(activity) && !coveredHere
    // The activity whose catch a scroll released, as {id, module, key}.
    property var released: null

    // A keyed replacement, like the media notice for the next track, stays
    // released.
    function releases(activity: var): bool {
        if (!released || !activity)
            return false;
        if (activity.id === released.id)
            return true;
        return activity.key != null && activity.module === released.module && activity.key === released.key;
    }
    // A panel open on another monitor's island: a click here closes it
    // too, as a click outside it would.
    readonly property string panelElsewhere: Daemon.focusedOutput !== null && Daemon.focusedOutput !== (screen?.name ?? "") ? Daemon.focusedOutput : ""
    readonly property bool covering: modal || overlaid || catching || panelElsewhere !== ""

    // Always the whole screen: a layer surface that changes size is animated by
    // the compositor (Hyprland's `layers` animation), which would stretch a
    // frozen screenshot. Only the input mask, the layer and the keyboard change.
    implicitHeight: screen?.height ?? Theme.surfaceHeight
    color: "transparent"

    // Windows only make room for the idle island and the bubbles, so they
    // don't move when the island grows. EdgeReserve keeps that room; this
    // window ignores reserved space, so it starts at the screen edge even
    // under another bar, and covers the whole screen for an overlay.
    readonly property int zone: Math.round(margin) + Theme.idleHeight
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "mochi-island"
    // Arranging widgets puts the desktop layer over the windows, on the top
    // layer: the island goes over it.
    readonly property bool arranging: Daemon.state("widgets")?.editing === true
    // The overlay layer draws over a fullscreen window too.
    readonly property bool overFullscreen: modal || overlaid || arranging || (activity?.over_fullscreen ?? false)
    WlrLayershell.layer: overFullscreen || lingering ? WlrLayer.Overlay : WlrLayer.Top

    // A fullscreen window hides the top layer, and the compositor may send
    // a hidden surface no frame callbacks, so Qt stops drawing it: Sway
    // does, and Hyprland does over a game. A new layer only takes effect on
    // the surface's next commit, which then never comes: the island would
    // stay hidden, and a screenshot would wait forever for a frame to save.
    // When no frame comes soon after the move, hiding the window and showing
    // it again makes a new surface, on the overlay layer from its first
    // frame. This runs on every output, not only covered ones: if Mochi
    // misses a fullscreen window, the move must still work. A surface in
    // sight draws its frame well before the timer ends.
    readonly property bool coveredHere: Daemon.coveredOutputs.includes(screen?.name ?? "")
    property bool remapping: false
    visible: !remapping
    // Moving to the overlay layer, until the first frame there. The
    // island holds what it shows next until then, so its opening morph
    // plays from the start instead of half of it passing out of sight.
    property bool moving: false
    // Closing over a fullscreen window: the surface stays over it while the
    // island shrinks and fades out, as it would close anywhere else.
    property bool lingering: false
    onOverFullscreenChanged: {
        if (overFullscreen) {
            moving = true;
            stalled.restart();
            island.Window.window?.update();
        } else if (!overFullscreen) {
            moving = false;
            stalled.stop();
            if (coveredHere) {
                lingering = true;
                linger.restart();
            }
        }
    }

    Timer {
        id: stalled

        interval: 100
        onTriggered: {
            root.remapping = true;
            Qt.callLater(() => root.remapping = false);
        }
    }

    Timer {
        id: linger

        interval: Theme.fadeIn + 50
        onTriggered: root.lingering = false
    }

    Connections {
        target: root.moving ? island.Window.window : null

        function onFrameSwapped(): void {
            stalled.stop();
            root.moving = false;
        }
    }

    // Under a fullscreen window the island draws only what belongs over
    // it: not the bar, the bubbles, or what the island showed before, which
    // the window hid. The frozen frame of a screenshot would show them.
    readonly property bool islandOverFullscreen: {
        const shown = island.activity;
        return arranging || (shown !== null && (shown.modal || shown.overlay != null || shown.over_fullscreen === true));
    }
    WlrLayershell.keyboardFocus: modal || overlaid ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Whether a point is on the island or a pill, not outside them.
    function inside(x: real, y: real): bool {
        const over = item => {
            if (!item || !item.visible)
                return false;
            const point = item.mapFromItem(null, x, y);
            return point.x >= 0 && point.y >= 0 && point.x < item.width && point.y < item.height;
        };
        return over(island) || pills.some(over);
    }

    // Every pill on screen, for the regions below.
    property list<Item> pills
    function addPill(pill: Item): void {
        pills = [...pills, pill];
    }
    function removePill(pill: Item): void {
        pills = pills.filter(other => other !== pill);
    }

    // A drag out of the island goes through to the apps underneath.
    mask: covering && !DragOut.active ? everywhere : shapes

    property Region shapes: Region {
        regions: [root.barMask, root.islandMask, ...pillMasks.instances, ...spanMasks.instances]
    }

    // The bar takes clicks all along it: there's no window under it, since
    // windows keep out of its room.
    property Region barMask: Region {
        y: root.atBottom ? root.height - Theme.idleHeight : 0
        width: Theme.mode === "bar" && !root.coveredHere ? root.width : 0
        height: Theme.idleHeight
    }

    // A pixel short of the bar's inner edge; see IslandRegion's inset.
    property Region barBlur: Region {
        y: root.atBottom ? root.height - Theme.idleHeight + 1 : 0
        width: Theme.mode === "bar" && !root.coveredHere ? root.width : 0
        height: Theme.idleHeight - 1
    }

    property Region everywhere: Region {
        width: root.width
        height: root.height
    }

    // Under everything: a click that misses the island closes what it
    // shows. The daemon decides how: dismissed when the user opened it or
    // it takes the keyboard, ended early otherwise.
    MouseArea {
        anchors.fill: parent
        enabled: root.covering
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            const here = root.screen?.name ?? "";
            if (root.overlaid) {
                Daemon.eventFor(root.activity, "dismiss", here);
                return;
            }
            // Where it was, so the daemon passes it on to the window under
            // it once the island lets go: one click, not two.
            const click = {
                "output": here,
                "x": mouse.x,
                "y": mouse.y,
                "width": root.width,
                "height": root.height,
                "button": mouse.button
            };
            if (root.modal || root.catching)
                Daemon.outsideClick(root.activity, here, click);
            else
                Daemon.outsideClick(Daemon.activityFor(root.panelElsewhere), root.panelElsewhere, click);
        }
        // The catch takes the scroll wheel too, and a surface can't pass an
        // event on to the window underneath, so the daemon scrolls there
        // again once the island lets go. A notice the user didn't open
        // stops catching and stays until it times out; a panel closes, as
        // on a click.
        onWheel: wheel => {
            // A scroll over the island or a bubble that nothing there took,
            // like a list already at its end, is the panel's own: it never
            // counts as outside.
            if (root.overlaid || root.inside(wheel.x, wheel.y))
                return;
            const here = root.screen?.name ?? "";
            const scroll = {
                "output": here,
                "x": wheel.x,
                "y": wheel.y,
                "width": root.width,
                "height": root.height,
                "button": 0,
                "scroll": {
                    "x": wheel.angleDelta.x,
                    "y": wheel.angleDelta.y
                }
            };
            // A notice the user didn't open lets go, and the scroll goes on
            // to the window under it; the notice stays.
            if (root.catching && !root.modal && !root.activity.expanded) {
                root.released = {
                    "id": root.activity.id,
                    "module": root.activity.module,
                    "key": root.activity.key ?? null
                };
                Daemon.passOn(scroll);
            } else if (root.modal || root.catching) {
                // A panel closes, as on a click, and the window scrolls.
                Daemon.outsideClick(root.activity, here, scroll);
            } else if (root.panelElsewhere !== "") {
                Daemon.outsideClick(Daemon.activityFor(root.panelElsewhere), root.panelElsewhere, scroll);
            }
        }
    }

    // Each modal activity gets the keyboard's focus in the island, where
    // Escape closes it; after the view's own setup, so a view that takes
    // the focus for a field keeps it.
    onActivityChanged: {
        if (modal && !overlaid)
            Qt.callLater(island.takeKeys);
    }
    onModalChanged: {
        if (modal && !overlaid)
            Qt.callLater(island.takeKeys);
        // A panel's own buttons send their events to this island.
        const name = screen?.name ?? "";
        if (modal)
            Daemon.focusedOutput = name;
        else if (Daemon.focusedOutput === name)
            Daemon.focusedOutput = null;
    }

    // The activity's overlay, under the bubbles and the island. It stays
    // loaded while activities with the same overlay follow each other, and
    // gets each one's payload.
    Loader {
        id: overlay

        anchors.fill: parent
        source: root.overlaid ? `root:/modules/${root.activity.module}/${root.activity.overlay}.qml` : ""
    }

    Binding {
        target: overlay.item
        property: "payload"
        value: root.activity?.payload
        when: overlay.item !== null && root.overlaid
    }

    Binding {
        target: overlay.item
        property: "screen"
        value: root.screen
        when: overlay.item !== null
    }

    // Blur through ext-background-effect-v1. Compositors without the protocol
    // show everything without blur.
    BackgroundEffect.blurRegion: Region {
        regions: [root.barBlur, root.islandBlur, ...pillBlurs.instances, ...spanBlurs.instances]
    }

    property IslandRegion islandMask: IslandRegion {
        island: island
    }

    property IslandRegion islandBlur: IslandRegion {
        island: island
        ears: true
        inset: 1
    }

    Variants {
        id: pillMasks

        model: root.pills
        PillRegion {}
    }

    Variants {
        id: pillBlurs

        model: root.pills
        PillRegion {
            inset: 1
        }
    }

    Variants {
        id: spanMasks

        model: root.spans
        SpanRegion {}
    }

    Variants {
        id: spanBlurs

        model: root.spans
        SpanRegion {
            inset: 1
        }
    }

    // Under the bubbles and the island, which it draws the background of.
    Bar {
        anchors.fill: parent
        island: root.islandItem
        flipY: root.atBottom
        visible: root.barred > 0 && !root.coveredHere
        opacity: root.barred
    }

    readonly property real edgeY: atBottom ? height - margin : margin
    readonly property var areas: ({
            "left": left,
            "center-left": centerLeft,
            "center": center,
            "center-right": centerRight,
            "right": right
        })
    readonly property BubbleArea host: areas[Theme.islandArea] ?? center

    // Named apart from the areas' own `island` property.
    readonly property Item islandItem: island

    // The areas set to "island" that have bubbles to merge. The island's
    // shape reaches out to them wherever they are, across the gap to the
    // screen's sides too, and takes in whatever sits on the way.
    readonly property var order: ["left", "center-left", "center", "center-right", "right"]
    readonly property var joined: order.filter(name => areas[name].arrangement === "island" && areas[name].hasMerged)
    // 1 while the island is part of a Span, animated: its own background
    // fades into the Span's.
    property real islandMerged: joined.length > 0 && island.shown ? 1 : 0

    Behavior on islandMerged {
        NumberAnimation {
            duration: Theme.duration(350)
            easing.type: Easing.OutCubic
        }
    }

    readonly property list<Item> spans: [islandSpan, leftSpan, centerLeftSpan, centerSpan, centerRightSpan, rightSpan]

    component MergedShape: Span {
        anchors.fill: parent
        stripNear: root.margin
        attached: root.attached
        leftSide: start < 0.5 ? root.attached * (1 - root.barred) : 0
        rightSide: end > root.width - 0.5 ? root.attached * (1 - root.barred) : 0
        flipY: root.atBottom
        opacity: shown ? 1 - root.barred : 0
        visible: !root.coveredHere

        // Whether it draws, apart from fading.
        property bool shown: false

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.duration(350)
                easing.type: Easing.OutCubic
            }
        }
    }

    // Around the island and the areas that join it.
    MergedShape {
        id: islandSpan

        readonly property var members: root.joined.map(name => root.areas[name])

        island: root.islandItem
        shown: members.length > 0
        start: Math.min(...(island.shown ? [island.x] : []), ...members.map(area => area.x + area.spanStart))
        end: Math.max(...(island.shown ? [island.x + island.width] : []), ...members.map(area => area.x + area.spanEnd))
    }

    // Around each merged area that doesn't join the island.
    component AreaShape: MergedShape {
        required property BubbleArea area

        shown: area.hasMerged && !area.absorbed && !root.joined.includes(area.area)
        start: area.x + area.spanStart
        end: area.x + area.spanEnd
    }

    AreaShape {
        id: leftSpan

        area: left
    }

    AreaShape {
        id: centerLeftSpan

        area: centerLeft
    }

    AreaShape {
        id: centerSpan

        area: center
    }

    AreaShape {
        id: centerRightSpan

        area: centerRight
    }

    AreaShape {
        id: rightSpan

        area: right
    }

    component Area: BubbleArea {
        island: root.islandItem
        window: root
        visible: !root.coveredHere
        attached: root.attached
        flat: root.barred
        // Inside the island's shape without joining it, like the area
        // between the island and one that joins it: its pills draw on that
        // shape too.
        absorbed: islandSpan.shown && !root.joined.includes(area) && occupied && x >= islandSpan.start - 0.5 && x + width <= islandSpan.end + 0.5
        atBottom: root.atBottom
        y: root.atBottom ? root.edgeY - height : root.edgeY
    }

    Area {
        id: left

        area: "left"
        x: root.side
    }

    Area {
        id: center

        area: "center"
        x: (root.width - width) / 2
    }

    // The center-left and center-right areas hug the center area, or meet in
    // the middle of the screen when it is empty.
    Area {
        id: centerLeft

        area: "center-left"
        x: (center.width > 0 ? center.x - Theme.spacing : (root.width - Theme.spacing) / 2) - width
    }

    Area {
        id: centerRight

        area: "center-right"
        x: center.width > 0 ? center.x + center.width + Theme.spacing : (root.width + Theme.spacing) / 2
    }

    Area {
        id: right

        area: "right"
        x: root.width - width - root.side
    }

    Island {
        id: island

        x: root.host.x + root.host.slot.x
        y: root.host.y + root.host.slot.y
        attached: root.attached
        sideAttached: root.host.onSide ? root.attached * (1 - root.barred) : 0
        flat: Math.max(root.barred, root.islandMerged)
        atBottom: root.atBottom
        atRight: Theme.islandArea === "right"
        overlay: overlay
        output: root.screen?.name ?? ""
        holding: root.moving
        // Under a fullscreen window it fades in as it opens and out as it
        // closes: what it shows the rest of the time is out of sight there.
        opacity: (shown ? 1 : 0) * (root.coveredHere && !root.islandOverFullscreen ? 0 : 1)
        visible: !root.coveredHere || root.islandOverFullscreen || root.lingering
    }

    // Carries a drag out of a panel past the panel's closing.
    DragCarrier {}

    // While mochid profiles, how many frames this island draws.
    FrameCounter {
        output: root.screen?.name ?? ""
        surface: "island"
    }
}
