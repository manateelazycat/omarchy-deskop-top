import QtQuick

// Painted in the display surface; its matching input area lives in the
// stationary input surface so it never interferes with dragging.
Rectangle {
    required property color accent
    property bool hovered: false
    width: 24
    height: 24
    radius: 3
    color: hovered ? Qt.rgba(accent.r, accent.g, accent.b, 0.16) : "transparent"

    Rectangle {
        anchors.centerIn: parent
        width: 12
        height: 2
        color: parent.accent
    }
}
