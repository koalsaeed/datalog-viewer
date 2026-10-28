# Supported log formats and how each was verified

Status of every reader in the clickable prototype
(https://claude.ai/artifact/LX5ane67KcZScjvz7jBmTP), which the Flutter app
will port. "Verified" means checked against real log files, not only against
files we generated ourselves.

| Format | Detection | Verified with | Result |
|---|---|---|---|
| HP Tuners `.hpl`, newer | `SS\0\0SYNC` | User's 2025 F-150 log + its VCM Scanner CSV export | 79/79 channels match VCM (r ≈ 0.99–1.00), text channels 96–100 % |
| HP Tuners `.hpl`, older | `HPT ` + `SS\0\0sync` | User's 2019 Mustang log | Decodes to the byte; names stored in the file |
| VCM Scanner CSV | `HP Tuners CSV Log File` | Same F-150 export | 79 channels, 10:58.9 |
| SCT LiveLink CSV | generic CSV | `assets/sample.csv` | 33 channels |
| MegaLogViewer `.mlg` v1/v2 | `MLVLG` | 6 test files of `karniv00l/mlg-converter` + rusEFI, Speeduino and MegaSquirt logs from UltraLog | Every raw value identical to the `mlg-converter` package (4.67 M values, 0 difference) |
| MoTeC `.ld` (i2 / M1 / M150) | u32 `0x40` at 0 | `Sample1.ld` from `afonso360/motec-i2` | 78 channels, names, units, sample counts, rates and first values match that project's tests |
| Haltech NSP export | `%DataLog%` | 2 real NSP logs from UltraLog's examples + Log2Dyno fixtures | Coolant, IAT, MAP, fuel/oil pressure, battery, lambda all physically sensible (scaling below) |
| MaxxECU `.MaxxECU-log` | tab-separated, `Name [id]` | Fixture built to the layout `whiiskerz/pullsheet` tests use | **No real file found online.** Needs a real log |
| ECUMaster CSV | generic CSV | 4 real logs (UltraLog) | Sparse columns held; 6:43 to 4 h logs |
| RomRaider, Woolich, MHD, Motorsport Electronics, BlueDriver (UTF-16), OBDLink, Torque, RaceChrono, DynamicEFI, Honda TuningStudio, MegaSquirt CSV | generic CSV | Real logs from UltraLog's examples | All open with sensible durations and channel ranges |
| Racelogic `.vbo` | `[column names]` | Self-made file; layout checked against `quentinsf/vboxutils` | **No real file found online** |

| AiM `.xrk` / `.xrz` | `<hCNF` / zlib | 9 test files of `m3rlin45/libxrk` + `pyxrk` + 3 BMW Thunderhill logs | 106/106 checks: channel sets, sample counts, values and lap boundaries against libxrk's DLL-derived expectations; RaceStudio CSV exports agree within CSV rounding; .xrk and .xrz decode bit-identically |
| ECUMaster EMU Black `.emublog` | gzip, 308-byte records | `sample_cruise` + `220kpa` | 19,500 values vs emublog2mlv's reference `.msl`, 0 mismatches |
| ECUMaster EMU PRO `.emuprolog.gz` | gzip → `ef 65 6d 6c` | 3 real logs + ECUMaster's own CSV exports of the same sessions | 3.8 M values, 0 mismatches; frame model predicts all 347,000 frames |
| Link `.llg` / `.llg5` | `lf3` | 4 real logs (G4+ and G5) | Parses byte-exact to EOF; no reference export exists, values checked for physical plausibility |
| FuelTech `.ftml` | raw DEFLATE → .NET BinaryFormatter | 2 real FT450 logs + the reference CSV made with FTManager's own libraries | All 33 columns identical on the WOT log; second log within 0.55 % of FTManager's export |

Readers for these binary formats live in `prototype/readers/` (plain JS,
port to Dart for the app). Their licence notices are in
`prototype/readers/THIRD_PARTY_NOTICES.txt`.

Known limits:
- **Link:** units rest on plausibility only (°C and km/h are not strictly
  proven). One G5 log ends with ~0.8 s where every channel holds another
  channel's bytes; the viewer drops that tail and says so.
- **AiM:** one undocumented expansion-message variant is skipped (3.4 KB of
  19 MB in one BMW file); some unconnected sensors read nonsense.
- **ECUMaster EMU PRO:** only 5 of the CSV-checked channels vary, so the other
  ~400 rest on the exact frame-length model and cross-checks; gaps longer than
  1 s are not detectable; custom 8-bit user channels keep generic names.
  The largest log (143 MB inflated) needs ~450 MB of memory while parsing,
  which is a risk on phones.
- **FuelTech:** `.ftl` (older FTManager) is not covered (no samples found);
  units assume FTManager's default unit settings.

Not read yet: Emerald `.lg1`/`.lg2`, DynamicEFI `.dat`, Haltech's native NSP
log file (only its CSV export), MaxxECU `.MaxxECU-Zip-log` (a zip; needs unzip
support), ECUMaster `.emublog3` (EMU Black V3).

## Haltech NSP scaling

Values are integers in each `Type`'s base unit:

| Type | Value | Check against the real log |
|---|---|---|
| EngineSpeed | raw rpm | idle 1066 rpm target |
| Percentage, Angle | ÷10 | ignition 23° at idle |
| Temperature | ÷10 − 273.15 → °C | coolant 70.4 °C, IAT 43 °C |
| Pressure | ÷10 → kPa absolute; channels whose DisplayMaxMin minimum is 1013 are gauge (− 101.3) | MAP 42.3 kPa idle; fuel 294 kPa (43 psi) |
| AbsPressure | ÷10 kPa | |
| BatteryVoltage | ÷1000 V | 13.17 V |
| AFR (lambda) | ÷1000 | target 0.944 λ |
| Ratio, GearRatio | ÷1000 | pressure ratio 0.417 = 42.3 / 101.3 |
| Time_us | ÷1000 → ms | dead time 1.03 ms |
| Speed | ÷10 km/h | |
| Decibel | ÷100 | |
| other | raw | |

Values ≤ −2 147 483 000 are "no sensor" and become gaps.

## Generic CSV rules

- Separator: the one that splits the most lines into the same number of cells;
  `;` and tab beat `,` on a tie. With `;` or tab, `14,00` is read as 14.00.
- Header block: the run of text rows right above the first data row; the first
  is names, the second units (a third, like RaceChrono's source row, is ignored).
- `Name [12]` (MaxxECU): a bracketed number is a channel ID, not a unit.
- Time column: `time/t/et/timestamp/offset/seconds` first, then
  `runtime/elapsed/device time/duration`, then anything with "time"; among
  matches the one with the most distinct readable values. Reads seconds, ms
  (`ms`/`msec` in the name), `hh:mm:ss(.fff)` and full dates.
- Time only moves forward: a restarted clock continues where it stopped, and
  rows that share one coarse stamp are spread across that second.
- Empty or `-` cells hold the previous value (ECUMaster writes values only when sampled).
- Text encodings: UTF-8, UTF-16 with BOM, Windows-1252 fallback.

## Licences of the reference projects

UltraLog is AGPL-3.0, so none of its code is used; only its example log files
were used as test inputs, and the readers here were written independently.
`mlg-converter` (MIT) was run as a reference to compare values. MoTeC facts come
from `motec-i2`'s tests.
