// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const visibility = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../renderer/Visibility.js`, 'utf8'), visibility);
const screen = {x: 3840, y: -1332, width: 1920, height: 1080, scale: 1, transform: 0};
const client = (x, y, extra = {}) => ({at: [x, y], size: [20, 20], ...extra});

test('offscreen Catlink rim does not occupy its assigned monitor', () => {
    assert.equal(visibility.overlapsScreen(client(1821, -1431), screen), false);
    assert.equal(visibility.overlapsScreen(client(4000, -1200), screen), true);
});
test('fully outside and edge-touching windows are excluded on all four edges', () => {
    for (const [x, y] of [[3820, -1200], [5760, -1200], [4000, -1352], [4000, -252]]) {
        assert.equal(visibility.overlapsScreen(client(x, y), screen), false);
    }
});
test('one visible pixel still blocks on each edge', () => {
    for (const [x, y] of [[3821, -1200], [5759, -1200], [4000, -1351], [4000, -253]]) {
        assert.equal(visibility.overlapsScreen(client(x, y), screen), true);
    }
});
test('hidden, unmapped, invisible and zero-size windows do not block', () => {
    for (const extra of [{hidden: true}, {mapped: false}, {visible: false}, {size: [0, 20]}, {size: [20, 0]}]) {
        assert.equal(visibility.overlapsScreen(client(4000, -1200, extra), screen), false);
    }
});
test('scaled and rotated monitors use logical dimensions', () => {
    const scaled = {...screen, scale: 2};
    assert.equal(visibility.overlapsScreen(client(4800, -1200), scaled), false);
    assert.equal(visibility.overlapsScreen(client(4799, -1200), scaled), true);
    for (const transform of [1, 3, 5, 7]) {
        const rotated = {...scaled, transform};
        assert.equal(visibility.overlapsScreen(client(4380, -1200), rotated), false);
        assert.equal(visibility.overlapsScreen(client(4379, -1200), rotated), true);
        assert.equal(visibility.overlapsScreen(client(4000, -373), rotated), true);
        assert.equal(visibility.overlapsScreen(client(4000, -372), rotated), false);
    }
});
