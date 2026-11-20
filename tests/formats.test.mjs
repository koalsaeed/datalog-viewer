// Every sample log must open the same way it did when its expected result was recorded:
// same source label, channel count and duration, the same standard channels picked, and the
// same value ranges on them. Record new results with `npm run update-expected`, then review
// the diff of expected/formats.json before committing it.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fixtureGroups, launch, openFiles, showPanel } from './helpers.mjs';

const UPDATE = !!process.env.UPDATE_EXPECTED;
const groups = fixtureGroups();
const expected = {}, recorded = {};
for (const g of groups) expected[g.expected] ??= existsSync(g.expected) ? JSON.parse(readFileSync(g.expected, 'utf8')) : {};

const sig = x => (Number.isFinite(x) ? +x.toPrecision(4) : null);
function summary(r) {
  const byName = new Map(r.channels.map(c => [c.n, c]));
  return {
    meta: r.meta,
    channels: r.channels.length,
    standard: r.picked,
    ranges: Object.fromEntries(r.picked.map(n => { const c = byName.get(n); return [n, c ? [sig(c.min), sig(c.max)] : null]; })),
  };
}

describe('log formats', () => {
  let v;
  before(async () => { v = await launch(); await showPanel(v.page); });   // the open panel lists the picked channels
  after(async () => {
    await v.close();
    if (!UPDATE) return;
    for (const [file, rec] of Object.entries(recorded)) {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify({ ...expected[file], ...rec }, null, 1) + '\n');
    }
  });

  for (const g of groups) {
    test(g.key, async () => {
      const r = await openFiles(v.page, g.files);
      assert.equal(r.error, '', `page shows an error: ${r.error}`);
      assert.doesNotMatch(r.toast, /Could not/, r.toast);
      assert.deepEqual(v.errors, [], 'no uncaught errors in the page');
      assert.ok(r.channels.length > 0, 'at least one channel');
      const got = summary(r);
      if (UPDATE) { (recorded[g.expected] ??= {})[g.key] = got; return; }
      const want = expected[g.expected][g.key];
      assert.ok(want, `no expected result for ${g.key}: run npm run update-expected`);
      assert.equal(got.meta, want.meta);
      assert.equal(got.channels, want.channels);
      assert.deepEqual(got.standard, want.standard);
      assert.deepEqual(got.ranges, want.ranges);
    });
  }
});
