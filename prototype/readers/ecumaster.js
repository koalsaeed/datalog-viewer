// ECUMaster datalog reader: EMU Black ".emublog" (V2) and EMU PRO ".emuprolog(.gz)".
// Plain browser JS: no imports, no DOM. Expects in scope:
//   inflateRaw(u8, expectedSizeOrUndefined) -> Uint8Array   (raw DEFLATE, no headers)
//   td  (a TextDecoder('utf-8'))
//
// Exports (globals): looksLikeEmublog(u8), looksLikeEmuPro(u8), parseEcuMaster(buf, name)
//
// ---------------------------------------------------------------------------------------------
// EMU Black .emublog (V2): gzip -> 12-byte header (starts 82 60 44 22) + fixed 308-byte records,
// little-endian.  Channel offsets/scales and the frameStamp time base are ported from the
// MIT-licensed emublog2mlv project (src/emublog2mlv/core.py, (c) zazzn, MIT License).
// Result: common time base { t, ch }.
//
// ---------------------------------------------------------------------------------------------
// EMU PRO .emuprolog (reverse-engineered from sample files, no public spec; big-endian):
//   gzip -> 128-byte file header (ef 65 6d 6c ".eml" ...) then a chain of frames, each starting
//   on an 8-byte boundary:
//     u8 tag (0xE?) | u8 seq | u16 len (incl. this header) | u16 crc? | payload[len-6]
//   tag E3: payload = zlib stream with the self-describing channel schema (see parseSchema)
//   tag E9: custom CAN / user channel definitions (names, unit, float scale+offset)
//   tag EC: logging layout (which channels at which rate) - two identical copies
//   tag ED: sample frame: u16 layoutId | u32 timestamp(26-bit counter) | samples | 0x40 | pad
//           (some frames carry further tagged records after the 0x40 byte; ignored)
//   Each ED frame covers 40 ms = two 20 ms ticks; seq counts frames modulo 25 (1 s cycle).
//   Channel numbering used by the layout: all 1-byte channels (tree order), then 4-byte channels
//   (2 index units each), then 2-byte channels.  Rate classes in the layout (low nibble):
//     0: 500 Hz (10 samples/tick)  3: 50 Hz  4: 25 Hz  5: 10 Hz  6: 5 Hz  7: 1 Hz
//     (1 = 250 Hz and 2 = 100 Hz are guesses, never seen in the samples).
//   Frame body: [ticks A: >=25 Hz channels][tick B: >=50 Hz channels][10 Hz slice for tick A]
//               [10 Hz slice for tick B][5 Hz slice (seq%5)][1 Hz slice (seq)]
//   each part ordered 4-byte list, 2-byte list, 1-byte list, ascending channel index.
//   Time = tick * 20 ms, ticks counted from seq (gaps of dropped frames reconstructed modulo
//   25 frames, which is what ECUMaster's own CSV export does).  10 Hz slices are stamped the
//   way the ECUMaster client exports them (see keyShift).  Note: comparing 10 Hz per-cylinder
//   ignition angles with the 25 Hz ignition angle suggests slow-group values are really sampled
//   at the end of their frame (0-40 ms later than stamped); we follow the client convention.
// Result: { name, source, series:[{ n, u, t, v, labels?, codes?, dp? }] }  (per-channel time bases;
//   channels that never change are emitted as two points: first and last sample time).
// ---------------------------------------------------------------------------------------------

/* ------------------------------------------------------------------ gzip helpers */

function emuGzipInfo(u8) {
  // returns { start: offset of raw deflate data, isize } or null if not gzip
  if (!u8 || u8.length < 18 || u8[0] !== 0x1f || u8[1] !== 0x8b || u8[2] !== 8) return null;
  var flg = u8[3], p = 10;
  if (flg & 4) { p += 2 + (u8[p] | (u8[p + 1] << 8)); }            // FEXTRA
  if (flg & 8) { while (p < u8.length && u8[p] !== 0) p++; p++; }   // FNAME
  if (flg & 16) { while (p < u8.length && u8[p] !== 0) p++; p++; }  // FCOMMENT
  if (flg & 2) p += 2;                                              // FHCRC
  if (p >= u8.length) return null;
  var n = u8.length;
  var isize = (u8[n - 4] | (u8[n - 3] << 8) | (u8[n - 2] << 16) | (u8[n - 1] << 24)) >>> 0;
  return { start: p, isize: isize };
}

function emuGunzip(u8) {
  var g = emuGzipInfo(u8);
  if (!g) return u8;                                   // already decompressed
  var out = inflateRaw(u8.subarray(g.start, u8.length - 8), g.isize || undefined);
  return out instanceof Uint8Array ? out : new Uint8Array(out);
}

