// Shared set-up: opens the app's viewer page in Chromium and loads logs through its file field.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright';

const here = new URL('.', import.meta.url).pathname;
// VIEWER_PAGE=path/to/page.html tests another build (e.g. an older one, to see a test catch its bug).
export const PAGE = process.env.VIEWER_PAGE ? pathToFileURL(process.env.VIEWER_PAGE).href : new URL('../assets/viewer/index.html', import.meta.url).href;
export const CACHE = `${here}.cache/fixtures`;
export const OWN = `${here}fixtures/own`;
// Logs that must never be committed (customer logs, files with a VIN in the name) go in
// tests/.private/. They are tested when present, with their results in .private/expected.json.
export const PRIVATE = `${here}.private`;
export const MANIFEST = JSON.parse(readFileSync(`${here}fixtures/manifest.json`, 'utf8'));

// Every log to test, as groups of files opened together (an Emerald .lg1 with its .lg2).
export function fixtureGroups() {
  const sets = [
    { dir: CACHE, names: MANIFEST.map(f => f.file), expected: `${here}expected/formats.json` },
    { dir: OWN, names: readdirSync(OWN), expected: `${here}expected/formats.json` },
  ];
  if (existsSync(PRIVATE)) sets.push({ dir: PRIVATE, names: readdirSync(PRIVATE).filter(n => n !== 'expected.json'), expected: `${PRIVATE}/expected.json` });
  const groups = [];
  for (const s of sets) {
    for (const n of s.names.sort()) {
      if (/\.lg2$/i.test(n) || n.endsWith('.part')) continue;
      const files = [`${s.dir}/${n}`];
      const lg2 = n.replace(/\.lg1$/i, '.lg2');
      if (lg2 !== n && s.names.includes(lg2)) files.push(`${s.dir}/${lg2}`);
      groups.push({ key: n, files, expected: s.expected });
    }
  }
  return groups;
}

export async function launch({ touch = false } = {}) {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 900, height: 420 }, hasTouch: touch, isMobile: touch });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(PAGE);
  await page.waitForFunction(() => document.getElementById('fmeta').textContent, null, { timeout: 30000 });   // boot sample is open
  return { browser, context, page, errors, close: () => browser.close() };
}

// Opens files through the page's own file field. Returns what the page shows afterwards.
export async function openFiles(page, files) {
  await page.evaluate(() => { document.getElementById('fmeta').textContent = ''; document.getElementById('toast').textContent = ''; });
  await page.setInputFiles('#fileIn', files);
  await page.waitForFunction(() => document.getElementById('fmeta').textContent || /Could not/.test(document.getElementById('toast').textContent), null, { timeout: 90000 });
  await page.waitForTimeout(150);
  return page.evaluate(() => {
    const st = window.__pwpReaders.state();
    return {
      meta: document.getElementById('fmeta').textContent,
      toast: document.getElementById('toast').textContent,
      error: document.getElementById('loading').hidden ? '' : document.getElementById('loading').textContent,
      channels: st ? st.ch : [],
      picked: [...document.querySelectorAll('#inList .row.sel .nm')].map(e => e.textContent),
    };
  });
}

export const panelOpen = page => page.evaluate(() => document.getElementById('drawer').classList.contains('open'));
export async function showPanel(page, { pin = false } = {}) {
  if (!(await panelOpen(page))) await page.click('#bDrawer');
  const pinned = await page.evaluate(() => document.getElementById('screen').classList.contains('docked'));
  if (pin !== pinned) await page.click('#bPin');
  await page.waitForTimeout(250);
}
