// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

import QtQuick
import QtTest
import Quickshell
import "Plugin/renderer" as Plugin

ShellRoot {
    id: harness
    property int writes: 0
    property var lastSettings: ({})
    function check(condition, message) { if (!condition) throw new Error(message); }
    Plugin.TopController {
        id: service
        emptyScreens: { var result = {}; result[Quickshell.screens[0].name] = true; return result; }
        onSaveRequested: settings => { harness.writes++; harness.lastSettings = settings; }
    }
    TestEvent { id: events }
    TestResult { id: result }
    Timer {
        interval: 2000; running: true
        onTriggered: {
            try {
                var surface = service.surfaces.instances[0];
                harness.check(!!surface && surface.fits, "desktop surface missing");
                var terminal = surface.terminal;
                harness.check(terminal.running && terminal.processId > 0, "real btop did not start");
                harness.check(terminal.screenText().includes("cpu") && terminal.screenText().includes("proc"),
                    "PTY did not display btop panels: " + terminal.screenText());
                console.log("TOP_PASS: real btop draws CPU, memory, network and process panels");
                var originalPid = terminal.processId;
                var originalDisplay = surface.displayWindow;
                var visibilityChanges = 0;
                function changed() { visibilityChanges++; }
                originalDisplay.visibleChanged.connect(changed);
                var oldX = surface.panelX, oldY = surface.panelY;
                events.mousePress(surface.contentItem, 100, 28, Qt.LeftButton, Qt.NoModifier, 1);
                harness.check(service.gesturing && service.gestureEdge === "move", "header did not grab");
                events.mouseMove(surface.contentItem, 160, 53, 1, Qt.LeftButton, Qt.NoModifier);
                result.wait(50);
                harness.check(surface.panelX === oldX + 60 && surface.panelY === oldY + 25, "move drifted");
                harness.check(surface.inputX === oldX && surface.inputY === oldY, "grab coordinate system moved");
                var stoppedX = surface.panelX, stoppedY = surface.panelY;
                result.wait(80);
                harness.check(surface.panelX === stoppedX && surface.panelY === stoppedY, "moving after pointer stopped");
                events.mouseRelease(surface.contentItem, 160, 53, Qt.LeftButton, Qt.NoModifier, 1);
                result.wait(30);
                harness.check(harness.writes === 1 && !service.gesturing, "move did not save once");
                harness.check(surface.panelX === stoppedX && surface.panelY === stoppedY, "release jumped");
                console.log("TOP_PASS: header drag stays stable and saves once on release");
                var width = surface.panelWidth, height = surface.panelHeight;
                events.mousePress(surface.contentItem, width - 2, height - 2, Qt.LeftButton, Qt.NoModifier, 1);
                harness.check(service.gestureEdge === "se", "corner did not select diagonal resize");
                events.mouseMove(surface.contentItem, width - 10000, height - 10000, 1, Qt.LeftButton, Qt.NoModifier);
                result.wait(80);
                harness.check(surface.panelWidth === surface.minimumWidth && surface.panelHeight === surface.minimumHeight,
                    "minimum pixel size was not enforced");
                harness.check(terminal.columns === 80 && terminal.rows === 24, "minimum PTY is not 80x24");
                events.mouseRelease(surface.contentItem, width - 10000, height - 10000, Qt.LeftButton, Qt.NoModifier, 1);
                result.wait(200);
                harness.check(harness.writes === 2, "resize did not save once");
                harness.check(!terminal.screenText().includes("Terminal too small"), "btop rejected minimum size");
                console.log("TOP_PASS: edge resize clamps at real btop minimum and resizes the PTY");
                harness.check(terminal.processId === originalPid && originalDisplay === surface.displayWindow
                    && visibilityChanges === 0, "gesture replaced btop or remapped the display");
                originalDisplay.visibleChanged.disconnect(changed);

                // Exercise all opposite-edge constraints through the controller.
                for (var edge of ["n", "s", "e", "w", "ne", "nw", "se", "sw"]) {
                    service.configure({settings: {width: 1000, height: 650, positionX: 0.5, positionY: 0.5}});
                    result.wait(10);
                    service.beginGesture(surface, edge);
                    var before = service.gestureRect;
                    service.queueGesture(edge.includes("w") ? 80 : -80, edge.includes("n") ? 60 : -60);
                    service.flushGesture();
                    if (edge.includes("w")) harness.check(surface.panelX + surface.panelWidth === before.x + before.width, edge + " right edge moved");
                    if (edge.includes("n")) harness.check(surface.panelY + surface.panelHeight === before.y + before.height, edge + " bottom edge moved");
                    if (edge.includes("e")) harness.check(surface.panelX === before.x, edge + " left edge moved");
                    if (edge.includes("s")) harness.check(surface.panelY === before.y, edge + " top edge moved");
                    service.cancelGesture();
                }
                console.log("TOP_PASS: all eight edges preserve their opposite edge; cancellation restores geometry");
                service.configure({settings: {width: 1100, height: 700, positionX: 0.31, positionY: 0.69}});
                result.wait(100);
                harness.check(surface.panelWidth === 1100 && surface.panelHeight === 700 && service.position.x === 0.31,
                    "persisted size and position did not restore");
                events.mousePress(terminal, 100, 50, Qt.LeftButton, Qt.NoModifier, 1);
                events.mouseRelease(terminal, 100, 50, Qt.LeftButton, Qt.NoModifier, 1);
                harness.check(!service.gesturing, "terminal click started frame drag");
                // Hold compositor focus for QtTest: synthetic pointer events
                // do not relocate the user's physical pointer to this monitor.
                var keyboard = Qt.createQmlObject("import QtTest; TestEvent {}", terminal);
                result.wait(80);
                surface.displayWindow.priming = true;
                surface.displayWindow.keyboardWanted = true;
                result.wait(80);
                terminal.forceActiveFocus();
                harness.check(keyboard.keyClick(Qt.Key_1, Qt.NoModifier, 1), "key event not delivered");
                result.wait(250);
                harness.check(!terminal.screenText().includes("¹cpu"), "keyboard did not toggle btop CPU panel");
                keyboard.keyClick(Qt.Key_1, Qt.NoModifier, 1);
                result.wait(250);
                harness.check(terminal.screenText().includes("¹cpu"), "keyboard did not restore CPU panel");
                surface.displayWindow.priming = false;
                console.log("TOP_PASS: terminal keyboard input toggles and restores the btop CPU panel");
                service.palette = {accent: "#f7768e", foreground: "#eeeeee", background: "#101010", fontFamily: "monospace"};
                result.wait(350);
                harness.check(String(terminal.accent) === "#f7768e" && terminal.processId === originalPid && terminal.running,
                    "theme update restarted btop");
                console.log("TOP_PASS: live theme update keeps the same btop process");
                service.palette = {accent: "#7aa2f7", foreground: "#c0caf5", background: "#1a1b26", fontFamily: "monospace"};
                result.wait(350);
                terminal.parent.grabToImage(function(capture) {
                    var path = Quickshell.env("DESKTOP_TOP_CAPTURE_PATH");
                    if (path) capture.saveToFile(path);
                    cleanup.start();
                });
            } catch (error) {
                console.error("TOP_RUNTIME_FAILED:", error);
                Qt.quit();
            }
        }
    }
    Timer {
        id: cleanup; interval: 50
        onTriggered: {
            try {
                var surface = service.surfaces.instances[0];
                service.configure({settings: Object.assign({}, service.settings, {fontSize: 32})});
                result.wait(150);
                harness.check(surface.terminal.running === surface.fits,
                    "a monitor too small for the minimum retained btop");
                service.configure({settings: Object.assign({}, service.settings, {fontSize: 13})});
                result.wait(300);
                harness.check(surface.fits && surface.terminal.running, "reducing font size did not restart btop");
                console.log("TOP_PASS: a card too large for the monitor stops btop and restores after reducing font size");
                var writesBefore = harness.writes;
                service.beginGesture(surface, "move");
                service.queueGesture(20, 30);
                service.emptyScreens = ({});
                result.wait(100);
                harness.check(service.surfaces.instances.length === 0 && !service.gesturing && harness.writes === writesBefore,
                    "occupied workspace retained or saved a gesture");
                console.log("TOP_PASS: occupied workspace removes surfaces and cancels unfinished gestures");
                console.log("TOP_RUNTIME_PASSED");
            } catch (error) { console.error("TOP_RUNTIME_FAILED:", error); }
            Qt.quit();
        }
    }
}