// Minimal raw-DEFLATE decoder used only to sniff the first few output bytes (no full inflate).
// Returns Uint8Array(<= maxOut) or null on any error / truncation.
function emuPeekInflate(src, pos, maxOut) {
  var out = new Uint8Array(maxOut), op = 0, bitbuf = 0, bitcnt = 0, p = pos;
  function bits(n) {
    while (bitcnt < n) { if (p >= src.length) throw 1; bitbuf |= src[p++] << bitcnt; bitcnt += 8; }
    var v = bitbuf & ((1 << n) - 1); bitbuf >>>= n; bitcnt -= n; return v;
  }
  function build(lengths, n) {
    var count = new Uint16Array(16), sym = new Uint16Array(n), offs = new Uint16Array(16), i;
    for (i = 0; i < n; i++) count[lengths[i]]++;
    count[0] = 0;
    for (i = 1; i < 16; i++) offs[i] = offs[i - 1] + count[i - 1];
    for (i = 0; i < n; i++) if (lengths[i]) sym[offs[lengths[i]]++] = i;
    return { count: count, sym: sym };
  }
  function decode(h) {
    var code = 0, first = 0, index = 0;
    for (var len = 1; len < 16; len++) {
      code |= bits(1);
      var c = h.count[len];
      if (code - c < first) return h.sym[index + (code - first)];
      index += c; first += c; first <<= 1; code <<= 1;
    }
    throw 2;
  }
  var LB = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
  var LE = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
  var DB = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
  var DE = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
  try {
    for (;;) {
      var last = bits(1), type = bits(2), i;
      if (type === 0) {
        bitbuf = 0; bitcnt = 0;
        if (p + 4 > src.length) return null;
        var len = src[p] | (src[p + 1] << 8); p += 4;
        for (i = 0; i < len && op < maxOut; i++) { if (p >= src.length) return null; out[op++] = src[p++]; }
        if (op >= maxOut) return out;
      } else if (type === 1 || type === 2) {
        var lh, dh, l = new Uint8Array(320);
        if (type === 1) {
          for (i = 0; i < 144; i++) l[i] = 8; for (; i < 256; i++) l[i] = 9;
          for (; i < 280; i++) l[i] = 7; for (; i < 288; i++) l[i] = 8;
          lh = build(l, 288);
          var dl = new Uint8Array(30); for (i = 0; i < 30; i++) dl[i] = 5; dh = build(dl, 30);
        } else {
          var nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
          var ord = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15], cl = new Uint8Array(19);
          for (i = 0; i < ncode; i++) cl[ord[i]] = bits(3);
          var ch = build(cl, 19), idx = 0;
          while (idx < nlen + ndist) {
            var s = decode(ch), rep, val = 0;
            if (s < 16) { l[idx++] = s; continue; }
            if (s === 16) { if (!idx) return null; val = l[idx - 1]; rep = 3 + bits(2); }
            else if (s === 17) rep = 3 + bits(3); else rep = 11 + bits(7);
            while (rep--) l[idx++] = val;
          }
          lh = build(l.subarray(0, nlen), nlen);
          dh = build(l.subarray(nlen, nlen + ndist), ndist);
        }
        for (;;) {
          var sy = decode(lh);
          if (sy < 256) { out[op++] = sy; if (op >= maxOut) return out; continue; }
          if (sy === 256) break;
          sy -= 257; if (sy >= 29) return null;
          var ln = LB[sy] + bits(LE[sy]), ds = decode(dh);
          if (ds >= 30) return null;
          var dist = DB[ds] + bits(DE[ds]);
          if (dist > op) return null;
          while (ln--) { out[op] = out[op - dist]; op++; if (op >= maxOut) return out; }
        }
      } else return null;
      if (last) return out.subarray(0, op);
    }
  } catch (e) { return null; }
}

function emuPeek(u8, n) {
  var g = emuGzipInfo(u8);
  if (!g) return u8.subarray(0, Math.min(n, u8.length));
  return emuPeekInflate(u8, g.start, n);
}

/* ------------------------------------------------------------------ detection */

var EMUB_MAGIC = [0x82, 0x60, 0x44, 0x22];
var EMUB_HDR = 12, EMUB_REC = 308;

function looksLikeEmublog(u8) {
  if (!u8 || u8.length < 20) return false;
  var head = emuPeek(u8, 16), g = emuGzipInfo(u8);
  var magicOk = !!head && head.length >= 4 &&
    head[0] === EMUB_MAGIC[0] && head[1] === EMUB_MAGIC[1] && head[2] === EMUB_MAGIC[2] && head[3] === EMUB_MAGIC[3];
  if (!g) return magicOk && (u8.length - EMUB_HDR) % EMUB_REC === 0;
  var sizeOk = g.isize >= EMUB_HDR + EMUB_REC && (g.isize - EMUB_HDR) % EMUB_REC === 0;
  if (head) return magicOk && sizeOk;
  return sizeOk;                                      // could not sniff: fall back to size rule
}

function looksLikeEmuPro(u8) {
  if (!u8 || u8.length < 20) return false;
  var head = emuPeek(u8, 8);
  return !!head && head.length >= 4 && head[0] === 0xef && head[1] === 0x65 && head[2] === 0x6d && head[3] === 0x6c;
}

function parseEcuMaster(buf, name) {
  var u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  if (looksLikeEmuPro(u8)) return parseEmuPro(u8, name);
  if (looksLikeEmublog(u8)) return parseEmublog(u8, name);
  throw new Error('Not an ECUMaster .emublog / .emuprolog file');
}

/* ------------------------------------------------------------------ EMU Black (.emublog V2) */

