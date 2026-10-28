# HP Tuners `.hpl` log format (as observed)

Worked out from one VCM Scanner log (`log-000027-20261027-125635-<VIN>.hpl`,
978 115 bytes, 79 channels, 10 min 59 s, 2025 Ford F-150). The whole file
decodes to the byte with the rules below. More logs are needed to confirm
anything marked *unverified*.

All integers are little-endian.

## Blocks

The file is a sequence of blocks. Each one starts with the 8-byte marker
`53 53 00 00 53 59 4E 43` (`"SS\0\0SYNC"`), then 6 bytes of timestamp, then
a tag at offset 14 of the block:

| Tag | Meaning |
|---|---|
| `SC\0\0` | First block: header and channel table (uncompressed) |
| `CDG\0` | Data: `u32 compressedLength` at +18, `u32 rawLength` at +22, raw-deflate payload at +26 |

The data is compressed with plain raw deflate (zlib `wbits=-15`) and **is not
encrypted**. Each data block covers about 10 s.

## Channel table (inside the `SC` block)

```
+33  u16  channel count
+35  u16  slot of channel 0
then, per channel:
     u32  channel ID
     f64  divisor
     f64  offset
     u8   (0 in every channel seen)
     u8   unit length, then unit text (UTF-8, e.g. "rpm", "λ", "°C")
     u16  slot of the next channel (absent after the last one)
```

Value = raw / divisor + offset (e.g. `1.28, -100` is the OBD fuel-trim formula).

**Channel names are not stored.** The file holds only the IDs; VCM Scanner
looks the names up in its own database. The low 16 bits of the ID are VCM
Scanner's channel number, which is the number its CSV export writes in the
`[Channel Information]` row (e.g. ID `0x04380857` → `2135` = Engine RPM).
`assets/hpt_channels.json` maps channel numbers to names; it was built from
the CSV export of the sample log and grows with every new export.

The middle byte of the ID tracks the unit (`0x38` rpm, `0xEE` λ, `0x9C` %,
`0x5B` kPa, `0xF1` °C …). Units in the `.hpl` are always metric; VCM
Scanner's CSV converts to the user's display units (psi, °F, lb·ft, mph).

The top byte of the channel ID gives the value type:

| ID top byte | Value |
|---|---|
| `0x02` | u8 |
| `0x04` | u16 |
| `0x09` | f32 |
| `0x0B` | text: u8 length + ASCII (e.g. gear `"3rd"`, `"Drive"`) |
| others | *unverified* (likely signed / 32-bit variants) |

## Records (inside a decompressed `CDG` payload)

```
u16  record count
per record:
     u24  time in ms since the logger started
     u8   item count
     per item:
          u8  slot; if bit 7 is set the channel was sampled but no value
              follows (the value did not change)
          value, sized by the channel's type
```

Records are change-only and their times are not strictly ordered inside a
block, so a reader sorts each channel's events by time and holds the last value.

## Validation against VCM Scanner

The CSV export of the same log (`[Channel Data]`, 23 672 rows) was compared
channel by channel with the decoded `.hpl`:

- All 79 channel numbers match, in table order.
- Numeric channels correlate at r ≈ 0.99–1.00, once VCM's unit conversion is
  applied (kPa→psi ×0.145, °C→°F, N·m→lb·ft ×0.7376, m/s→mph ×2.237,
  lb/min→lb/h ×60).
- Text channels (gear, shift state, torque source …) match 96–100 % of rows.
- Lower correlations only appear on slow, sparse channels (fuel lift pump
  actual, oil pressure, VCT mapped-point weights). VCM interpolates those
  between samples; this reader holds the last value.

## Reference implementation

`parseHpl()` in the clickable prototype
(https://claude.ai/artifact/LX5ane67KcZScjvz7jBmTP) decodes the sample log in
about 0.3 s in a browser and resamples to a shared 20 Hz time axis.
