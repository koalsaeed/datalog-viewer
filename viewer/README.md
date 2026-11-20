# Viewer page source

`viewer.html` is the source of the log viewer. The format readers live in
`prototype/readers/` (one file per ECU family) and are inlined at build time.

```
viewer/build.sh            # writes assets/viewer/index.html, the page the Android app loads
viewer/build.sh --check    # CI: fails if that page is not what the source builds
```

`viewer/build.sh --prototype OUT` also writes the phone-frame prototype page (the
shareable demo with notes). Both open `sample_cruise.emublog` on start; customer logs are
never embedded.

Edit `viewer.html` or a reader, run `viewer/build.sh`, then the tests in `tests/`.
