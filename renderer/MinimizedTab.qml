import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: tab
    required property int slot
    required property color accent
    required property string namespace
    signal restoreRequested()

    // Both independent desktop workers use the same two-slot layout:
    // clock on the left, btop on the right, with a 20 logical pixel gap.
    readonly property int tabWidth: 72
    readonly property int tabGap: 20
    readonly property int tabX: Math.max(0, Math.round(((screen ? screen.width : 1920)
        - tabWidth * 2 - tabGap) / 2)) + slot * (tabWidth + tabGap)
    anchors { top: true; left: true }
    margins { top: 0; left: tab.tabX }
    implicitWidth: tabWidth
    implicitHeight: 14
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: namespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
        anchors.fill: parent
        clip: true
        Rectangle {
            y: -4
            width: parent.width
            height: parent.height + 4
            radius: 4
            color: "#000000"
        }
        Rectangle {
            objectName: "tabAccentLine"
            anchors.centerIn: parent
            width: pointer.containsMouse ? 34 : 28
            height: 2
            radius: 1
            color: tab.accent
        }
        MouseArea {
            id: pointer
            objectName: "restoreHitArea"
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.restoreRequested()
        }
    }
}
