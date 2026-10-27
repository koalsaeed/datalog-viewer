# PWP Datalog Viewer — Redesign

Date: 2026-10-27
Status: draft, waiting for approval

## Goals

1. The chart uses the whole landscape screen. No fixed panels around it.
2. One way to do each thing. Remove the duplicated tools.
3. A clearer, branded look (PWP), defined in one theme object.
4. CSV only: SCT LiveLink and HP Tuners VCM Scanner CSV exports.
   `.hpl` files are recognised and the user is shown how to export them as CSV.
5. Pinch zoom that does what the user means, without accidental jumps.
6. The viewer can be dropped into the PWP Tune app by copying one folder.

Out of scope: live logging, equations, MLG/VBO, HPL decoding (separate
spike once 2–3 sample `.hpl` files exist), iOS, light theme.

## Integration shape (simplest option)

The app stays a single Flutter package. Everything that is the viewer lives
in `lib/viewer/`, and nothing in it imports from outside that folder.

```
lib/
  main.dart                    // 15-line shell: prefs, landscape, runApp
  viewer/
    datalog_viewer.dart        // public entry: DatalogViewer widget + exports
    theme/viewer_theme.dart    // ViewerTheme (colours, trace palette) + InheritedWidget
    model/vehicle_log.dart     // LogChannel, VehicleLog, gaps, nearestIndex
    parsing/csv_log_parser.dart
    parsing/log_loader.dart    // picker, decoding, .hpl detection
    state/view_prefs.dart      // SharedPreferences, keys prefixed `datalog_viewer.`
    ui/…                       // shell, chart, drawer, navigator, landing
```

Moving it to PWP Tune later means copying `lib/viewer/`, adding the
`file_selector` and `shared_preferences` dependencies, and opening
`DatalogViewer()` as a page. The colours can be changed with
`DatalogViewer(theme: ViewerTheme(...))`.

## Screen layout (landscape)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ☰  datalog3.csv · 33 ch · 0:31.0         t 0:15.52   ▤  ⤢  ⋮         │ 40 px
├──────────────────────────────────────────────────────────────────────┤
│ RPM            3 215 rpm                                       6 800 │
│   ╱╲    ╱╲╱╲      ┃                                                  │
│ THROTTLE          64.2 %                                         100 │
│        ╱‾‾‾‾╲     ┃                                                  │
│ LAMBSE B1         0.82 λ                                        1.10 │
│  ‾‾╲__╱‾‾‾‾╲__    ┃                                                  │
├──────────────────────────────────────────────────────────────────────┤
│ ▁▂▅▇▅▂▁▂▃▅▇█▇▅▃▂▁  [=====]  ▁▂▃                                     │ 40 px
└──────────────────────────────────────────────────────────────────────┘
```

- Android status and navigation bars are hidden (immersive sticky mode).
- **Top bar (40 px):** channels drawer `☰`, file summary, cursor time,
  lanes/overlay `▤`, fit `⤢`, overflow `⋮` (open file, value tags,
  sample log, about).
- **Chart:** fills the rest. In lane mode every lane shows its name,
  the value at the cursor with its unit, and the top/bottom of its scale at the right.
  In overlay mode a compact legend row at the top of the plot shows the same
  readings.
- **Navigator (40 px):** the minimap and the visible window in one strip. Dragging the
  window pans, tapping elsewhere centres the view there. It replaces the
  minimap, the pan bar and the ◀ ▶ buttons.
- **Channels drawer:** opens from the left (300 px). A pin button in its
  header docks it beside the chart (the chart narrows and stays fully visible);
  unpinned it floats over the chart with a scrim. `☰` and the drawer's `‹`
  button hide and show it in both modes, and the pin state is remembered. It has
  two sections: *In chart* (drag to reorder, eye to hide, tap the colour dot to isolate,
  ⋯ to rename/remove) and *All channels* (search, tap to add). It replaces
  the docked panel, the full-screen picker and the rename dialog.

Removed as duplicates: top docking and dock switching, bottom stats bar,
side VALUES column, pan bar, ＋/− buttons, cursor lock, focus mode,
full-screen channel picker, separate channel editor dialog.

## Gestures

| Input | Action |
|---|---|
| 1 finger on chart | move the cursor (tap or drag) |
| 2 fingers, spread mostly horizontal | zoom time around the fingers |
| 2 fingers, spread mostly vertical | zoom the value axis around the fingers |
| 2 fingers moving together | pan time (and value axis when it is zoomed) |
| Double tap | zoom ×2 in time at the tap point |
| Fit button | reset both axes |
| Navigator | pan / jump |

Sensitivity rules:
- A two-finger gesture first passes a dead zone (finger distance changes by less than 14 px,
  or the focal point moves by less than 8 px) before anything moves.
- Once outside the dead zone the axis is locked for the rest of the gesture: time zoom when
  the change in horizontal distance is ≥ 1.4× the change in vertical distance, value
  zoom when the reverse, otherwise pan only.
- The zoom factor is taken from the change in finger distance on the locked axis, so
  a vertical wobble no longer zooms the value axis.
- Time zoom is limited to 20 samples in view, value zoom to 0.1×–1× of the range.
- This logic is a pure Dart class (`GestureIntent`) and has unit tests.

## Look

Dark, high-contrast, one accent colour. `ViewerTheme.pwp`:

| Token | Value | Use |
|---|---|---|
| background | `#0D1014` | chart and page |
| surface | `#141920` | bars, drawer |
| raised | `#1B222B` | chips, menus |
| border | `#252E39` | grid, dividers |
| text | `#E7EBF0` | primary text |
| muted | `#8A96A6` | secondary text |
| accent | `#E31B23` | PWP red: active icons, cursor tag, navigator window |

