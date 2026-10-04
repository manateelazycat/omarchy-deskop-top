// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

function number(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback;
    var result = Number(value);
    return isFinite(result) ? result : fallback;
}
function clamp(value, minimum, maximum) { return Math.max(minimum, Math.min(maximum, value)); }
function unit(value, fallback) { return clamp(number(value, fallback), 0, 1); }
function pixel(fraction, extent, size, margin) {
    var inset = Math.min(margin, Math.max(0, (extent - size) / 2));
    return Math.round(inset + unit(fraction, 0.5) * Math.max(0, extent - size - 2 * inset));
}
function fraction(position, extent, size, margin) {
    var inset = Math.min(margin, Math.max(0, (extent - size) / 2));
    var travel = Math.max(0, extent - size - 2 * inset);
    return travel > 0 ? unit((position - inset) / travel, 0.5) : 0.5;
}
// btop 1.4.7 Term::get_min_size, for the four standard panels.
function boxes(value) {
    var selected = String(value || "cpu mem net proc").split(/\s+/)
        .filter(function(b) { return ["cpu", "mem", "net", "proc"].indexOf(b) !== -1; });
    return selected.length ? selected.filter(function(b, i) { return selected.indexOf(b) === i; }).join(" ") : "cpu mem net proc";
}
function minimum(value) {
    var selected = boxes(value).split(" ");
    function has(b) { return selected.indexOf(b) !== -1; }
    return {columns: Math.max(has("cpu") ? 60 : 0, (has("mem") || has("net") ? 36 : 0) + (has("proc") ? 44 : 0)),
        rows: (has("cpu") ? 8 : 0) + (has("proc") ? 16 : (has("mem") ? 10 : 0) + (has("net") ? 6 : 0))};
}
// Resize from the original gesture rectangle, preserving the opposite edge.
function resize(rect, edge, dx, dy, minWidth, minHeight, screenWidth, screenHeight, margin) {
    var left = rect.x, top = rect.y, right = rect.x + rect.width, bottom = rect.y + rect.height;
    if (edge.indexOf("w") !== -1) left = clamp(rect.x + dx, margin, right - minWidth);
    if (edge.indexOf("e") !== -1) right = clamp(right + dx, left + minWidth, screenWidth - margin);
    if (edge.indexOf("n") !== -1) top = clamp(rect.y + dy, margin, bottom - minHeight);
    if (edge.indexOf("s") !== -1) bottom = clamp(bottom + dy, top + minHeight, screenHeight - margin);
    return {x: left, y: top, width: right - left, height: bottom - top};
}
