// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

pragma ComponentBehavior: Bound
import QtQuick
import DesktopTop

Item {
    id: face
    required property var controller
    property bool terminalEnabled: true
    property alias terminal: terminal
    signal focusRequested()
    readonly property color ink: controller.palette.foreground
    readonly property color accent: controller.palette.accent
    readonly property color background: controller.palette.background
    readonly property color dim: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
    opacity: controller.panelOpacity

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(face.background.r, face.background.g, face.background.b, 0.76)
        border.width: 1
        border.color: Qt.rgba(face.accent.r, face.accent.g, face.accent.b, 0.24)
    }
    Repeater {
        model: 4
        Item {
            required property int index
            x: index % 2 === 0 ? 0 : face.width - 14
            y: index < 2 ? 0 : face.height - 14
            width: 14; height: 14
            Rectangle { width: 14; height: 2; y: parent.index < 2 ? 0 : 12; color: face.accent }
            Rectangle { width: 2; height: 14; x: parent.index % 2 === 0 ? 0 : 12; color: face.accent }
        }
    }
    Text {
        x: 26; y: 20
        text: ">_ OMARCHY"
        color: face.accent
        font { family: face.controller.palette.fontFamily; pixelSize: 12; weight: Font.DemiBold; letterSpacing: 1.6 }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 26
        y: 21; text: "[ BTOP ]"; color: face.dim
        font { family: face.controller.palette.fontFamily; pixelSize: 10; letterSpacing: 0.6 }
    }
    Terminal {
        id: terminal
        x: 26; y: 48
        width: face.width - 52; height: face.height - 98
        clip: true
        focus: true
        enabled: face.terminalEnabled
        fontFamily: face.controller.palette.fontFamily
        fontPixelSize: face.controller.fontPixelSize
        foreground: face.ink; background: face.background; accent: face.accent
        boxes: face.controller.shownBoxes
        onFocusRequested: face.focusRequested()
        onSizeChanged: Qt.callLater(face.controller.statusChanged)
        onRunningChanged: Qt.callLater(face.controller.statusChanged)
    }
    Rectangle {
        x: 26; y: face.height - 48
        width: face.width - 52; height: 1
        color: Qt.rgba(face.accent.r, face.accent.g, face.accent.b, 0.2)
    }
    Text {
        x: 26; y: face.height - 32
        text: terminal.running ? "SYSTEM MONITOR" : terminal.error ? "BTOP ERROR · CLICK TO RETRY" : "BTOP STOPPED · CLICK TO RESTART"
        color: terminal.error ? face.accent : face.ink
        font { family: face.controller.palette.fontFamily; pixelSize: 12; letterSpacing: 1 }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 26
        y: face.height - 31
        text: face.controller.gesturing ? (face.controller.gestureEdge === "move" ? "MOVING..." : "RESIZING...")
            : terminal.columns + " × " + terminal.rows
        color: face.controller.gesturing ? face.accent : face.dim
        font { family: face.controller.palette.fontFamily; pixelSize: 10; letterSpacing: 1 }
    }
}
