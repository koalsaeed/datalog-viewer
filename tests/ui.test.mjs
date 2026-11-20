// Viewer behaviour, including the bugs found on the phone so they cannot come back.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { afterEach, test } from 'node:test';
import { CACHE, OWN, launch, openFiles, showPanel } from './helpers.mjs';

const BIG = `${CACHE}/2025-07-18_0215pm_Log1118.csv`;   // Haltech NSP, 114 channels
const SMALL = `${CACHE}/mhd-n55-pull.csv`;               // 31 channels
const EMERALD = [`${CACHE}/EM Log MG ZS Turbo boost run.lg1`, `${CACHE}/EM Log MG ZS Turbo boost run.lg2`];

let v;
afterEach(async () => { if (v) await v.close(); v = null; });

const allRows = page => page.evaluate(() => document.querySelectorAll('#allList .row').length);
const marked = page => page.evaluate(() => [...document.querySelectorAll('#inList .row.mark .nm')].map(e => e.textContent));
const stripVisible = page => page.evaluate(() => !document.getElementById('legend').hidden);
const onTopOfStrip = (page, x) => page.evaluate(x => {
  const lg = document.getElementById('legend').getBoundingClientRect();
  const el = document.elementFromPoint(x ?? lg.left + 40, lg.top + 10);
  return el ? (el.closest('#legend') ? 'strip' : el.closest('#drawer') ? 'panel' : el.closest('#menu') ? 'menu' : el.id || el.tagName) : 'none';
}, x);

test('the boot sample opens without errors', async () => {
  v = await launch();
  assert.match(await v.page.textContent('#fmeta'), /ch · /);
  assert.deepEqual(v.errors, []);
});

// Bug from the phone: with the panel pinned, opening a log with fewer channels than the one
// before threw "Cannot read properties of undefined (reading 'v')" and the log did not open.
test('switching between logs of different sizes with the panel pinned', async () => {
  v = await launch();
  await showPanel(v.page, { pin: true });
  for (const f of [BIG, SMALL, BIG, SMALL]) {
    const r = await openFiles(v.page, [f]);
    assert.equal(r.error, '', r.error);
    assert.doesNotMatch(r.toast, /Could not/, r.toast);
    assert.equal(await allRows(v.page), r.channels.length - r.picked.length, 'ALL CHANNELS lists the new log');
  }
  assert.deepEqual(v.errors, []);
});

test('ALL CHANNELS shows each reading at the cursor and follows it', async () => {
  v = await launch();
  await showPanel(v.page, { pin: true });
  await openFiles(v.page, [BIG]);
  const read = () => v.page.evaluate(() => [...document.querySelectorAll('#allList .row .val')].map(e => e.textContent));
  const box = await v.page.locator('#chart').boundingBox();
  const seen = [];
  for (const fx of [0.15, 0.5, 0.85]) {
    await v.page.mouse.click(box.x + box.width * fx, box.y + box.height * 0.6);
    await v.page.waitForTimeout(200);
    const vals = await read();
    assert.ok(vals.length > 50 && vals.every(t => t.length > 0), 'every row has a reading');
    seen.push(vals.join('|'));
  }
  assert.equal(new Set(seen).size, 3, 'readings change with the cursor');
});

test('the channel strip stays under the panel and the menu, and hides while the panel is pinned', async () => {
  v = await launch();
  await openFiles(v.page, [SMALL]);
  if (await v.page.evaluate(() => document.getElementById('bLanes').classList.contains('on'))) await v.page.click('#bLanes');   // the strip shows in overlay mode
  await v.page.waitForTimeout(250);
  assert.equal(await stripVisible(v.page), true);
  await v.page.click('#bMore');
  const m = await v.page.locator('#menu').boundingBox();
  assert.equal(await onTopOfStrip(v.page, m.x + 30), 'menu');
  await v.page.click('#bMore');
  await showPanel(v.page);
  assert.equal(await onTopOfStrip(v.page), 'panel');
  await showPanel(v.page, { pin: true });
  assert.equal(await stripVisible(v.page), false, 'hidden while pinned');
  await v.page.click('#bHide');
  await v.page.waitForTimeout(250);
  assert.equal(await stripVisible(v.page), true, 'back when the pinned panel is hidden');
  assert.deepEqual(v.errors, []);
});

