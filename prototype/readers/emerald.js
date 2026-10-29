// Emerald ECU (K3 / K6 / M3D, "EMS" PC software) datalog reader: .lg1 (data) + .lg2 (channel list).
// No public spec was found; layout and channel table were worked out from 4 sample pairs
// (MG ZS Turbo, K6). See the report for evidence and per-channel confidence.
//
// .lg1  fixed 24-byte records, little-endian, no header/footer:
//         f64  timestamp, OLE Automation date (days since 1899-12-30, PC local wall clock, ~1 ms res.)
//         8 x u16 raw value of logger slot 1..8
//       Records whose timestamp is 0 are separators the PC logger writes when a triggered capture
//       stops (seen in one sample as runs of 5 copies of the previous values, followed by one more
//       real record and then a pause in time). They are dropped; one NaN row is inserted at the
//       pause so plots do not join across it (also at any pause > 5 s).
// .lg2  CRLF INI-like text: [chan1]..[chan8] each followed by one integer (Emerald variable id),
//       then [ValU] followed by 5 integers (logger unit settings). Only ValU[1] is understood:
//       it is the pressure unit of the MAP variable (1 = bar, raw/100; 2 = kPa, raw/10).
//       The .lg2 is written when the log is saved, so it describes the slot assignment at save
//       time: if a slot was re-assigned during recording, earlier samples carry the old variable
//       (observed in one sample; it cannot be detected from the file).

// id -> { n, u, k (multiplier), conf }. Values are raw * k. 'raw' entries have unknown scaling.
var EMERALD_CHANNELS = {
  1:  { n: 'AFR/Lambda sensor (raw)', u: '', k: 1, conf: 'identity probable, scaling unknown' },
  2:  { n: 'Air Temp', u: '°C', k: 1, conf: 'probable' },
  12: { n: 'Channel 12 (unknown)', u: '', k: 1, conf: 'unknown' },
  15: { n: 'Channel 15 (unknown, boost duty?)', u: '', k: 1, conf: 'unknown' },
  17: { n: 'Channel 17 (unknown)', u: '', k: 1, conf: 'unknown' },
  19: { n: 'Coolant Temp', u: '°C', k: 1, conf: 'high' },
  20: { n: 'RPM', u: 'rpm', k: 1, conf: 'high' },
  24: { n: 'Ignition Advance? (raw)', u: '', k: 1, conf: 'identity probable, scaling unknown' },
  26: { n: 'Injector Duty', u: '%', k: 0.1, conf: 'probable' },
  29: { n: 'Channel 29 (unknown)', u: '', k: 1, conf: 'unknown' },
  31: { n: 'Load Site', u: '', k: 1, conf: 'probable' },
  32: { n: 'MAP', u: null, k: null, conf: 'high (unit from [ValU])' },
  41: { n: 'Throttle', u: '%', k: 0.1, conf: 'probable' },
  45: { n: 'Throttle', u: '%', k: 0.1, conf: 'probable' },
  46: { n: 'TPS (raw sensor)', u: '', k: 1, conf: 'probable' },
  47: { n: 'Channel 47 (unknown)', u: '', k: 1, conf: 'unknown' },
};
var EMERALD_PRESSURE = { 1: { u: 'bar', k: 0.01 }, 2: { u: 'kPa', k: 0.1 } };

function emeraldOleOk(d) { return d > 29221 && d < 73051; } // 1980-01-01 .. 2099-12-31

function looksLikeEmeraldLg1(u8) {
  if (!u8 || u8.length < 48 || u8.length % 24 !== 0) return false;
  var dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  var n = Math.min(u8.length / 24, 64), first = null, prev = null, good = 0;
  for (var i = 0; i < n; i++) {
    var d = dv.getFloat64(i * 24, true);
    if (d === 0) continue;                         // segment separator
    if (!emeraldOleOk(d)) return false;
    if (first === null) first = d;
    if (Math.abs(d - first) > 2) return false;     // all within a couple of days
    if (prev !== null && d < prev - 1e-6) return false;
    prev = d; good++;
  }
  return good >= 2 || (good === 1 && u8.length === 24);
}

function parseEmeraldLg2(text) {
  var sec = null, slots = [], valu = [];
  var lines = String(text).replace(/^﻿/, '').split(/\r\n|\r|\n/);
  for (var i = 0; i < lines.length; i++) {
    var s = lines[i].trim();
    if (!s) continue;
    var m = /^\[(.+)\]$/.exec(s);
    if (m) { sec = m[1].toLowerCase(); continue; }
    if (!/^-?\d+$/.test(s)) continue;
    var v = parseInt(s, 10), c = /^chan(\d+)$/.exec(sec || '');
    if (c) { if (slots[+c[1] - 1] === undefined) slots[+c[1] - 1] = v; }
    else if (sec === 'valu') valu.push(v);
  }
  return { slots: slots, valu: valu };
}