// Channel map ported from emublog2mlv core.py (MIT, (c) zazzn).  [name, unit, offset, kind, scale, bit]
// kind: 'u16' -> (b[o] + 256*b[o+1]) * scale, 'u8' -> b[o]*scale, 'flag' -> bit of u16 at o.
// (core.py's 'ChargeTemp' is omitted: it is the same bytes as IAT and flagged unseparated there.)
var EMUB_CHANNELS = [
  ['RPM', 'rpm', 2, 'u16', 1.0],
  ['MAP', 'kPa', 4, 'u16', 1.0],
  ['TPS', '%', 5, 'u16', 1 / 256],
  ['VE', '%', 11, 'u16', 1 / 10],
  ['IgnitionAngle', '°', 13, 'u8', 0.5],
  ['IgnFromTable', '°', 61, 'u16', 1 / 512],
  ['InjectorsPW', 'ms', 31, 'u16', 1 / 64],
  ['InjectorsDC', '%', 97, 'u16', 1 / 512],
  ['InjCalTime', 'ms', 15, 'u8', 1 / 32],
  ['ShortTermTrim', '%', 39, 'u16', 1 / 512],
  ['Lambda', 'λ', 43, 'u16', 1 / 128],
  ['LambdaTarget', 'λ', 189, 'u16', 1 / 100],
  ['IAT', '°C', 187, 'u16', 1 / 256],
  ['CLT', '°C', 115, 'u8', 1.0],
  ['OilTemp', '°C', 113, 'u8', 1.0],
  ['OilPressure', 'psi', 111, 'u16', 0.003541],
  ['FuelPressure', 'psi', 114, 'u8', 0.90643],
  ['IATCorrection', '%', 99, 'u16', 1 / 256],
  ['Ethanol', '%', 125, 'u16', 1 / 512],
  ['AirFlow', '', 256, 'u16', 1 / 256],
  ['CAM1valveDC', '%', 104, 'u16', 1 / 256],
  ['AccelEnrichment', '%', 37, 'u8', 1.0],
  ['AccelEnrichmentPW', 'ms', 38, 'u16', 1 / 62],
  ['KnockSensor', 'V', 19, 'u16', 7.66354e-5],
  ['BatteryVoltage', 'V', 8, 'u16', 1 / 37],
  ['BoostTarget', 'kPa', 84, 'u16', 1.0],
  ['BoostDC', '%', 81, 'u16', 1 / 256],
  ['BoostDCFromTable', '%', 83, 'u8', 1.0],
  ['IdleTarget', 'rpm', 23, 'u16', 1.0],
  ['FCustomCorrActive', '', 214, 'flag', 0, 11],
];

function parseEmublog(u8in, name) {
  var d = emuGunzip(u8in);
  if (d.length < EMUB_HDR + EMUB_REC) throw new Error('EMU Black log too short');
  var n = Math.floor((d.length - EMUB_HDR) / EMUB_REC), base = EMUB_HDR, i, j;
  // time base: frameStamp (u32 LE @304) is a 1 Hz seconds counter; spread records evenly
  // within each second (as emublog2mlv build_timebase does). Fallback: index / 25 Hz.
  var fs = new Float64Array(n), mono = true;
  for (i = 0; i < n; i++) {
    var q = base + i * EMUB_REC + 304;
    fs[i] = (d[q] | (d[q + 1] << 8) | (d[q + 2] << 16) | (d[q + 3] << 24)) >>> 0;
    if (i && fs[i] < fs[i - 1]) mono = false;
  }
  var t = new Float64Array(n);
  if (!mono || n < 2 || fs[n - 1] <= fs[0]) {
    for (i = 0; i < n; i++) t[i] = i / 25;
  } else {
    i = 0;
    while (i < n) {
      j = i; while (j < n && fs[j] === fs[i]) j++;
      var k = j - i;
      for (var r = 0; r < k; r++) t[i + r] = (fs[i] - fs[0]) + r / k;
      i = j;
    }
  }
  var ch = [], lam = null, lamT = null;
  EMUB_CHANNELS.forEach(function (c) {
    var v = new Float32Array(n), o = c[2], sc = c[4];
    for (var i = 0, p = base; i < n; i++, p += EMUB_REC) {
      if (c[3] === 'u16') v[i] = (d[p + o] | (d[p + o + 1] << 8)) * sc;
      else if (c[3] === 'u8') v[i] = d[p + o] * sc;
      else v[i] = ((d[p + o] | (d[p + o + 1] << 8)) >> c[5]) & 1;
    }
    if (c[0] === 'Lambda') lam = v;
    if (c[0] === 'LambdaTarget') lamT = v;
    ch.push({ n: c[0], u: c[1], v: v });
  });
  // gasoline-equivalent AFR views, as emublog2mlv writes them
  [['AFR', lam], ['AFRTarget', lamT]].forEach(function (a) {
    var v = new Float32Array(n);
    for (var i = 0; i < n; i++) v[i] = a[1][i] * 14.7;
    ch.push({ n: a[0], u: 'AFR', v: v });
  });
  return { name: name, source: 'ECUMaster EMU Black (.emublog)', t: t, ch: ch };
}

/* ------------------------------------------------------------------ EMU PRO (.emuprolog) */

