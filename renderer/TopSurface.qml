// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Geometry.js" as Geometry

PanelWindow {
    id: panel
    required property var controller
    readonly property real edgeMargin: 24
    readonly property real screenWidth: screen ? screen.width : 1920
    readonly property real screenHeight: screen ? screen.height : 1080
    readonly property real minimumWidth: controller.minimum.columns * face.terminal.cellWidth + 52
    readonly property real minimumHeight: controller.minimum.rows * face.terminal.cellHeight + 98
    readonly property bool fits: screenWidth >= minimumWidth + 2 * edgeMargin && screenHeight >= minimumHeight + 2 * edgeMargin
    readonly property real panelWidth: Math.round(Geometry.clamp(controller.panelWidth, minimumWidth, screenWidth - 2 * edgeMargin))
    readonly property real panelHeight: Math.round(Geometry.clamp(controller.panelHeight, minimumHeight, screenHeight - 2 * edgeMargin))
    readonly property int panelX: Geometry.pixel(controller.position.x, screenWidth, panelWidth, edgeMargin)
    readonly property int panelY: Geometry.pixel(controller.position.y, screenHeight, panelHeight, edgeMargin)
    readonly property bool grabbed: controller.gesturing && controller.gestureScreen === screen.name
    readonly property int inputX: grabbed ? controller.gestureRect.x : panelX
    readonly property int inputY: grabbed ? controller.gestureRect.y : panelY
    readonly property real inputWidth: grabbed ? controller.gestureRect.width : panelWidth
    readonly property real inputHeight: grabbed ? controller.gestureRect.height : panelHeight
    readonly property var displayWindow: display
    readonly property var terminal: face.terminal

    anchors { top: true; left: true }
    margins { top: panel.inputY; left: panel.inputX }
    implicitWidth: inputWidth; implicitHeight: inputHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: fits && !remapping
    WlrLayershell.namespace: "omarchy-desktop-top-input"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the outer frame catches drag events. The content rectangle belongs
    // to the other surface and passes through to the real terminal.
    mask: Region {
        width: panel.inputWidth; height: panel.inputHeight
        Region { x: 26; y: 48; width: panel.inputWidth - 52; height: panel.inputHeight - 98; intersection: Intersection.Subtract }
    }
    property bool remapping: false
    Timer { id: settle; interval: 200; onTriggered: panel.remapping = true }
    Timer { interval: 50; running: panel.remapping; onTriggered: panel.remapping = false }
    Connections {
        target: panel.screen
        function onXChanged() { if (panel.grabbed) panel.controller.cancelGesture(); settle.restart(); }
        function onYChanged() { if (panel.grabbed) panel.controller.cancelGesture(); settle.restart(); }
        function onWidthChanged() { if (panel.grabbed) panel.controller.cancelGesture(); }
        function onHeightChanged() { if (panel.grabbed) panel.controller.cancelGesture(); }
    }
    PanelWindow {
        id: display
        screen: panel.screen
        anchors { top: true; left: true }
        margins { top: panel.panelY; left: panel.panelX }
        implicitWidth: panel.panelWidth; implicitHeight: panel.panelHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: panel.visible
        WlrLayershell.namespace: "omarchy-desktop-top"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: !keyboardWanted ? WlrKeyboardFocus.None
            : priming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        mask: Region { item: face.terminal }
        property bool keyboardWanted: false
        property bool priming: false
        readonly property bool windowActive: contentItem.Window.active
        onWindowActiveChanged: if (!windowActive && !priming) keyboardWanted = false
        onVisibleChanged: if (!visible) keyboardWanted = false
        Timer { id: focusPrime; interval: 50; onTriggered: display.priming = false }
        TopFace {
            id: face
            anchors.fill: parent
            controller: panel.controller
            terminalEnabled: panel.fits
            onFocusRequested: {
                display.priming = true;
                display.keyboardWanted = true;
                focusPrime.restart();
            }
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        property point pressPoint: Qt.point(0, 0)
        property string hotEdge: "move"
        function edgeAt(x, y) {
            var vertical = y < 12 ? "n" : y >= panel.inputHeight - 12 ? "s" : "";
            var horizontal = x < 12 ? "w" : x >= panel.inputWidth - 12 ? "e" : "";
            return vertical + horizontal || "move";
        }
        cursorShape: panel.grabbed && panel.controller.gestureEdge === "move" ? Qt.ClosedHandCursor
            : hotEdge === "nw" || hotEdge === "se" ? Qt.SizeFDiagCursor
            : hotEdge === "ne" || hotEdge === "sw" ? Qt.SizeBDiagCursor
            : hotEdge === "n" || hotEdge === "s" ? Qt.SizeVerCursor
            : hotEdge === "w" || hotEdge === "e" ? Qt.SizeHorCursor : Qt.OpenHandCursor
        onPressed: mouse => {
            pressPoint = Qt.point(mouse.x, mouse.y);
            hotEdge = edgeAt(mouse.x, mouse.y);
            if (!face.terminal.running && hotEdge === "move" && mouse.y > panel.inputHeight - 48) {
                face.terminal.restart();
                mouse.accepted = false;
                return;
            }
            if (!panel.controller.beginGesture(panel, hotEdge)) mouse.accepted = false;
        }
        onPositionChanged: mouse => {
            if (pressed && panel.grabbed) panel.controller.queueGesture(mouse.x - pressPoint.x, mouse.y - pressPoint.y);
            else hotEdge = edgeAt(mouse.x, mouse.y);
        }
        onReleased: if (panel.grabbed) panel.controller.finishGesture()
        onCanceled: if (panel.grabbed) panel.controller.cancelGesture()
    }
    Component.onDestruction: if (grabbed) controller.cancelGesture()
}