Trace palette (8, chosen to read on the dark background and to differ from each other):
`#38BDF8 #4ADE80 #FACC15 #C084FC #2DD4BF #F472B6 #FB923C #CBD5E1`
(no red, so traces never compete with the brand accent).

Clickable prototype: https://claude.ai/artifact/LX5ane67KcZScjvz7jBmTP

Numbers use tabular figures. The cursor is a thin white line with an accent time tag.
The grid is lighter than now (dotted, 4 vertical divisions).

## CSV parsing

One parser, `parseCsvLog`, that handles:
- **SCT LiveLink:** `name|meta|…` headers, 31-character name truncation repair, `Time (sec)`.
- **HP Tuners VCM Scanner export:** preamble lines before the header row, an
  optional units row under the header, quoted fields, an `Offset`/`Time` column.
  The exact layout is confirmed against the sample file the user will send.
- **Generic:** `,` `;` or tab delimiters, UTF-8 with or without BOM, falling back to latin1.

How the header row is detected: the first row whose cell count matches the
dominant cell count of the following rows and that is mostly non-numeric.
A units row is a non-numeric row directly under the header; its cells become
channel units (units inferred from the name are the fallback).

`.hpl` (the bytes start with `HPT `) shows a sheet: "HP Tuners logs must be exported as
CSV from VCM Scanner: File → Export → CSV", with an Open CSV button.

## Behaviour kept from the current app

The lessons in the previous handoff carry over unchanged: time from the data
column only; the gap threshold taken from the median interval; NaN treated as a gap; a min/max
envelope per pixel column; auto-pick of channels on open; the viewport
survives channel changes; units read-only; English UI.

## Fixed bugs

- Reorder index mismatch with hidden channels (one list, one reorder path).
- Isolate chip colour mismatch (colour comes from one slot lookup).
- View prefs throttling that dropped the last change (save on change, not in build).

## Testing and delivery

- `test/` with parser tests (LiveLink sample, VCM-style file, quoted fields, BOM,
  semicolons, truncated names, units row), model tests (gap estimation,
  nearestIndex) and `GestureIntent` tests.
- `flutter analyze` and `flutter test` run locally in the session and in CI
  before `flutter build apk`.
- Remove `RUN-ME.md` (stale local paths); keep `CLOUD-BUILD.md`; the handoff
  document moves to `docs/HANDOFF.md` and is updated.