// Parse the inflated E3 schema.  Layout (all integers big-endian):
//   u32 version | u32 ? | u16 nLeaves | u8 nStructs | zeros ... (18 bytes)
//   units:  NUL-terminated strings, index 0 = '' ... terminated by an empty string
//   groups: "engine/" "trigger/" ... (strings ending in '/')
//   enums:  u8 flags | name\0 | u8 count | count x { value (1/2/4 B) | label\0 }
//           flags: bit0 signed, bit4 bitfield (values are bit numbers), bits1-2 log2(storage size)
//   structs: u8 fieldCount | name\0          (field definitions are the first leaves, in order)
//   group table: (1 + nGroups) x { u8 childCount | u8 groupId | name\0 }   (id 0 = root)
//   leaves:  T | F | type-specific | key\0 | [display\0 if T&0x80]
//     T: low nibble type (0 u8,1 s8,2 u16,3 s16,4 bool,5 u32,6 s32,8 enum,9 struct), 0x10 array
//     enum:   enumIdx, [n if array], [extra if F&0x80]
//     struct: structIdx, [n if array]
//     number: [n if array], F&1 unit u8, F&2 min, F&4 max (type width), F&8 div u16,
//             F&0x10 mul u16, F&0x20 offset s16, F&0x80 decimals u8;  value = raw*mul/div + off
//     key '^' = value of the struct node itself; '$' in key/display = array index (1-based)
function emuParseSchema(s) {
  var p = 18, N = s.length;
  function cstr() { var e = p; while (e < N && s[e] !== 0) e++; var str = td.decode(s.subarray(p, e)); p = e + 1; return str; }
  var units = [];
  for (;;) { var u = cstr(); if (u === '' && units.length) break; units.push(u); if (p >= N) throw new Error('schema: units'); }
  var groups = [];
  for (;;) {
    var save = p, g = cstr();
    if (!g || g.charAt(g.length - 1) !== '/') { p = save; break; }
    groups.push(g);
  }
  var enums = [];
  var nameRe = /^e[A-Za-z0-9_]+$/;
  // Structs list follows the enums; find it by checking where a valid struct list + group table
  // (sequential group ids) starts.
  function structsAt(q) {
    var save = p; p = q;
    try {
      var list = [];
      for (;;) {
        var at = p, c = s[p]; p++;
        var nm = cstr();
        if (!c || !nameRe.test(nm)) { p = at; break; }
        list.push([nm, c]);
      }
      // the group table must follow: (1 + nGroups) entries with sequential ids 0..nGroups
      var q2 = p;
      for (var gi = 0; gi <= groups.length; gi++) {
        if (q2 + 1 >= N || s[q2 + 1] !== gi) return null;
        q2 += 2; while (q2 < N && s[q2] !== 0) q2++; q2++;
      }
      return list.length ? { list: list, end: p } : null;
    } finally { p = save; }
  }
  var st = null;
  for (;;) {
    st = structsAt(p);
    if (st) break;
    var fl = s[p++], ename = cstr(), cnt = s[p++];
    var w = (fl & 0x10) ? 1 : (1 << ((fl >> 1) & 3)), items = [];
    for (var k = 0; k < cnt; k++) {
      var v = 0;
      for (var b = 0; b < w; b++) v = v * 256 + s[p + b];
      if ((fl & 1) && !(fl & 0x10) && v >= Math.pow(2, 8 * w - 1)) v -= Math.pow(2, 8 * w);
      p += w;
      items.push([v, cstr()]);
    }
    enums.push({ flags: fl, name: ename, items: items, size: 1 << ((fl >> 1) & 3) });
    if (p >= N) throw new Error('schema: enums');
  }
  var structs = st.list; p = st.end;
  var gtab = [];
  for (var gi = 0; gi <= groups.length; gi++) { var c = s[p], id = s[p + 1]; p += 2; gtab.push([c, id, cstr()]); }
  var total = 0;
  structs.forEach(function (x) { total += x[1]; });
  gtab.forEach(function (x) { total += x[0]; });
  var W = [1, 1, 2, 2, 1, 4, 4, 4];
  function num(w, signed) {
    var v = 0; for (var b = 0; b < w; b++) v = v * 256 + s[p + b];
    if (signed && v >= Math.pow(2, 8 * w - 1)) v -= Math.pow(2, 8 * w);
    p += w; return v;
  }
  var leaves = [];
  for (var li = 0; li < total; li++) {
    var T = s[p++], ty = T & 15, arr = T & 0x10, F = s[p++], e = { ty: ty, F: F, n: 0 };
    if (ty === 9) { e.st = s[p++]; if (arr) e.n = s[p++]; }
    else if (ty === 8) { e.en = s[p++]; if (arr) e.n = s[p++]; if (F & 0x80) p++; }
    else {
      if (ty > 7) throw new Error('schema: unknown leaf type ' + ty + ' at ' + (p - 2));
      if (arr) e.n = s[p++];
      var w2 = W[ty], sg = ty === 1 || ty === 3 || ty === 6;
      if (F & 1) e.unit = s[p++];
      if (F & 2) e.min = num(w2, sg);
      if (F & 4) e.max = num(w2, sg);
      if (F & 8) e.div = num(2, false);
      if (F & 0x10) e.mul = num(2, false);
      if (F & 0x20) e.off = num(2, true);
      if (F & 0x40) throw new Error('schema: unknown field flag 0x40');
      if (F & 0x80) e.dec = s[p++];
    }
    e.key = cstr();
    if (T & 0x80) e.disp = cstr();
    leaves.push(e);
  }
  return { units: units, groups: groups, enums: enums, structs: structs, gtab: gtab, leaves: leaves };
}