test('the standard channels are picked on open', async () => {
  v = await launch();
  await showPanel(v.page);
  const r = await openFiles(v.page, [SMALL]);
  assert.deepEqual(r.picked, ['RPM', 'Throttle Position', 'STFT 2', 'Lambda bank 1', 'Load actual']);
});

// Bug from the phone: a marked channel could not be unmarked.
test('marking and unmarking a channel', async () => {
  v = await launch({ touch: true });
  const cdp = await v.context.newCDPSession(v.page);
  const hold = async (x, y) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    await v.page.waitForTimeout(650);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await v.page.waitForTimeout(250);
  };
  await openFiles(v.page, [SMALL]);
  await showPanel(v.page, { pin: true });
  const row = async () => { const b = await v.page.locator('#inList .row.sel .nm').first().boundingBox(); return [b.x + 40, b.y + b.height / 2]; };
  await hold(...await row());
  assert.deepEqual(await marked(v.page), ['RPM'], 'long press marks');
  await hold(...await row());
  assert.deepEqual(await marked(v.page), [], 'a second long press unmarks');
  await hold(...await row());
  await v.page.click('#inList .mk');
  assert.deepEqual(await marked(v.page), [], 'the MARK badge unmarks');
  await v.page.click('#inList .row.sel [data-act="menu"]');
  await v.page.click('.rowmenu [data-act="mark"]');
  assert.deepEqual(await marked(v.page), ['RPM'], 'Mark in the row menu');
  await v.page.click('#bMore');
  assert.equal(await v.page.isVisible('#mUnmark'), true);
  await v.page.click('#mUnmark');
  assert.deepEqual(await marked(v.page), [], 'Clear marks');
  await hold(...await row());
  await v.page.click('#inList .row.sel [data-act="menu"]');
  await v.page.click('.rowmenu [data-act="remove"]');
  await v.page.evaluate(() => document.querySelector('#allList [data-add]').click());
  assert.deepEqual(await marked(v.page), [], 'removing a channel drops its mark');
  assert.deepEqual(v.errors, []);
});

// The Android app answers "Open log…" by streaming the picked files in as base64 chunks.
test('files streamed in by the Android app open, Emerald .lg1 + .lg2 together', async () => {
  v = await launch();
  await v.page.evaluate(() => { window.PWPApp = { postMessage: m => { window.__asked = m; } }; });
  await v.page.click('#bMore');
  await v.page.click('#mOpen');
  assert.equal(await v.page.evaluate(() => window.__asked), 'open', 'the page asks the app to pick');
  await v.page.evaluate(() => { document.getElementById('fmeta').textContent = ''; });
  for (const f of EMERALD) {
    const b64 = readFileSync(f).toString('base64');
    await v.page.evaluate(n => window.__pwpReceive.begin(n), f.split('/').pop());
    for (let o = 0; o < b64.length; o += 32768) await v.page.evaluate(c => window.__pwpReceive.chunk(c), b64.slice(o, o + 32768));
  }
  await v.page.evaluate(() => window.__pwpReceive.done());
  await v.page.waitForFunction(() => document.getElementById('fmeta').textContent, null, { timeout: 30000 });
  assert.match(await v.page.textContent('#fmeta'), /Emerald ECU \.lg1 \+ \.lg2/);
  await v.page.evaluate(() => window.__pwpReceive.fail('permission denied'));
  assert.match(await v.page.textContent('#toast'), /Could not read the file: permission denied/);
  assert.deepEqual(v.errors, []);
});

test('a log inside a ZIP opens', async () => {
  v = await launch();
  const r = await openFiles(v.page, [`${OWN}/stored.zip`]);
  assert.match(r.meta, /^4 ch · /);
  assert.match(await v.page.textContent('#fname'), /maxx\.csv \(from stored\.zip\)/);
  const z = await openFiles(v.page, [`${OWN}/car.MaxxECU-Zip-log`]);
  assert.match(z.meta, /MaxxECU log/);
  assert.deepEqual(v.errors, []);
});
