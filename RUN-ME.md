# How to run the first version

> **Do you want zero installs?** Use [`CLOUD-BUILD.md`](CLOUD-BUILD.md) instead.
> It builds the APK on GitHub — no Flutter, no Android Studio, no emulator.
> This file is the local-machine path, kept for when you want a 1-second
> feedback loop instead of a 7-minute one.

Everything below assumes Windows and PowerShell.

---

## Part A — one time setup (skip if already done)

1. **Git for Windows** — https://git-scm.com/download/win
2. **Flutter SDK** — https://docs.flutter.dev/get-started/install/windows
   - Extract the zip to `C:\dev\flutter` (no spaces, not in OneDrive)
   - Add `C:\dev\flutter\bin` to your user PATH
   - Close and reopen PowerShell
3. **Android Studio** — https://developer.android.com/studio
   - SDK Manager → SDK Platforms → latest Android API
   - SDK Manager → SDK Tools → **Android SDK Command-line Tools**
4. Accept licenses:
   ```powershell
   flutter doctor --android-licenses
   ```
5. Windows Developer Mode:
   ```powershell
   start ms-settings:developers
   ```
6. Create an emulator: Android Studio → Device Manager → Create Virtual Device →
   Pixel 7 → API 35 → Finish. Press ▶ to start it.
7. Check everything:
   ```powershell
   flutter doctor
   ```
   You need ✓ on **Flutter** and **Android toolchain**.

---

## Part B — create the project

```powershell
cd C:\dev
flutter create datalog_viewer
```

## Part C — copy the code in

Replace the generated `lib` folder with the one in this workspace, and add the
sample log as an asset:

```powershell
$src = "C:\Users\k-als\Documents\deepseek-harness\default-workspace\car-datalog\app"
$dst = "C:\dev\datalog_viewer"

Remove-Item -Recurse -Force "$dst\lib"
Copy-Item -Recurse -Force "$src\lib" "$dst\lib"
Copy-Item -Recurse -Force "$src\assets" "$dst\assets"
```

## Part D — register the asset

Open `C:\dev\datalog_viewer\pubspec.yaml`, find:

```yaml
flutter:
  uses-material-design: true
```

and add two lines under it (indentation matters — two spaces):

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/sample.csv
```

## Part E — run

```powershell
cd C:\dev\datalog_viewer
flutter pub get
flutter run
```

With the emulator running, Flutter picks it automatically. Press **Ctrl+Left**
inside the emulator window to rotate it to landscape.

> First run downloads Gradle and dependencies. Expect **5–15 minutes**. Later
> runs take seconds.

---

## What you should see

```
┌───────────────────────────────────────────────────────────────┐
│ 📈 datalog3.csv   33 channels  1787 samples  0:31.0    t = 0:15.5 │
├──────────────┬────────────────────────────────────────────────┤
│ CHANNELS  33 │                                                │
│ ▍rpm    3200 │        ╱╲                                      │
│  rpm         │   ╱╲  ╱  ╲   ╱╲                                │
│ ▍throttle    │  ╱  ╲╱    ╲ ╱  ╲                               │
│ ▍lambse      │                                                │
│ ▍vehicle sp  │                    ┃                           │
│  ...         │                    ┃                           │
└──────────────┴────────────────────────────────────────────────┘
```

- **Left:** all 33 channels. Four are pre-selected (rpm, throttle, lambse,
  vehicle speed) and shown with a coloured bar + live value.
- **Middle:** the four traces, each normalised to its own min/max.
- **White vertical line:** the cursor. Tap or drag anywhere on the chart to move
  it — the values on the left update.
- Tap any channel to add it (up to 8), tap again to remove it.

---

## If something breaks

| Symptom | Fix |
|---|---|
| `Target file "lib/main.dart" not found` | Part C failed — check `C:\dev\datalog_viewer\lib` contains `main.dart` |
| `Unable to load asset: assets/sample.csv` | Part D missing, or indentation wrong. Then `flutter clean` + `flutter pub get` |
| `No supported devices found` | Start the emulator first |
| Gradle download hangs | Normal on first run; needs a stable connection |
| Text overflow warnings in console | Harmless for now |
