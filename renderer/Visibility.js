// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

// Hyprland client geometry uses logical coordinates; monitor dimensions
// require rotation and scaling before testing their visible intersection.
function overlapsScreen(client, monitor) {
    if (client.mapped === false || client.hidden || client.visible === false) return false;
    var at = client.at || [0, 0], size = client.size || [0, 0];
    var scale = Math.max(0.1, monitor.scale || 1);
    var rotated = (monitor.transform || 0) % 2 !== 0;
    var width = (rotated ? monitor.height : monitor.width) / scale;
    var height = (rotated ? monitor.width : monitor.height) / scale;
    return size[0] > 0 && size[1] > 0
        && at[0] < monitor.x + width && at[0] + size[0] > monitor.x
        && at[1] < monitor.y + height && at[1] + size[1] > monitor.y;
}
