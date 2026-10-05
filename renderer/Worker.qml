// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool configured: false
    property var peer: null
    DesktopState { id: desktop }
    TopController {
        id: top
        emptyScreens: root.configured ? desktop.emptyScreens : ({})
        onSaveRequested: settings => {
            if (root.peer) root.peer.write(JSON.stringify({type: "save", settings: settings}) + "\n");
        }
        onStatusChanged: Qt.callLater(root.sendState)
    }
    function sendState() {
        if (peer && peer.connected && configured)
            peer.write(JSON.stringify({type: "state", state: top.status()}) + "\n");
    }
    SocketServer {
        path: Quickshell.env("DESKTOP_TOP_SOCKET")
        active: true
        onActiveChanged: if (active) console.log("DESKTOP_TOP_WORKER_READY")
        handler: Component {
            Socket {
                id: client
                parser: SplitParser {
                    onRead: data => {
                        try {
                            var packet = JSON.parse(data);
                            if (packet.type === "minimize") {
                                top.setMinimized(packet.screen, packet.minimized === true);
                                return;
                            }
                            top.configure(packet);
                            root.configured = true;
                            Qt.callLater(root.sendState);
                        } catch (error) { console.warn("Desktop Top: invalid host settings:", error); }
                    }
                }
                onConnectedChanged: {
                    if (connected) root.peer = client;
                    else Qt.callLater(Qt.quit);
                }
            }
        }
    }
}
