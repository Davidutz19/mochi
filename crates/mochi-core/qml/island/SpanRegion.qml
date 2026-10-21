import QtQuick
import Quickshell

// A Span's strip as a region, for the input mask and the blur, in window
// coordinates. The island's part of it has a region of its own.
Region {
    required property Span modelData
    // Pixels to stay inside the outline; see IslandRegion.
    property int inset: 0

    readonly property Span span: modelData
    readonly property bool shown: span.visible
    readonly property real edge: Math.max(0, span.edgeCorner - inset)
    readonly property real farCorner: Math.max(0, span.r - inset)

    x: shown ? Math.round(span.start) + inset : 0
    y: shown ? Math.round(span.flipY ? span.height - span.stripFar : span.stripNear) + inset : 0
    width: shown ? Math.max(0, Math.round(span.w) - inset * 2) : 0
    height: shown ? Math.max(0, span.thickness - inset * 2) : 0
    topLeftRadius: span.flipY ? farCorner : edge
    topRightRadius: span.flipY ? farCorner : edge
    bottomRightRadius: span.flipY ? edge : farCorner
    bottomLeftRadius: span.flipY ? edge : farCorner
}
