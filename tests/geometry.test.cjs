// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const geometry = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../renderer/Geometry.js`, 'utf8'), geometry);
const rect = {x: 200, y: 180, width: 1000, height: 650};
test('all eight resize edges retain the opposite edge and clamp to btop minimum', () => {
    for (const edge of ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw']) {
        const r = geometry.resize(rect, edge, edge.includes('w') ? 10000 : -10000,
            edge.includes('n') ? 10000 : -10000, 692, 482, 1920, 1080, 24);
        assert.ok(r.width >= 692 && r.height >= 482, edge);
        if (edge.includes('w')) assert.equal(r.x + r.width, rect.x + rect.width, edge);
        if (edge.includes('n')) assert.equal(r.y + r.height, rect.y + rect.height, edge);
        if (edge.includes('e')) assert.equal(r.x, rect.x, edge);
        if (edge.includes('s')) assert.equal(r.y, rect.y, edge);
    }
});
test('expanding stops at screen margins', () => {
    const r = geometry.resize(rect, 'se', 10000, 10000, 692, 482, 1920, 1080, 24);
    assert.equal(r.x + r.width, 1896);
    assert.equal(r.y + r.height, 1056);
});
test('relative positions round-trip across sizes and monitor scales', () => {
    for (const width of [692, 1000, 1500]) for (const fraction of [0, 0.2, 0.64, 1]) {
        const pixel = geometry.pixel(fraction, 1920, width, 24);
        const restored = geometry.fraction(pixel, 1920, width, 24);
        assert.ok(Math.abs(fraction - restored) <= 0.5 / (1920 - width - 48) + 1e-9);
    }
});
test('standard btop panel combinations use upstream minimum rows and columns', () => {
    for (const [boxes, columns, rows] of [['cpu mem net proc', 80, 24], ['cpu', 60, 8], ['proc', 44, 16],
        ['mem net', 36, 16], ['cpu mem net', 60, 24], ['cpu proc', 60, 24]]) {
        const result = geometry.minimum(boxes);
        assert.equal(result.columns, columns); assert.equal(result.rows, rows);
    }
});