// Flatten the schema into channels in tree order (struct fields expanded, arrays expanded).
function emuFlatten(S) {
  var sstart = [], acc = 0;
  S.structs.forEach(function (x) { sstart.push(acc); acc += x[1]; });
  var out = [];
  function visit(e, path) {
    var key = e.key, pth = key === '^' ? path : path + (path && path.charAt(path.length - 1) !== '/' ? '/' : '') + key;
    var reps = e.n ? e.n : 1;
    for (var r = 0; r < reps; r++) {
      var pp = e.n ? pth.split('$').join(String(r + 1)) : pth;
      if (e.ty === 9) {
        var k0 = sstart[e.st], cnt = S.structs[e.st][1];
        for (var j = 0; j < cnt; j++) visit(S.leaves[k0 + j], pp);
      } else out.push({ path: pp, e: e });
    }
  }
  var li = acc;
  S.gtab.forEach(function (g) {
    var prefix = g[1] ? S.groups[g[1] - 1] : '';
    for (var j = 0; j < g[0]; j++) visit(S.leaves[li++], prefix);
  });
  return out;
}

function emuChannelSize(S, e) {
  if (e.ty === 8) return S.enums[e.en].size;
  return [1, 1, 2, 2, 1, 4, 4, 4][e.ty];
}

// E9 frame: custom (CAN stream / user variable) channel definitions for custom/unifiedNChannels$.
function emuParseCustom(d, p, len) {
  var q = p + 6, end = p + len;
  if (q + 22 > end) return null;
  var n8 = (d[q + 4] << 8) | d[q + 5], n16 = (d[q + 6] << 8) | d[q + 7], n32 = (d[q + 8] << 8) | d[q + 9];
  var N = n8 + n16 + n32, o = q + 22, dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
  if (o + 12 * N > end) return null;
  var recs = [];
  for (var k = 0; k < N; k++, o += 12) recs.push({ meta: dv.getUint32(o, false), mul: dv.getFloat32(o + 4, false), off: dv.getFloat32(o + 8, false) });
  // names: u8 (bit7: one extra byte follows) | bits5-6 kind (0 = stream/group name, 1 = 8-bit,
  // 2 = 16-bit, 3 = 32-bit channel) | bits0-4 length ; then the name
  var names = { 1: [], 2: [], 3: [] }, firstSec = { 1: 0, 2: 0, 3: 0 }, seenStream = false;
  while (o < end && d[o]) {
    var b = d[o], ln = b & 31, kind = (b >> 5) & 3, ex = (b & 0x80) ? 1 : 0;
    if (o + 1 + ex + ln > end) break;
    var nm = td.decode(d.subarray(o + 1 + ex, o + 1 + ex + ln));
    o += 1 + ex + ln;
    if (!kind) { seenStream = true; continue; }
    names[kind].push(nm);
    if (!seenStream) firstSec[kind]++;
  }
  var res = { 8: [], 16: [], 32: [] }, cnts = { 8: n8, 16: n16, 32: n32 }, base = { 8: 0, 16: n8, 32: n8 + n16 };
  [[8, 1], [16, 2], [32, 3]].forEach(function (a) {
    var bits = a[0], list = names[a[1]], cnt = cnts[bits];
    // Names map 1:1 onto channel numbers when the counts agree; otherwise only trust the first
    // (CAN stream) section, whose order was verified against data.
    var usable = list.length === cnt ? cnt : Math.min(firstSec[a[1]], cnt);
    for (var k = 0; k < cnt; k++) {
      var r = recs[base[bits] + k];
      res[bits].push({ name: k < usable ? list[k] : null, unitIdx: r.meta & 0xffff, signed: !!(r.meta & 0x80000000),
        mul: r.mul, off: r.off });
    }
  });
  return res;
}

// EC frame: layout.  payload: u16 nLayouts, then nLayouts x { 52 x u16 header, entries }
//   header[0] layout byte size, header[1..12] = 4 groups x (n4B, n2B, n1B) entry counts,
//   header[13..17] 10 Hz slice sizes, [18..22] 5 Hz slice sizes, [23..51] 1 Hz slice sizes
//   (sizes in index units).  entry: u16 (index << 4 | rateCode), u8 count (index units).
function emuParseLayout(d, p) {
  var o = p + 8, H = [];
  for (var i = 0; i < 52; i++) H.push((d[o + 2 * i] << 8) | d[o + 2 * i + 1]);
  o += 104;
  var lists = [];
  for (var g = 0; g < 4; g++) {
    var gl = [];
    for (var t = 0; t < 3; t++) {
      var L = [];
      for (var k = 0; k < H[1 + g * 3 + t]; k++, o += 3) {
        var v = (d[o] << 8) | d[o + 1], c = d[o + 2], j0 = v >> 4, rc = v & 15;
        for (var j = j0; j < j0 + c;) { L.push([j, rc]); j += (t === 0) ? 2 : 1; }
      }
      gl.push(L);
    }
    lists.push(gl);
  }
  return { H: H, lists: lists, id: (d[p + 4] << 8) | d[p + 5] };
}

var EMUP_SPT = { 0: 10, 1: 5, 2: 2, 3: 1 };      // samples per 20 ms tick for rate codes 0..3

