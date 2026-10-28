// Link ECU (PCLink) datalog reader: .llg (G4+/PC datalog) and .llg5 (G5 ECU internal / PC datalog).
// Format reverse-engineered from sample files; no public spec. See report for confidence levels.
//
// Container: a sequence of blocks, little-endian:
//   u32 blockLen (includes this header) | 3-byte ASCII tag | payload
//   "lf3" (215 B)  file header : @7 u32 channelCount, @211 u32 markerCount
//   "ld2" (7207 B) log info    : 36 UTF-16LE fields x 200 B starting @7
//                                 (#3 ECU model, #29 date, #30 time, #31/#32 version strings,
//                                  #33 source, #34 serial no., #35 title)
//   "lm1" (433 B)  marker      : @7 u8 flag, @8 UTF-16LE text (200 B), @208 f64 time [s]
//   "ds3" (645 B)  channel     : @7 u32 sampleCount, @211 u32 channel id,
//                                 @215 UTF-16LE name (200 B), @415 UTF-16LE unit (200 B),
//                                 @615 u32 unitIsQuantityClass (1 => unit text is e.g. "Pressure"),
//                                 @620 f64 nominal sample interval [s]
//                  followed directly (outside blockLen) by sampleCount x { f32 time [s], f32 value }.
// Every channel has its own time base, so the result uses the `series` form.

function looksLikeLink(u8) {
  if (!u8 || u8.length < 230) return false;
  const len = u8[0] | (u8[1] << 8) | (u8[2] << 16) | (u8[3] << 24);
  if (len !== 215) return false;
  if (u8[4] !== 0x6c || u8[5] !== 0x66 || u8[6] !== 0x33) return false; // "lf3"
  return u8[219] === 0x6c && u8[220] === 0x64 && u8[221] === 0x32;     // next block "ld2"
}

function parseLink(buf, name) {
  const u8 = new Uint8Array(buf);
  const dv = new DataView(buf);
  const N = u8.length;
  if (!looksLikeLink(u8)) throw new Error('Not a Link ECU .llg/.llg5 file');

  const str16 = (off, maxBytes) => {
    let s = '';
    const end = Math.min(off + maxBytes, N - 1);
    for (let i = off; i + 1 <= end; i += 2) {
      const c = u8[i] | (u8[i + 1] << 8);
      if (c === 0) break;
      s += String.fromCharCode(c);
    }
    return s;
  };
  const tagAt = (o) => String.fromCharCode(u8[o + 4], u8[o + 5], u8[o + 6]);

  // Quantity-class units: values appear to be stored in Link's base (metric) units.
  const CLASS_UNITS = { Temperature: '°C', Pressure: 'kPa', Lambda: 'λ', Speed: 'km/h' };

  const meta = {};
  const markers = [];
  const raw = [];
  let declaredChannels = null;
  let truncated = false;
  let o = 0;

  while (o + 7 <= N) {
    const len = dv.getUint32(o, true);
    const tag = tagAt(o);
    if (len < 7 || o + len > N || !/^[a-z]{2}[0-9]$/.test(tag)) break; // unknown/garbage => stop

    if (tag === 'lf3') {
      declaredChannels = dv.getUint32(o + 7, true);
      o += len;
    } else if (tag === 'ld2') {
      const f = (k) => str16(o + 7 + 200 * k, 200).trim();
      meta.ecu = f(3); meta.date = f(29); meta.time = f(30);
      meta.version1 = f(31); meta.version2 = f(32);
      meta.logSource = f(33); meta.serial = f(34); meta.title = f(35);
      o += len;
    } else if (tag === 'lm1') {
      if (len >= 216) markers.push({ t: dv.getFloat64(o + 208, true), text: str16(o + 8, 200), flag: u8[o + 7] });
      o += len;
    } else if (tag === 'ds3') {
      if (len < 628) break;
      let n = dv.getUint32(o + 7, true);
      const id = dv.getUint32(o + 211, true);
      const chName = str16(o + 215, 200).trim();
      let unit = str16(o + 415, 200).trim();
      const isClass = dv.getUint32(o + 615, true) === 1;
      const interval = dv.getFloat64(o + 620, true);
      const dataOff = o + len;
      const avail = Math.floor((N - dataOff) / 8);
      if (n > avail) { n = avail; truncated = true; }
      const t = new Float64Array(n), v = new Float64Array(n);
      for (let i = 0, p = dataOff; i < n; i++, p += 8) {
        t[i] = dv.getFloat32(p, true);
        v[i] = dv.getFloat32(p + 4, true);
      }
      const uClass = isClass ? unit : undefined;
      if (isClass && CLASS_UNITS[unit]) unit = CLASS_UNITS[unit];
      raw.push({ id, n: chName, u: unit, uClass, interval, t, v });
      o = dataOff + 8 * n;
      if (truncated) break;
    } else {
      o += len; // unknown but well-formed block: skip
    }
  }
  if (!raw.length) throw new Error('Link log: no channels found');
  if (o < N) truncated = true;

  // Common zero: earliest timestamp (G4+ PC logs start negative with a "History" pre-roll).
  let t0 = Infinity;
  for (const c of raw) if (c.t.length && c.t[0] < t0) t0 = c.t[0];
  if (!isFinite(t0)) t0 = 0;

  // Duplicate names exist (e.g. "AN 3 - ..." twice in G4+ logs): the copy with most samples keeps
  // the plain name, the others get " (id <channel id>)".
  const best = new Map();
  for (const c of raw) {
    const nm = c.n || ('Channel ' + c.id);
    const b = best.get(nm);
    if (!b || c.t.length > b.t.length) best.set(nm, c);
  }
  const series = raw.map((c) => {
    for (let i = 0; i < c.t.length; i++) c.t[i] -= t0;
    // enforce non-decreasing time (never observed to be violated in samples)
    for (let i = 1; i < c.t.length; i++) if (c.t[i] < c.t[i - 1]) c.t[i] = c.t[i - 1];
    let nm = c.n || ('Channel ' + c.id);
    if (best.get(nm) !== c) nm = nm + ' (id ' + c.id + ')';
    const s = { n: nm, u: c.u, t: c.t, v: c.v, id: c.id, rate: c.interval > 0 ? 1 / c.interval : undefined };
    if (c.uClass) s.uClass = c.uClass;
    return s;
  });

  const ext = /\.llg5$/i.test(name || '') ? 'llg5' : 'llg';
  return {
    name,
    source: 'Link ECU ' + ext + (meta.ecu ? ' (' + meta.ecu + ')' : ''),
    series,
    markers: markers.map((m) => ({ t: m.t - t0, text: m.text, flag: m.flag })),
    meta: Object.assign(meta, { t0, declaredChannels, parsedChannels: series.length, truncated }),
  };
}

if (typeof module !== 'undefined' && module.exports) module.exports = { looksLikeLink, parseLink };
