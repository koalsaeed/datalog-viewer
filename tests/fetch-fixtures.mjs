// Downloads the public sample logs listed in fixtures/manifest.json into .cache/fixtures.
// They stay in their own repositories (several are not ours to redistribute); each file is
// pinned to a commit and checked against its SHA-256, so a test never runs on a changed file.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync } from 'node:fs';
import { CACHE, MANIFEST } from './helpers.mjs';

const sha256 = p => createHash('sha256').update(readFileSync(p)).digest('hex');

mkdirSync(CACHE, { recursive: true });
let fetched = 0;
for (const f of MANIFEST) {
  const dest = `${CACHE}/${f.file}`;
  if (existsSync(dest) && sha256(dest) === f.sha256) continue;
  const tmp = `${dest}.part`;
  execFileSync('curl', ['-sSfL', '--retry', '3', '-o', tmp, f.url]);   // curl follows the proxy settings
  const got = sha256(tmp);
  if (got !== f.sha256) { rmSync(tmp); throw new Error(`${f.file}: SHA-256 ${got}, expected ${f.sha256} (${f.url})`); }
  renameSync(tmp, dest);
  fetched++;
}
console.log(`fixtures: ${MANIFEST.length} ready (${fetched} downloaded) in ${CACHE}`);