function parseEmuPro(u8in, name) {
  var d = emuGunzip(u8in), N = d.length, i, j, k;
  if (N < 136 || d[0] !== 0xef || d[1] !== 0x65 || d[2] !== 0x6d || d[3] !== 0x6c) throw new Error('Not an EMU PRO log');

  // ---- frame chain
  var edPos = new Int32Array(Math.max(16, (N / 700) | 0)), nEd = 0, schemaF = -1, customF = -1, layoutF = -1;
  var p = 128, skipped = 0, resync = false;
  function hdrOk(q) { var l = (d[q + 2] << 8) | d[q + 3]; return (d[q] & 0xf0) === 0xe0 && l >= 6 && q + l <= N; }
  while (p + 6 <= N) {
    var tag = d[p], len = (d[p + 2] << 8) | d[p + 3];
    // corrupt data: resync on the 8-byte grid, accepting a header only if the next one chains too
    var ok = hdrOk(p);
    if (ok && resync) { var nx = p + ((len + 7) & ~7); ok = nx + 6 > N || hdrOk(nx); }
    if (!ok) {
      if ((tag & 0xf0) === 0xe0 && len >= 6 && p + len > N && N - p < 65536) break;   // truncated tail
      p += 8; skipped += 8; resync = true; continue;
    }
    resync = false;
    if (tag === 0xed) {
      if (nEd === edPos.length) { var g2 = new Int32Array(edPos.length * 2); g2.set(edPos); edPos = g2; }
      edPos[nEd++] = p;
    } else if (tag === 0xe3 && schemaF < 0) schemaF = p;
    else if (tag === 0xe9 && customF < 0) customF = p;
    else if (tag === 0xec && layoutF < 0) layoutF = p;
    p += (len + 7) & ~7;
  }
  if (schemaF < 0 || layoutF < 0) throw new Error('EMU PRO: schema or layout frame missing');

  // ---- schema (E3: zlib)
  var sl = (d[schemaF + 2] << 8) | d[schemaF + 3], zs = schemaF + 6;
  if ((d[zs] & 0x0f) !== 8) throw new Error('EMU PRO: schema is not zlib');
  var zhdr = 2 + ((d[zs + 1] & 0x20) ? 4 : 0);
  var schemaBytes = inflateRaw(d.subarray(zs + zhdr, schemaF + sl - 4), undefined);
  var S = emuParseSchema(schemaBytes instanceof Uint8Array ? schemaBytes : new Uint8Array(schemaBytes));
  var flat = emuFlatten(S);

  // ---- numbering used by the layout: 1-byte, then 4-byte (2 units each), then 2-byte channels
  var byIdx = [], idxN = 0;
  [1, 4, 2].forEach(function (sz) {
    flat.forEach(function (c) { if (emuChannelSize(S, c.e) === sz) { c.size = sz; byIdx[idxN] = c; idxN += sz === 4 ? 2 : 1; } });
  });

  // ---- custom channel definitions
  var cust = customF >= 0 ? emuParseCustom(d, customF, (d[customF + 2] << 8) | d[customF + 3]) : null;

  // ---- layout and per-seq frame programs
  var LAY = emuParseLayout(d, layoutF), H = LAY.H, lists = LAY.lists;
  var chans = [], chanOf = new Map();   // used channels
  function chanFor(j) {
    var c = chanOf.get(j);
    if (c !== undefined) return c;
    var info = byIdx[j];
    if (!info) throw new Error('EMU PRO: layout references unknown channel ' + j);
    c = chans.length; chanOf.set(j, c); chans.push({ j: j, info: info, key: -1 });
    return c;
  }
  var keys = [];        // timing groups: { occ: [ per seq: array of tick offsets (in ticks) ] }
  function newKey() { var o = []; for (var s = 0; s < 25; s++) o.push([]); keys.push({ occ: o }); return keys.length - 1; }
  // program per seq: flat list of channel slots in byte order
  var progs = [], progLen = [];
  for (var s0 = 0; s0 < 25; s0++) { progs.push([]); progLen.push(12); }
  function addItem(s, c) { progs[s].push(c); progLen[s] += chans[c].info.size; }
  function setKey(c, kk) {
    if (chans[c].key === -1) chans[c].key = kk;
    else if (chans[c].key !== kk) throw new Error('EMU PRO: channel in two timing groups');
  }
  // group 0: >= 25 Hz channels, in both ticks of every frame
  var g0keys = {};
  [0, 1].forEach(function (tk) {
    lists[0].forEach(function (L) {
      L.forEach(function (it) {
        var rc = it[1], spt = rc === 4 ? 1 : EMUP_SPT[rc];
        if (spt === undefined) throw new Error('EMU PRO: unexpected rate code ' + rc + ' in fast group');
        if (rc === 4 && tk === 1) return;
        var c = chanFor(it[0]);
        if (g0keys[rc] === undefined) {
          g0keys[rc] = newKey();
          for (var s = 0; s < 25; s++) for (var t2 = 0; t2 < 2; t2++) {
            if (rc === 4 && t2) continue;
            for (var q = 0; q < spt; q++) keys[g0keys[rc]].occ[s].push(t2 + q / spt);
          }
        }
        setKey(c, g0keys[rc]);
        for (var s2 = 0; s2 < 25; s2++) for (var q2 = 0; q2 < spt; q2++) addItem(s2, c);
      });
    });
  });
  function slices(gl, units) {
    var seq = gl[0].concat(gl[1], gl[2]), out = [], kk = 0;
    units.forEach(function (u) {
      var sl2 = [], a = 0;
      while (a < u && kk < seq.length) { sl2.push(seq[kk][0]); a += byIdx[seq[kk][0]] && byIdx[seq[kk][0]].size === 4 ? 2 : 1; kk++; }
      out.push(sl2);
    });
    return out;
  }
  var S10 = slices(lists[1], H.slice(13, 18)), S5 = slices(lists[2], H.slice(18, 23)), S1 = slices(lists[3], H.slice(23, 48));
  var k10 = S10.map(function () { var kk = newKey(); keys[kk].tenHz = true; return kk; }), k5 = S5.map(function () { return newKey(); }), k1 = S1.map(function () { return newKey(); });
  for (var s = 0; s < 25; s++) {
    [0, 1].forEach(function (tk) {
      var si = (2 * s + tk) % 5;
      keys[k10[si]].occ[s].push(tk);
      S10[si].forEach(function (jj) { var c = chanFor(jj); setKey(c, k10[si]); addItem(s, c); });
    });
    keys[k5[s % 5]].occ[s].push(0);
    S5[s % 5].forEach(function (jj) { var c = chanFor(jj); setKey(c, k5[s % 5]); addItem(s, c); });
    if (s < S1.length) {
      keys[k1[s]].occ[s].push(0);
      S1[s].forEach(function (jj) { var c = chanFor(jj); setKey(c, k1[s]); addItem(s, c); });
    }
  }
  // program arrays: [slot, kind] with kind 0 u8, 1 s8, 2 u16, 3 s16, 4 u32, 5 s32
  chans.forEach(function (c) {
    var e = c.info.e, ty = e.ty, sz = c.info.size, sg;
    if (ty === 8) { var ef = S.enums[e.en].flags; sg = !!(ef & 1) && !(ef & 0x10); }
    else sg = ty === 1 || ty === 3 || ty === 6;
    c.custom = null;
    var m = /^custom\/unified(8|16|32)Channels(\d+)$/.exec(c.info.path);
    if (m && cust) { var cd = cust[m[1]][+m[2] - 1]; if (cd) { c.custom = cd; sg = cd.signed; } }
    c.kind = sz === 1 ? (sg ? 1 : 0) : sz === 2 ? (sg ? 3 : 2) : (sg ? 5 : 4);
  });
  var P = progs.map(function (pr) {
    var a = new Int32Array(pr.length * 2);
    for (var q = 0; q < pr.length; q++) { a[2 * q] = pr[q]; a[2 * q + 1] = chans[pr[q]].kind; }
    return a;
  });

  // ---- pass 1: validate frames, frame counter from seq, constancy per channel
  var NC = chans.length, first = new Float64Array(NC), seen = new Uint8Array(NC), varying = new Uint8Array(NC);
  var fcount = new Int32Array(nEd), valid = new Uint8Array(nEd), perSeq = new Int32Array(25);
  var prev = -1, fc = 0, nValid = 0, nBad = 0;
  for (var f = 0; f < nEd; f++) {
    var fp = edPos[f], sq = d[fp + 1], fl2 = (d[fp + 2] << 8) | d[fp + 3];
    if (sq >= 25 || ((d[fp + 6] << 8) | d[fp + 7]) !== LAY.id || progLen[sq] + 1 > fl2 || d[fp + progLen[sq]] !== 0x40) { nBad++; continue; }
    if (prev < 0) fc = 0; else { var dl = (sq - prev + 25) % 25; fc += dl ? dl : 25; }
    prev = sq; fcount[f] = fc; valid[f] = 1; nValid++; perSeq[sq]++;
    var pr2 = P[sq], o = fp + 12;
    for (var q3 = 0; q3 < pr2.length; q3 += 2) {
      var cs = pr2[q3], raw;
      switch (pr2[q3 + 1]) {
        case 0: raw = d[o]; o += 1; break;
        case 1: raw = (d[o] << 24) >> 24; o += 1; break;
        case 2: raw = (d[o] << 8) | d[o + 1]; o += 2; break;
        case 3: raw = ((d[o] << 24) | (d[o + 1] << 16)) >> 16; o += 2; break;
        case 4: raw = ((d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]) >>> 0; o += 4; break;
        default: raw = (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]; o += 4;
      }
      if (!seen[cs]) { seen[cs] = 1; first[cs] = raw; } else if (raw !== first[cs]) varying[cs] = 1;
    }
  }
  if (!nValid) throw new Error('EMU PRO: no decodable sample frames');

  // ---- allocate (only varying channels get full arrays; timing arrays shared per group)
  var keyN = new Int32Array(keys.length), keyUsed = new Uint8Array(keys.length);
  for (k = 0; k < keys.length; k++) { var nn = 0; for (var s3 = 0; s3 < 25; s3++) nn += perSeq[s3] * keys[k].occ[s3].length; keyN[k] = nn; }
  chans.forEach(function (c, ci) { if (varying[ci]) keyUsed[c.key] = 1; });
  var keyT = [], keyCur = new Int32Array(keys.length);
  for (k = 0; k < keys.length; k++) keyT.push(keyUsed[k] ? new Float64Array(keyN[k]) : null);
  var vals = [], vcur = new Int32Array(NC);
  for (i = 0; i < NC; i++) vals.push(varying[i] ? (chans[i].info.size === 4 ? new Float64Array(keyN[chans[i].key]) : new Float32Array(keyN[chans[i].key])) : null);
  var seqKeys = [];
  for (var s4 = 0; s4 < 25; s4++) { var lst = []; for (k = 0; k < keys.length; k++) if (keys[k].occ[s4].length) lst.push(k); seqKeys.push(lst); }
  var keyFirst = new Float64Array(keys.length).fill(NaN), keyLast = new Float64Array(keys.length).fill(NaN);
  // ECUMaster's own export stamps each 10 Hz slice on a fixed 100 ms grid anchored at the
  // *start* (tick A) of the first frame that carries it; replicate that (it matches the client's
  // CSV export of all three sample sessions exactly).  keyShift = tick offset of that first frame.
  var keyShift = new Float64Array(keys.length), shiftSet = new Uint8Array(keys.length);
  for (f = 0; f < nEd; f++) {
    if (!valid[f]) continue;
    var sqf = d[edPos[f] + 1];
    for (k = 0; k < keys.length; k++) if (keys[k].tenHz && !shiftSet[k] && keys[k].occ[sqf].length) { shiftSet[k] = 1; keyShift[k] = keys[k].occ[sqf][0]; }
  }

  // ---- pass 2: decode
  var TICK = 0.02;
  for (f = 0; f < nEd; f++) {
    if (!valid[f]) continue;
    var fp2 = edPos[f], sq2 = d[fp2 + 1], baseTick = 2 * fcount[f];
    var sk = seqKeys[sq2];
    for (var a = 0; a < sk.length; a++) {
      var kk2 = sk[a], oc = keys[kk2].occ[sq2], ta = keyT[kk2];
      var bt = baseTick - keyShift[kk2];
      if (keyFirst[kk2] !== keyFirst[kk2]) keyFirst[kk2] = (bt + oc[0]) * TICK;
      keyLast[kk2] = (bt + oc[oc.length - 1]) * TICK;
      if (ta) for (var b2 = 0; b2 < oc.length; b2++) ta[keyCur[kk2]++] = (bt + oc[b2]) * TICK;
    }
    var pr3 = P[sq2], o2 = fp2 + 12;
    for (var q4 = 0; q4 < pr3.length; q4 += 2) {
      var cs2 = pr3[q4], raw2;
      switch (pr3[q4 + 1]) {
        case 0: raw2 = d[o2]; o2 += 1; break;
        case 1: raw2 = (d[o2] << 24) >> 24; o2 += 1; break;
        case 2: raw2 = (d[o2] << 8) | d[o2 + 1]; o2 += 2; break;
        case 3: raw2 = ((d[o2] << 24) | (d[o2 + 1] << 16)) >> 16; o2 += 2; break;
        case 4: raw2 = ((d[o2] << 24) | (d[o2 + 1] << 16) | (d[o2 + 2] << 8) | d[o2 + 3]) >>> 0; o2 += 4; break;
        default: raw2 = (d[o2] << 24) | (d[o2 + 1] << 16) | (d[o2 + 2] << 8) | d[o2 + 3]; o2 += 4;
      }
      var va = vals[cs2];
      if (va) va[vcur[cs2]++] = raw2;
    }
  }

  // ---- convert raw -> physical, build series
  var series = [], flatPos = new Map();
  flat.forEach(function (c, ii) { flatPos.set(c, ii); });
  var order = chans.map(function (c, ci) { return ci; }).sort(function (x, y) { return flatPos.get(chans[x].info) - flatPos.get(chans[y].info); });
  order.forEach(function (ci) {
    var c = chans[ci], e = c.info.e, path = c.info.path, unit = '', k2 = 1, off = 0, labels = null, codes = null, lmap = null, dp;
    if (e.ty === 8) {
      var en = S.enums[e.en];
      if (!(en.flags & 0x10)) {                       // plain enum -> label indices
        labels = []; codes = []; lmap = new Map();
        en.items.forEach(function (it) { lmap.set(it[0], labels.length); labels.push(it[1]); codes.push(it[0]); });
      }
    } else if (c.custom) {
      var cd = c.custom;
      if (cd.name) path = 'custom/' + cd.name;
      unit = S.units[cd.unitIdx] || '';
      k2 = cd.mul; off = cd.off;
    } else {
      unit = e.unit !== undefined ? (S.units[e.unit] || '') : '';
      var div = e.div || 1;
      if (div >= 0x8000) div = 1e7;  // seen only on GPS lat/lon (0xC361); true encoding unknown, 1e7 verified on data
      k2 = (e.mul || 1) / div; off = e.off || 0;
      if (e.dec !== undefined) dp = e.dec;
    }
    function conv(raw) {
      if (lmap) {
        var li = lmap.get(raw);
        if (li === undefined) { li = labels.length; lmap.set(raw, li); labels.push(String(raw)); codes.push(raw); }
        return li;
      }
      return raw * k2 + off;
    }
    var t, v, out;
    if (varying[ci]) {
      t = keyT[c.key]; v = vals[ci];
      for (var q5 = 0; q5 < v.length; q5++) v[q5] = conv(v[q5]);
    } else if (seen[ci]) {                            // constant channel: first and last sample time
      var cv = conv(first[ci]);
      t = new Float64Array([keyFirst[c.key], keyLast[c.key]]);
      v = new Float32Array([cv, cv]);
    } else return;
    out = { n: path, u: unit, t: t, v: v };
    if (labels) { out.labels = labels; out.codes = codes; }   // codes[i] = raw ECU value of labels[i]
    if (dp !== undefined) out.dp = dp;
    series.push(out);
  });
  return { name: name, source: 'ECUMaster EMU PRO (.emuprolog)', series: series,
    info: { frames: nEd, badFrames: nBad, skippedBytes: skipped, channels: series.length, varying: series.filter(function (x) { return x.v.length > 2; }).length } };
}
