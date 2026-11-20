# Viewer tests

Browser tests for `assets/viewer/index.html`, the page the Android app loads. They run on
every push (`.github/workflows/tests.yml`) and before every APK build, which is manual
(`build-apk.yml`) and stops if they fail.

```
cd tests
npm ci
npx playwright install chromium   # skip where Chromium for this Playwright version is already installed
npm test
```

- `formats.test.mjs` opens every sample log and compares the source label, channel count,
  duration, the standard channels picked and their value ranges with `expected/formats.json`.
  After a deliberate change, run `npm run update-expected` and review the diff of that file.
- `ui.test.mjs` covers the panel, the channel strip, marks, the Android file bridge and ZIPs,
  including bugs first found on the phone.

Sample logs: `fixtures/own/` holds files made for this project. The public logs in
`fixtures/manifest.json` are downloaded from their own repositories (pinned commit, checked
SHA-256) into `.cache/`, because several are not ours to redistribute.

Customer logs never go in the repository. Put them in `tests/.private/` (ignored by git):
they are tested when present, with their results in `.private/expected.json`.

`VIEWER_PAGE=/path/to/page.html npm test` runs the tests on another build, e.g. an older
one, to check that a test catches the bug it is for.
