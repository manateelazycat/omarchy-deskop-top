// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

import QtQuick
import Quickshell.Hyprland

// Event-driven native IPC models: no polling, subprocesses or timers.
QtObject {
    readonly property var emptyScreens: JSON.parse(emptyMask)
    // Suppress notifications when title/focus changes leave occupancy unchanged.
    readonly property string emptyMask: {
        var result = {};
        var monitors = Hyprland.monitors.values;
        var workspaces = Hyprland.workspaces.values;
        var windows = Hyprland.toplevels.values;
        for (var monitor of monitors) {
            var info = monitor.lastIpcObject;
            var workspace = monitor.activeWorkspace;
            if (!workspace || info.disabled || info.dpmsStatus === false) {
                result[monitor.name] = false;
                continue;
            }
            var occupied = workspace.toplevels.values.length > 0;
            var specialId = info.specialWorkspace ? info.specialWorkspace.id : 0;
            if (specialId) {
                var special = workspaces.find(function(w) { return w.id === specialId; });
                occupied = occupied || !!(special && special.toplevels.values.length);
            }
            for (var window of windows) {
                var client = window.lastIpcObject;
                if (client.pinned && client.monitor === monitor.id && !client.hidden) occupied = true;
            }
            result[monitor.name] = !occupied;
        }
        return JSON.stringify(result);
    }
}
