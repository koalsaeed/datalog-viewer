# Viewer page source

`viewer.html` is the source of the log viewer. The format readers live in
`prototype/readers/` (one file per ECU family) and are inlined at build time.

```
viewer/build.sh            # writes assets/viewer/index.html, the page the Android app loads
viewer/build.sh --check    # CI: fails if that page is not what the source builds
```

`viewer/build.sh --prototype OUT F150.hpl MUSTANG.hpl` also writes the phone-frame
prototype page with two HP Tuners logs embedded as samples. Those are customer logs:
keep OUT outside the repository.

Edit `viewer.html` or a reader, run `viewer/build.sh`, then the tests in `tests/`.
