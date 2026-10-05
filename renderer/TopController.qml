// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Geometry.js" as Geometry

Item {
    id: root
    property var settings: ({})
    property var palette: ({foreground: "#c0caf5", background: "#1a1b26", accent: "#7aa2f7", fontFamily: "monospace"})
    property var emptyScreens: ({})
    readonly property var minimizedScreens: Array.isArray(settings.minimizedScreens) ? settings.minimizedScreens : []
    readonly property var eligibleScreens: Quickshell.screens.filter(function(s) { return root.emptyScreens[s.name] === true; })
    readonly property bool anyVisible: eligibleScreens.length > 0
    property point position: Qt.point(0.64, 0.52)
    property point savedPosition: Qt.point(0.64, 0.52)
    property real panelWidth: 1000
    property real panelHeight: 650
    readonly property int fontPixelSize: Geometry.clamp(Geometry.number(settings.fontSize, 13), 8, 32)
    readonly property real panelOpacity: Geometry.clamp(Geometry.number(settings.opacity, 1), 0.2, 1)
    readonly property string shownBoxes: Geometry.boxes(settings.boxes)
    readonly property var minimum: Geometry.minimum(shownBoxes)
    property bool gesturing: false
    property string gestureScreen: ""
    property string gestureEdge: ""
    property var gestureRect: ({x: 0, y: 0, width: 1000, height: 650})
    property var gestureLimits: ({})
    property var pendingRect: null
    property alias surfaces: surfaces
    signal saveRequested(var nextSettings)
    signal statusChanged()

    function isMinimized(screenName) { return minimizedScreens.indexOf(screenName) !== -1; }
    function setMinimized(screenName, minimized) {
        if (!Quickshell.screens.some(function(s) { return s.name === screenName; })
            || isMinimized(screenName) === minimized) return;
        if (gesturing && gestureScreen === screenName) cancelGesture();
        var names = minimizedScreens.filter(function(name) { return name !== screenName; });
        if (minimized) names.push(screenName);
        var next = Object.assign({}, settings, {minimizedScreens: names});
        settings = next;
        saveRequested(next);
        statusChanged();
    }

    function configure(config) {
        settings = config.settings || ({});
        if (config.palette) palette = config.palette;
        savedPosition = Qt.point(Geometry.unit(settings.positionX, 0.64), Geometry.unit(settings.positionY, 0.52));
        if (!gesturing) restore();
        statusChanged();
    }
    function restore() {
        position = savedPosition;
        panelWidth = Math.max(1, Geometry.number(settings.width, 1000));
        panelHeight = Math.max(1, Geometry.number(settings.height, 650));
    }
    function beginGesture(surface, edge) {
        if (gesturing) return false;
        gestureScreen = surface.screen.name;
        gestureEdge = edge;
        gestureRect = {x: surface.panelX, y: surface.panelY, width: surface.panelWidth, height: surface.panelHeight};
        gestureLimits = {screenWidth: surface.screenWidth, screenHeight: surface.screenHeight,
            minWidth: surface.minimumWidth, minHeight: surface.minimumHeight, margin: surface.edgeMargin};
        pendingRect = null;
        gesturing = true;
        statusChanged();
        return true;
    }
    function queueGesture(dx, dy) {
        if (!gesturing) return;
        var limits = gestureLimits, rect = gestureRect;
        pendingRect = gestureEdge === "move"
            ? {x: Geometry.clamp(rect.x + dx, limits.margin, limits.screenWidth - rect.width - limits.margin),
               y: Geometry.clamp(rect.y + dy, limits.margin, limits.screenHeight - rect.height - limits.margin),
               width: rect.width, height: rect.height}
            : Geometry.resize(rect, gestureEdge, dx, dy, limits.minWidth, limits.minHeight,
                limits.screenWidth, limits.screenHeight, limits.margin);
    }
    function flushGesture() {
        if (!pendingRect) return;
        var rect = pendingRect, limits = gestureLimits;
        pendingRect = null;
        panelWidth = rect.width;
        panelHeight = rect.height;
        position = Qt.point(Geometry.fraction(rect.x, limits.screenWidth, rect.width, limits.margin),
            Geometry.fraction(rect.y, limits.screenHeight, rect.height, limits.margin));
    }
    function finishGesture() {
        if (!gesturing) return;
        flushGesture();
        gesturing = false;
        var next = Object.assign({}, settings, {positionX: position.x, positionY: position.y,
            width: Math.round(panelWidth), height: Math.round(panelHeight)});
        settings = next;
        savedPosition = position;
        saveRequested(next);
        statusChanged();
    }
    function cancelGesture() {
        pendingRect = null;
        gesturing = false;
        restore();
        statusChanged();
    }
    function status() {
        return {positionX: position.x, positionY: position.y, width: panelWidth, height: panelHeight,
            gesturing: gesturing, emptyScreens: emptyScreens, palette: palette, minimizedScreens: minimizedScreens,
            minimumColumns: minimum.columns, minimumRows: minimum.rows,
            screens: Quickshell.screens.map(function(screen) {
                var surface = surfaces.instances.find(function(p) { return p.screen.name === screen.name; });
                return {name: screen.name, visible: !!surface && surface.visible,
                    minimized: root.isMinimized(screen.name), tabVisible: !!surface && surface.minimizedWindow.visible,
                    tabX: surface ? surface.minimizedWindow.tabX : 0,
                    tabWidth: surface ? surface.minimizedWindow.tabWidth : 72,
                    x: surface ? surface.panelX : 0, y: surface ? surface.panelY : 0,
                    width: surface ? surface.panelWidth : 0, height: surface ? surface.panelHeight : 0,
                    columns: surface ? surface.terminal.columns : 0, rows: surface ? surface.terminal.rows : 0,
                    btopPid: surface ? surface.terminal.processId : -1, running: surface ? surface.terminal.running : false,
                    error: surface ? surface.terminal.error : ""};
            })};
    }
    onEligibleScreensChanged: {
        if (gesturing && !eligibleScreens.some(function(s) { return s.name === root.gestureScreen; })) cancelGesture();
        Qt.callLater(root.statusChanged);
    }
    Timer { interval: 16; repeat: true; running: root.gesturing; onTriggered: root.flushGesture() }
    Variants {
        id: surfaces
        model: root.eligibleScreens
        TopSurface {
            required property var modelData
            screen: modelData
            controller: root
        }
    }
}