function parseEmerald(lg1Buf, lg2Text, name) {
  var u8 = lg1Buf instanceof Uint8Array ? lg1Buf : new Uint8Array(lg1Buf);
  if (!looksLikeEmeraldLg1(u8)) throw new Error('Not an Emerald .lg1 file');
  var dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  var N = Math.floor(u8.length / 24);

  // pass 1: keep records with a valid timestamp; decide where a segment break (NaN row) goes.
  // In the samples a separator run is followed by exactly one more real record and then the
  // time gap where recording paused, so the break is put at the first gap > 0.25 s within
  // 3 real records after a separator run. Any gap > 5 s also gets a break.
  var keep = [], brk = [], d0 = null, sinceSep = -1, prevD = null, dropped = 0;
  for (var i = 0; i < N; i++) {
    var d = dv.getFloat64(i * 24, true);
    if (!emeraldOleOk(d)) { dropped++; if (d0 !== null) sinceSep = 0; continue; }
    if (d0 === null) d0 = d;
    var b = false;
    if (prevD !== null) {
      var gap = (d - prevD) * 86400;
      if (gap > 5) b = true;
      if (sinceSep >= 0) {
        if (gap > 0.25) { b = true; sinceSep = -1; }
        else if (++sinceSep > 3) sinceSep = -1;
      }
    }
    keep.push(i); brk.push(b); prevD = d;
  }
  var nb = 0;
  for (i = 0; i < brk.length; i++) if (brk[i]) nb++;
  var rows = keep.length + nb;
  var t = new Float64Array(rows), raw = [];
  for (var k = 0; k < 8; k++) raw.push(new Float64Array(rows));
  var r = 0, last = 0, backwards = 0, segments = [{ start: 0 }];
  for (var j = 0; j < keep.length; j++) {
    var o = keep[j] * 24;
    d = dv.getFloat64(o, true);
    var ts = Math.round((d - d0) * 86400000) / 1000;          // ms resolution
    if (ts < last) { ts = last; backwards++; }
    if (brk[j]) {
      t[r] = last; for (k = 0; k < 8; k++) raw[k][r] = NaN; r++;
      segments[segments.length - 1].end = last; segments.push({ start: ts });
    }
    t[r] = ts;
    for (k = 0; k < 8; k++) raw[k][r] = dv.getUint16(o + 8 + 2 * k, true);
    last = ts; r++;
  }
  segments[segments.length - 1].end = last;

  var cfg = lg2Text != null ? parseEmeraldLg2(lg2Text) : null;
  var valu = cfg ? cfg.valu : [];
  var notes = [];
  var ch = [];
  for (k = 0; k < 8; k++) {
    var id = cfg ? cfg.slots[k] : undefined, v = raw[k], c = { n: '', u: '', v: v, slot: k + 1, id: id };
    if (id === undefined) {
      c.n = 'Slot ' + (k + 1) + ' (id ?)';
    } else {
      var def = EMERALD_CHANNELS[id];
      if (!def) { c.n = 'Channel ' + id + ' (unknown)'; }
      else {
        var kk = def.k, uu = def.u, nm = def.n;
        if (id === 32) {
          var p = EMERALD_PRESSURE[valu[1]];
          if (p) { kk = p.k; uu = p.u; }
          else {
            kk = 1; uu = ''; nm = 'MAP (raw, pressure unit code ' + (valu[1] === undefined ? '?' : valu[1]) + ')';
            notes.push('MAP pressure unit ' + (valu[1] === undefined ? 'missing in .lg2' : 'code ' + valu[1] + ' not understood') + ': raw values');
          }
        }
        c.n = nm; c.u = uu; c.conf = def.conf;
        if (kk !== 1) { var w = new Float64Array(v.length); for (i = 0; i < v.length; i++) w[i] = v[i] * kk; c.v = w; }
      }
    }
    ch.push(c);
  }
  // duplicate names (e.g. 41 and 45 are both "Throttle"; same id in two slots)
  var seen = {};
  for (k = 0; k < 8; k++) {
    var key = ch[k].n;
    if (seen[key]) ch[k].n = key + ' (slot ' + (k + 1) + (ch[k].id !== undefined ? ', id ' + ch[k].id : '') + ')';
    seen[key] = true;
  }
  if (cfg) {
    for (k = 1; k <= 5; k++) if (k !== 2 && valu[k - 1] !== undefined && valu[k - 1] !== 0)
      notes.push('[ValU] line ' + k + ' = ' + valu[k - 1] + ' (meaning unknown; samples all had 0, units may be off)');
  }

  var start = null;
  if (d0 !== null) {
    var ms = Math.round((d0 - 25569) * 86400000);               // OLE day 25569 = 1970-01-01
    start = new Date(ms).toISOString().replace('Z', '');        // wall clock as recorded (no time zone)
  }
  var src = 'Emerald ECU .lg1' + (cfg ? ' + .lg2' : ' (no .lg2: generic slot names, raw values)');
  if (notes.length) src += ' [' + notes.join('; ') + ']';
  return {
    name: name, source: src, t: t, ch: ch,
    meta: {
      start: start, records: N, rows: rows, separatorRecords: dropped, segments: segments,
      backwardsTimestamps: backwards, slotIds: cfg ? cfg.slots : null, valU: cfg ? valu : null,
    },
  };
}

if (typeof module !== 'undefined' && module.exports) module.exports = { looksLikeEmeraldLg1, parseEmerald, parseEmeraldLg2, EMERALD_CHANNELS };
