import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// One shape around a run of merged bubbles, and the island when it joins
// them: a strip as tall as the idle island from `start` to `end`, with the
// island hanging past it where it grows. The pills and the island in it
// draw no background of their own then. Floating, the strip's ends are
// round; in notch mode it hangs from the edge with ears at its ends, and
// with ears where the island leaves it, like the bar.
//
// The geometry is worked out with the edge at the top; `flipY` mirrors it
// to the bottom edge. It fills the window, in the window's coordinates.
Item {
    id: root

    // The strip's ends, in window coordinates.
    property real start: 0
    property real end: 0
    // The strip's side toward the edge, from the edge: the margin. The
    // side away from it is `stripFar`.
    property real stripNear: 0
    property real thickness: Theme.idleHeight
    // The island, when it is part of the shape.
    property Island island: null
    property real attached: 0
    // 0 or 1: an end touching the screen's side, in notch mode.
    property real leftSide: 0
    property real rightSide: 0
    property bool flipY: false

    readonly property real w: end - start
    readonly property bool empty: w < 0.5
    readonly property real stripFar: stripNear + thickness
    readonly property real r: Math.min(thickness / 2, Theme.maxRadius)

    // The island's sides and its end away from the edge, unflipped, and how
    // far past the strip that is.
    readonly property bool withIsland: island !== null && island.shown
    readonly property real islandStart: withIsland ? island.x : 0
    readonly property real islandEnd: withIsland ? island.x + island.width : 0
    readonly property real islandFar: !withIsland ? stripFar : flipY ? height - island.y : island.y + island.height
    readonly property real hang: withIsland ? Math.max(0, islandFar - stripFar) : 0
    readonly property bool hanging: hang > 0.5
    // The island makes up an end of the strip: that side runs straight
    // down to the island's far end.
    readonly property bool islandAtStart: withIsland && islandStart <= start + 0.5
    readonly property bool islandAtEnd: withIsland && islandEnd >= end - 0.5

    // Corners and ears where the strip meets the edge, as in IslandShape.
    readonly property real edgeEar: Math.min(Theme.earRadius, Math.max(0, thickness - r)) * attached
    readonly property real edgeCorner: r * (1 - attached)
    readonly property real leftEar: edgeEar * (1 - leftSide)
    readonly property real rightEar: edgeEar * (1 - rightSide)
    readonly property real leftDown: Theme.earRadius * leftSide
    readonly property real rightDown: Theme.earRadius * rightSide
    // The far corners at the ends: the island's when it makes up the end.
    readonly property real leftFar: islandAtStart ? Math.max(stripFar, islandFar) : stripFar
    readonly property real rightFar: islandAtEnd ? Math.max(stripFar, islandFar) : stripFar
    readonly property real leftCorner: (islandAtStart ? island.radius : r) * (1 - leftSide)
    readonly property real rightCorner: (islandAtEnd ? island.radius : r) * (1 - rightSide)
    // The hanging part's corners and its ears grow with it from nothing,
    // as in Bar.
    readonly property real corner: withIsland ? Math.min(island.radius, hang) : 0
    readonly property real ear: Math.max(0, Math.min(Theme.earRadius, hang - corner, islandAtStart ? Theme.earRadius : islandStart - start - leftCorner, islandAtEnd ? Theme.earRadius : end - rightCorner - islandEnd))

    function point(x: real, y: real): string {
        return `${x} ${flipY ? height - y : y}`;
    }

    // Mirroring reverses the direction of every arc.
    function arc(radius: real, convex: bool, x: real, y: real): string {
        const sweep = convex !== flipY ? 1 : 0;
        return ` A ${radius} ${radius} 0 0 ${sweep} ${point(x, y)}`;
    }

    // Clockwise from the top-left. The border skips what touches the
    // screen: the edge, and a side in notch mode.
    function outline(border: bool): string {
        const alongEdge = border && edgeEar > 0 ? " M " : " L ";
        let path = leftEar > 0 ? `M ${point(start - leftEar, stripNear)}` : `M ${point(start + edgeCorner, stripNear)}`;

        if (rightEar > 0)
            path += alongEdge + point(end + rightEar, stripNear) + arc(rightEar, false, end, stripNear + rightEar);
        else
            path += alongEdge + point(end - edgeCorner, stripNear) + arc(edgeCorner, true, end, stripNear + edgeCorner);

        if (rightDown > 0)
            path += (border ? " M " : " L ") + point(end, rightFar + rightDown) + arc(rightDown, false, end - rightDown, rightFar);
        else
            path += ` L ${point(end, rightFar - rightCorner)}` + arc(rightCorner, true, end - rightCorner, rightFar);

        // Around the island where it hangs past the strip.
        if (hanging && !islandAtEnd) {
            path += ` L ${point(islandEnd + ear, stripFar)}` + arc(ear, false, islandEnd, stripFar + ear);
            path += ` L ${point(islandEnd, islandFar - corner)}` + arc(corner, true, islandEnd - corner, islandFar);
        }
        if (hanging && !islandAtStart) {
            path += ` L ${point(islandStart + corner, islandFar)}` + arc(corner, true, islandStart, islandFar - corner);
            path += ` L ${point(islandStart, stripFar + ear)}` + arc(ear, false, islandStart - ear, stripFar);
        }

        if (leftDown > 0)
            path += ` L ${point(start + leftDown, leftFar)}` + arc(leftDown, false, start, leftFar + leftDown);
        else
            path += ` L ${point(start + leftCorner, leftFar)}` + arc(leftCorner, true, start, leftFar - leftCorner);

        const alongSide = border && leftDown > 0 ? " M " : " L ";
        if (leftEar > 0)
            path += alongSide + point(start, stripNear + leftEar) + arc(leftEar, false, start - leftEar, stripNear);
        else
            path += alongSide + point(start, stripNear + edgeCorner) + arc(edgeCorner, true, start + edgeCorner, stripNear);

        return border && (edgeEar > 0 || leftDown > 0 || rightDown > 0) ? path : path + " Z";
    }

    visible: !empty && opacity > 0

    // A soft shadow under the strip and under the island where it hangs,
    // both covered by the shape where they overlap it. Theme.shadow sets
    // its strength, and transparent turns it off.
    RectangularShadow {
        visible: Theme.shadow.a > 0
        x: root.start
        y: root.flipY ? root.height - root.stripFar : root.stripNear
        width: root.w
        height: root.thickness
        radius: root.r * (1 - root.attached)
        blur: 16
        offset.y: root.flipY ? -2 : 2
        color: Theme.shadow
    }

    RectangularShadow {
        visible: Theme.shadow.a > 0 && root.hanging
        x: root.island?.x ?? 0
        y: root.island?.y ?? 0
        width: root.island?.width ?? 0
        height: root.island?.height ?? 0
        radius: root.corner
        blur: 16
        offset.y: root.flipY ? -2 : 2
        color: Theme.shadow
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.background
            strokeColor: "transparent"

            PathSvg {
                path: root.empty ? "" : root.outline(false)
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.border
            strokeWidth: 1
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.empty ? "" : root.outline(true)
            }
        }
    }
}
