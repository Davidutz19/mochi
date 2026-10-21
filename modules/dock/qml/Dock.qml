import QtQuick
import Quickshell
import qs.island

// The dock: one icon per app, pinned first, then the running ones. Under
// each, a dot for each open window, up to three; the app with focus has
// its dots joined into one pill, as the workspaces indicator stretches the
// active dot. A click starts the app, focuses it, or goes to its next
// window; a middle click starts another one; the wheel goes through its
// windows. Resting the pointer on an icon names it beside the dock.
Item {
    id: root

    property var payload: ({})
    // The monitor this dock is on, for per_monitor.
    readonly property string output: QsWindow.window?.screen?.name ?? ""
    readonly property bool perMonitor: payload.per_monitor === true
    readonly property bool canStart: Daemon.modules.includes("launcher")
    readonly property var apps: (payload.apps ?? []).filter(app => app.pinned || !perMonitor || windowsOf(app).length > 0)

    // The app under the pointer, for the tooltip.
    property var hovered: null
    readonly property string tooltip: {
        if (!hovered)
            return "";
        const windows = windowsOf(hovered);
        if (windows.length === 0)
            return canStart ? hovered.name : `${hovered.name}\nTurn on the launcher module to start it from here`;
        if (windows.length === 1)
            return windows[0].title && windows[0].title !== hovered.name ? `${hovered.name}\n${windows[0].title}` : hovered.name;
        return `${hovered.name}\n${windows.length} windows`;
    }

    function windowsOf(app: var): var {
        const windows = app?.windows ?? [];
        return perMonitor ? windows.filter(window => window.outputs.includes(output)) : windows;
    }

    // The pill's height less a 4 pixel inset on each side: a taller bar,
    // Layout's idle_height, gives bigger icons, 18 pixels at the default 34.
    readonly property real iconSize: implicitHeight - 8

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(26, Theme.idleHeight - 8)

    Row {
        id: row

        anchors.centerIn: parent

        Repeater {
            model: root.apps

            Item {
                id: slot

                required property var modelData
                readonly property var windows: root.windowsOf(modelData)
                readonly property bool focused: windows.some(window => window.focused)
                // Started from here and not open yet: the icon breathes
                // until its first window shows, or for ten seconds.
                property bool starting: false

                onWindowsChanged: {
                    if (windows.length > 0)
                        starting = false;
                }

                width: root.iconSize + 12
                height: root.implicitHeight

                Timer {
                    running: slot.starting
                    interval: 10000
                    onTriggered: slot.starting = false
                }

                // The icon under the pointer, over the pill's own hover
                // highlight: the text color, faint, shows on either theme.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusControl
                    color: Theme.foreground
                    opacity: mouse.containsMouse ? 0.12 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.fast
                        }
                    }
                }

                AppIcon {
                    id: icon

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 1 // design: a pixel off the edge, as the dots below are
                    icon: slot.modelData.icon
                    size: root.iconSize
                    scale: mouse.pressed ? 0.88 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.fast
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation on opacity {
                        running: slot.starting && Daemon.shows(icon.QsWindow.window)
                        loops: Animation.Infinite
                        onRunningChanged: {
                            if (!running)
                                icon.opacity = 1;
                        }

                        NumberAnimation {
                            to: 0.4
                            duration: Theme.duration(600)
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            to: 1
                            duration: Theme.duration(600)
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                // A dot per window, or one pill for the app with focus.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1 // design: the dots sit a pixel off the edge, under the icon
                    spacing: 2

                    Repeater {
                        model: slot.focused ? 1 : Math.min(slot.windows.length, 3)

                        Rectangle {
                            width: slot.focused ? 12 : 4
                            height: 3
                            radius: height / 2
                            color: slot.focused ? Theme.foreground : Theme.muted

                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.move
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.overshoot
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse)
                            root.hovered = slot.modelData;
                        else if (root.hovered?.key === slot.modelData.key)
                            root.hovered = null;
                    }
                    onClicked: mouse => {
                        const key = slot.modelData.key;
                        if (mouse.button === Qt.MiddleButton) {
                            slot.starting = root.canStart && slot.modelData.desktop != null;
                            Daemon.command("dock", "launch", [key]);
                            return;
                        }
                        if (slot.windows.length === 0)
                            slot.starting = root.canStart && slot.modelData.desktop != null;
                        Daemon.command("dock", "activate", [key, root.output]);
                    }
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y || wheel.angleDelta.x;
                        if (delta !== 0)
                            Daemon.command("dock", "cycle", [slot.modelData.key, delta > 0 ? "previous" : "next", root.output]);
                    }
                }
            }
        }
    }
}
