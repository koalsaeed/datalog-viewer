/*
 * AiM .xrk / .xrz datalog reader (plain browser JS, no imports, no DOM).
 *
 * Written from the MIT-licensed format documentation in m3rlin45/libxrk
 * (spec/xrk_format.py, spec/docs/*.md, src/libxrk/aim_xrk.pyx, gps.py).
 *
 * Expects in scope:
 *   inflateRaw(u8, expectedSizeOrUndefined) -> Uint8Array   (raw DEFLATE)
 *   td                                     -> TextDecoder('utf-8')
 *
 * Exports (globals / module.exports when available):
 *   looksLikeXrk(u8), looksLikeXrz(u8), parseAim(buf, name[, opts])
 *   opts.gpsLaps = true ignores LAP messages and detects laps from GPS vs the TRK start/finish point
 *
 * parseAim returns
 *   { name, source, series:[{ n, u, t:Float64Array(s), v:Float32Array|Float64Array,
 *                             dp, interp, hz }],
 *     laps:[{ n, t, end, type }], meta:{...}, info:{...} }
 * Every series has its own time base (seconds from session start, strictly increasing).
 * Channels inside one AiM sample group share the same `t` array object.
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- constants
  function tokv(s) { var v = 0; for (var i = s.length - 1; i >= 0; i--) v = v * 256 + s.charCodeAt(i); return v >>> 0; }
  var T_CNF = tokv('CNF'), T_CHS = tokv('CHS'), T_GRP = tokv('GRP'), T_GPS = tokv('GPS'), T_GPS1 = tokv('GPS1'),
      T_GNFI = tokv('GNFI'), T_LAP = tokv('LAP'), T_TRK = tokv('TRK'), T_IDN = tokv('idn'), T_SRC = tokv('SRC');
  var META_TOKS = {}; // token -> meta key (null-terminated strings)
  [['RCR', 'driver'], ['VEH', 'vehicle'], ['TMD', 'date'], ['TMT', 'time'], ['VTY', 'session'],
   ['CMP', 'series'], ['NTE', 'comment'], ['NDV', 'device']].forEach(function (p) { META_TOKS[tokv(p[0])] = p[1]; });

  // unit_type_byte & 127 -> [unit, decimal points]
  var UNIT_MAP = {
    1: ['%', 2], 3: ['g', 2], 4: ['deg', 1], 5: ['deg/s', 1], 6: ['', 0], 9: ['Hz', 0], 11: ['', 0],
    12: ['mm', 0], 14: ['bar', 2], 15: ['rpm', 0], 16: ['km/h', 0], 17: ['C', 1], 18: ['ms', 0],
    19: ['Nm', 0], 20: ['km/h', 0], 21: ['mV', 1], 22: ['l', 1], 24: ['l/s', 0], 26: ['time?', 0],
    27: ['A', 0], 30: ['lambda', 2], 31: ['gear', 0], 33: ['%', 2], 43: ['kg', 3]
  };
  // decoder_type -> [storage type, interpolate, fixup]
  var DECODERS = {
    0: ['i', false], 1: ['H', true], 3: ['i', false], 4: ['h', false], 6: ['f', true], 8: ['i', false],
    11: ['h', false], 12: ['i', false], 13: ['B', false], 15: ['H', false, 'gear'], 20: ['H', true, 'half'],
    22: ['i', false], 24: ['i', false], 26: ['i', false], 27: ['i', false], 31: ['i', false],
    32: ['i', false], 33: ['i', false], 37: ['i', false], 38: ['i', false], 39: ['i', false]
  };
  var MANUAL_DECODERS = { 'Calculated_Gear': ['Q', false, 'calcgear'], 'PreCalcGear': ['Q', false, 'calcgear'] };
  var HIDDEN = { 'StrtRec': 1, 'Master Clk': 1 };
  var GPS_NAMES = ['GPS Speed', 'GPS Latitude', 'GPS Longitude', 'GPS Altitude', 'GPS_Satellites', 'GPS_Fix',
    'GPS_pDOP', 'GPS_Position_Accuracy', 'GPS_Velocity_Accuracy', 'GPS_InlineAcc', 'GPS_LateralAcc', 'GPS_Yaw_Rate'];

  var HALF = null; // lazily built fp16 -> float32 table
  function halfTable() {
    if (HALF) return HALF;
    HALF = new Float32Array(65536);
    for (var h = 0; h < 65536; h++) {
      var s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 31, m = h & 1023;
      HALF[h] = e === 0 ? s * m * Math.pow(2, -24) : e === 31 ? (m ? NaN : s * Infinity) : s * (1 + m / 1024) * Math.pow(2, e - 15);
    }
    return HALF;
  }

  // ---------------------------------------------------------------- helpers
  function GI(n) { this.a = new Int32Array(n || 256); this.n = 0; }
  GI.prototype.push = function (x) {
    if (this.n === this.a.length) { var b = new Int32Array(this.a.length * 2); b.set(this.a); this.a = b; }
    this.a[this.n++] = x;
  };
  function Acc() { this.last = -1; this.tc = new GI(); this.off = new GI(); }
  function accAt(arr, i) { var a = arr[i]; if (!a) a = arr[i] = new Acc(); return a; }

  function cstr(u8, p, len) { var s = ''; for (var i = 0; i < len; i++) { var c = u8[p + i]; if (!c) break; s += String.fromCharCode(c); } return s; }
  function tstr(u8, p, len) { var e = p; while (e < p + len && u8[e]) e++; return td.decode(u8.subarray(p, e)); }

  function looksLikeXrk(u8) {
    if (!u8 || u8.length < 20 || u8[0] !== 0x3C || u8[1] !== 0x68 || u8[11] !== 0x3E) return false;
    for (var i = 2; i < 5; i++) { var c = u8[i]; if (c < 0x20 || c > 0x7E) return false; }
    return true;
  }
  function looksLikeXrz(u8) {
    // zlib stream header (78 01 / 78 9C / 78 DA). Generic for any zlib data: combine with the
    // file extension; parseAim verifies that the inflated stream really is XRK.
    return !!u8 && u8.length > 16 && u8[0] === 0x78 && (u8[1] === 0x01 || u8[1] === 0x9C || u8[1] === 0xDA);
  }

  // ---------------------------------------------------------------- geodesy (WGS84)
  var WA = 6378137.0, WE = 8.181919084261345e-2, WE2 = WE * WE, WE4 = WE2 * WE2, R2D = 180 / Math.PI;
  function lla2ecef(latDeg, lonDeg, alt, out) {
    var lat = latDeg * Math.PI / 180, lon = lonDeg * Math.PI / 180, cl = Math.cos(lat), sl = Math.sin(lat);
    var N = WA / Math.sqrt(1 - WE2 * sl * sl);
    out[0] = (N + alt) * cl * Math.cos(lon); out[1] = (N + alt) * cl * Math.sin(lon); out[2] = ((1 - WE2) * N + alt) * sl;
    return out;
  }
  // Vermeille (2003) closed-form ECEF -> geodetic, as used by libxrk
  function ecef2lla(x, y, z, out) {
    var p = (x * x + y * y) / (WA * WA), q = ((1 - WE2) / (WA * WA)) * z * z, r = (p + q - WE4) / 6;
    var s = (WE4 / 4) * p * q / (r * r * r), t = Math.cbrt(1 + s + Math.sqrt(s * (2 + s)));
    var u = r * (1 + t + 1 / t), v = Math.sqrt(u * u + WE4 * q);
    u += v;
    var w = (WE2 / 2) * (u - q) / v, k = Math.sqrt(u + w * w) - w, D = k * Math.sqrt(x * x + y * y) / (k + WE2);
    var rt = Math.sqrt(D * D + z * z);
    out[0] = R2D * 2 * Math.atan2(z, D + rt); out[1] = R2D * Math.atan2(y, x); out[2] = (k + WE2 - 1) / k * rt;
    return out;
  }

  // GPS start/finish crossing detection (port of libxrk gps.find_laps); tc in ms
  function findLaps(lat, lon, tc, sfLat, sfLon) {
    var n = lat.length; if (n < 3) return [];
    var SO = lla2ecef(sfLat, sfLon, 0, [0, 0, 0]), S1 = lla2ecef(sfLat, sfLon, 1000, [0, 0, 0]);
    var SD = [S1[0] - SO[0], S1[1] - SO[1], S1[2] - SO[2]], sdsd = SD[0] * SD[0] + SD[1] * SD[1] + SD[2] * SD[2];
    var m = n - 1, O = new Float64Array(3 * n), D = new Float64Array(3 * m), SN = new Float64Array(3 * m);
    var minspeed = new Uint8Array(m), t = new Float64Array(m), dist = new Float64Array(m), tmp = [0, 0, 0], i, j;
    for (i = 0; i < n; i++) { lla2ecef(lat[i], lon[i], 0, tmp); O[3 * i] = tmp[0] - SO[0]; O[3 * i + 1] = tmp[1] - SO[1]; O[3 * i + 2] = tmp[2] - SO[2]; }
    for (i = 0; i < m; i++) {
      var dx = O[3 * i + 3] - O[3 * i], dy = O[3 * i + 4] - O[3 * i + 1], dz = O[3 * i + 5] - O[3 * i + 2];
      D[3 * i] = dx; D[3 * i + 1] = dy; D[3 * i + 2] = dz;
      var dd = (tc[i + 1] - tc[i]) * 0.004; minspeed[i] = (dx * dx + dy * dy + dz * dz) > dd * dd ? 1 : 0;
      var sdd = SD[0] * dx + SD[1] * dy + SD[2] * dz;
      SN[3 * i] = sdsd * dx - sdd * SD[0]; SN[3 * i + 1] = sdsd * dy - sdd * SD[1]; SN[3 * i + 2] = sdsd * dz - sdd * SD[2];
    }
    function solve(snOf) {
      for (var i = 0; i < m; i++) {
        var a = snOf(i, 0), b = snOf(i, 1), c = snOf(i, 2);
        var num = -(a * O[3 * i] + b * O[3 * i + 1] + c * O[3 * i + 2]), den = a * D[3 * i] + b * D[3 * i + 1] + c * D[3 * i + 2];
        var tt = num / den; tt = tt > 0 ? tt : (tt !== tt ? NaN : 0); t[i] = tt;
        var px = O[3 * i] + tt * D[3 * i], py = O[3 * i + 1] + tt * D[3 * i + 1], pz = O[3 * i + 2] + tt * D[3 * i + 2];
        dist[i] = px * px + py * py + pz * pz;
      }
    }
    function pick(j) { return t[j + 1] <= 1 && t[j] > 1 && dist[j + 1] < 900; }
    solve(function (i, k) { return SN[3 * i + k]; });
    var S = [0, 0, 0];
    for (j = 0; j < m - 1; j++) if (pick(j) && minspeed[j + 1]) { S[0] += SN[3 * j + 3]; S[1] += SN[3 * j + 4]; S[2] += SN[3 * j + 5]; }
    solve(function (i, k) { return S[k]; });
    var markers = [0];
    for (j = 0; j < m - 1; j++) {
      if (!pick(j)) continue;
      var idx = j + 1;
      if (tc[idx] <= markers[markers.length - 1]) continue;
      if (!minspeed[idx]) { var q = idx; while (q < m && !minspeed[q]) q++; if (q < m) idx = q; }
      markers.push(tc[idx] + t[idx] * (tc[idx + 1] - tc[idx]));
    }
    return markers.slice(1);
  }

  // sort by time (stable) and drop repeated timestamps if needed; returns [t, v] arrays
  function monotonic(tc, vals) {
    var n = tc.length, ok = true, i;
    for (i = 1; i < n; i++) if (!(tc[i] > tc[i - 1])) { ok = false; break; }
    if (ok) return null;
    var idx = new Array(n); for (i = 0; i < n; i++) idx[i] = i;
    idx.sort(function (a, b) { return (tc[a] - tc[b]) || (a - b); });
    var keep = [];
    for (i = 0; i < n; i++) if (!keep.length || tc[idx[i]] > tc[keep[keep.length - 1]]) keep.push(idx[i]);
    var out = vals.map(function (v) { var o = new v.constructor(keep.length); for (var k = 0; k < keep.length; k++) o[k] = v[keep[k]]; return o; });
    var t2 = new Float64Array(keep.length); for (i = 0; i < keep.length; i++) t2[i] = tc[keep[i]];
    return { t: t2, v: out, dropped: n - keep.length };
  }

  // ---------------------------------------------------------------- main parser
  function parseAim(buf, name, opts) {
    opts = opts || {};
    var u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
    var i, source = 'AiM XRK', info = { badBytes: 0, warnings: [] };
    if (!looksLikeXrk(u8) && looksLikeXrz(u8)) {
      u8 = inflateRaw(u8.subarray(2), undefined);
      source = 'AiM XRZ';
    }
    if (!looksLikeXrk(u8)) throw new Error('Not an AiM XRK/XRZ file');
    var N = u8.length, dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);

    var channels = [], groups = [];
    var accS = [], accC = [], accM = [], accG = [];
    var gpsOffs = new GI(), gnfiOffs = new GI(), lapMsgs = [], meta = {}, trk = null;
    var lapOffset = null;
    var v2v3 = new Map(), lastV2Base = new Map(), lastV2Plus4 = new Map(), cvPos = 0;

    function readCHS(p, len) {
      if (len < 112) return null;
      var unitByte = u8[p + 12], um = UNIT_MAP[unitByte & 127] || ['', 0], unit = um[0];
      if ((unitByte & 0x80) && unit === 'mV') unit = 'V';
      return {
        index: dv.getUint16(p, true), hwId: dv.getUint16(p + 4, true), srcChId: dv.getUint16(p + 6, true),
        hwRef: dv.getUint32(p + 8, true), unitByte: unitByte, srcType: u8[p + 16], decoder: u8[p + 20],
        short: cstr(u8, p + 24, 8), name: cstr(u8, p + 32, 24), mms: Math.floor(dv.getUint32(p + 64, true) / 1000),
        size: u8[p + 72], unit: unit, dp: um[1], group: null, gOff: 0
      };
    }
    function readGRP(p, len) {
      if (len < 4) return null;
      var cnt = dv.getUint16(p + 2, true); if (len !== 4 + 2 * cnt) return null;
      var ch = []; for (var i = 0; i < cnt; i++) ch.push(dv.getUint16(p + 4 + 2 * i, true));
      return { index: dv.getUint16(p, true), chans: ch, rowSize: 0 };
    }
    // iterate header messages in [start,end): cb(tok, payloadPos, len, ver)
    function scanHeaders(start, end, cb) {
      var pos = start;
      while (pos + 20 <= end) {
        if (u8[pos] !== 0x3C || u8[pos + 1] !== 0x68) { pos++; continue; }
        var r = header(pos, end);
        if (r < 0) { pos++; continue; }
        cb(hTok, pos + 12, hLen, u8[pos + 10]);
        pos = r;
      }
    }
    var hTok = 0, hLen = 0;
    function header(pos, end) { // validates a <h...> frame, returns next pos or -1
      var tok = dv.getUint32(pos + 2, true), len = dv.getInt32(pos + 6, true);
      if (len < 0 || u8[pos + 11] !== 0x3E) return -1;
      var p = pos + 12, f = p + len;
      if (f + 8 > end || u8[f] !== 0x3C || u8[f + 7] !== 0x3E || dv.getUint32(f + 1, true) !== tok) return -1;
      var sum = 0; for (var i = p; i < f; i++) sum += u8[i];
      if ((sum & 0xFFFF) !== dv.getUint16(f + 5, true)) return -1;
      if ((tok >>> 24) === 0x20) tok -= 0x20000000;
      hTok = tok >>> 0; hLen = len;
      return f + 8;
    }
    function registerConfig(p, len, isCnf) {
      // Re-arm dedup so data after a new CNF is not dropped (timecodes may restart)
      if (isCnf) [accS, accC, accM, accG].forEach(function (arr) { for (var i = 0; i < arr.length; i++) if (arr[i]) arr[i].last = -1; });
      var newGroups = [];
      scanHeaders(p, p + len, function (tok, q, l) {
        if (tok === T_CHS) {
          var c = readCHS(q, l); if (!c) return;
          var ex = channels[c.index];
          if (!ex) channels[c.index] = c;
          else { ex.name = c.name; ex.short = c.short; } // later CNF renames: last write wins
        } else if (tok === T_GRP) {
          var g = readGRP(q, l); if (g) newGroups.push(g);
        }
      });
      newGroups.forEach(function (g) {
        var off = 0, ok = true;
        g.chans.forEach(function (ci) { var c = channels[ci]; if (!c) { ok = false; return; } c.group = g; c.gOff = off; off += c.size; });
        g.rowSize = off;
        if (ok) groups[g.index] = g;
      });
    }

    // --- pass 1: walk the top-level message stream
    var pos = 0, bad = 0, acc, tc, ch, len, idx, badRuns = [], badEnd = -1;
    function badAt(p) { // unparseable byte: skip it (resync), remember where
      if (p === badEnd && badRuns.length) badRuns[badRuns.length - 1][1]++; else if (badRuns.length < 32) badRuns.push([p, 1]);
      badEnd = p + 1; bad++; return p + 1;
    }
    while (pos < N) {
      if (pos + 10 >= N) { bad += N - pos; break; }
      var b0 = u8[pos], b1 = u8[pos + 1];
      if (b0 === 0x28) {
        if (b1 === 0x53 || b1 === 0x47) { // (S single sample / (G group sample
          idx = dv.getUint16(pos + 6, true);
          if (b1 === 0x47) { var g = groups[idx]; len = g ? g.rowSize + 9 : 0; acc = g ? accAt(accG, idx) : null; }
          else { ch = channels[idx]; len = ch ? ch.size + 9 : 0; acc = ch ? accAt(accS, idx) : null; }
          if (!acc || pos + len > N || u8[pos + len - 1] !== 0x29) { pos = badAt(pos); continue; }
          tc = dv.getInt32(pos + 2, true);
          if (tc > acc.last) { acc.last = tc; acc.tc.push(tc); acc.off.push(pos + 8); }
          pos += len; continue;
        }
        if (b1 === 0x4D) { // (M burst
          idx = dv.getUint16(pos + 6, true); ch = channels[idx];
          var cnt = dv.getUint16(pos + 8, true);
          var endp = ch ? pos + 10 + ch.size * cnt : 0;
          if (!ch || !ch.mms || endp >= N || u8[endp] !== 0x29) { pos = badAt(pos); continue; }
          acc = accAt(accM, idx); tc = dv.getInt32(pos + 2, true);
          var skip = 0, mms = ch.mms;
          if (tc <= acc.last) skip = Math.floor((acc.last - tc) / mms) + 1;
          if (skip < cnt) {
            acc.last = tc + (cnt - 1) * mms;
            for (var k = skip; k < cnt; k++) { acc.tc.push(tc + k * mms); acc.off.push(pos + 10 + k * ch.size); }
          }
          pos = endp + 1; continue;
        }
        if (b1 === 0x63) { // (c expansion data, three variants
          var unk1 = u8[pos + 2], cf = dv.getUint16(pos + 3, true), unk3 = u8[pos + 5], unk4 = u8[pos + 6];
          if (unk3 !== 0x84) { pos = badAt(pos); continue; }
          if (unk1 === 0 && unk4 === 6) {
            ch = (cf & 7) === 4 ? channels[cf >> 3] : null; len = ch ? ch.size + 12 : 0;
            if (!ch || pos + len > N || u8[pos + len - 1] !== 0x29) { pos = badAt(pos); continue; }
            acc = accAt(accC, cf >> 3); tc = dv.getInt32(pos + 7, true);
            if (tc > acc.last) { acc.last = tc; acc.tc.push(tc); acc.off.push(pos + 11); }
            pos += len; continue;
          }
          if (unk1 === 0 && unk4 === 8) {
            if (pos + 16 > N || u8[pos + 15] !== 0x29) { pos = badAt(pos); continue; }
            tc = dv.getInt32(pos + 7, true);
            var lst = v2v3.get(cf); if (!lst) v2v3.set(cf, lst = []);
            var low = cf & 15;
            if (low === 0 || low === 8) { lst.push(tc, pos + 11, 3, tc - 4, pos + 13, 3); lastV2Base.set(cf, [tc, cvPos]); }
            else { lst.push(tc - 2, pos + 11, 1, tc - 4, pos + 13, 1); lastV2Plus4.set(cf, [tc, cvPos]); }
            cvPos++; pos += 16; continue;
          }
          if (unk1 === 1 && unk4 === 2) {
            if (pos + 10 > N || u8[pos + 9] !== 0x29) { pos = badAt(pos); continue; }
            var be = lastV2Base.get(cf ^ 4), pe = lastV2Plus4.get(cf), st = -1;
            if (be && (!pe || be[1] >= pe[1])) st = be[0] - 2; else if (pe) st = pe[0] + 2;
            if (st >= 0) { var l3 = v2v3.get(cf); if (!l3) v2v3.set(cf, l3 = []); l3.push(st, pos + 7, 2); }
            cvPos++; pos += 10; continue;
          }
          pos = badAt(pos); continue;
        }
        pos = badAt(pos); continue;
      }
      if (b0 === 0x3C && b1 === 0x68) { // <h header message
        var nx = header(pos, N);
        if (nx < 0) { pos = badAt(pos); continue; }
        var tok = hTok, p = pos + 12, hl = hLen;
        if (tok === T_GPS || tok === T_GPS1) { for (var q = 0; q + 56 <= hl; q += 56) gpsOffs.push(p + q); }
        else if (tok === T_GNFI) { for (var q2 = 0; q2 + 32 <= hl; q2 += 32) gnfiOffs.push(p + q2); }
        else if (tok === T_CNF) registerConfig(p, hl, true);
        else if (tok === T_CHS || tok === T_GRP) { registerConfig(pos, nx - pos, false); info.topLevelDefs = (info.topLevelDefs || 0) + 1; } // stray top-level definition
        else if (tok === T_LAP) {
          if (hl >= 20) {
            var dur = dv.getUint32(p + 4, true), endT = hl >= 32 ? dv.getUint32(p + 28, true) : dv.getUint32(p + 16, true);
            if (lapOffset === null) lapOffset = endT - dur;
            lapMsgs.push({ seg: u8[p + 1], lap: dv.getUint16(p + 2, true), dur: dur, end: endT });
          }
        } else if (tok === T_TRK) {
          if (hl >= 44) trk = { name: cstr(u8, p, 32), lat: dv.getInt32(p + 36, true) / 1e7, lon: dv.getInt32(p + 40, true) / 1e7 };
        } else if (tok === T_IDN) {
          if (hl >= 10) { meta.loggerModelId = dv.getUint16(p, true); meta.loggerId = dv.getUint32(p + 6, true); }
        } else if (tok === T_SRC) { // embedded idn: "idn" + ver + len16, then idn payload
          if (hl >= 16 && u8[p] === 0x69 && u8[p + 1] === 0x64 && u8[p + 2] === 0x6E && meta.loggerId === undefined) {
            meta.loggerModelId = dv.getUint16(p + 6, true); meta.loggerId = dv.getUint32(p + 12, true);
          }
        } else if (META_TOKS[tok]) meta[META_TOKS[tok]] = tstr(u8, p, hl);
        pos = nx; continue;
      }
      pos = badAt(pos);
    }
    info.badBytes = bad; info.badRuns = badRuns;
    if (trk) meta.venue = trk.name;

    // --- resolve (c) V2/V3 expansion messages onto CHS channels (libxrk issue #68 rule)
    if (v2v3.size) {
      var cfs = Array.from(v2v3.keys()).sort(function (a, b) { return a - b; }), cfSet = new Set(cfs);
      var pairs = [], orphans = [], done = new Set();
      cfs.forEach(function (cf) {
        if (done.has(cf)) return;
        var low = cf & 15;
        if ((low === 0 || low === 8) && cfSet.has(cf | 4)) { pairs.push([cf, cf | 4]); done.add(cf); done.add(cf | 4); }
        else if ((low === 4 || low === 12) && cfSet.has(cf & ~4)) { /* covered by base */ }
        else { orphans.push(cf); done.add(cf); }
      });
      var pc = [], oc = [];
      channels.forEach(function (c, i) {
        if (!c || c.decoder !== 20 || c.srcType !== 1 || c.hwId === 0) return;
        (c.mms <= 5 ? pc : (c.mms <= 15 ? oc : [])).push([c.hwRef, c.srcChId, i]);
      });
      var cmpK = function (a, b) { return (a[0] - b[0]) || (a[1] - b[1]) || (a[2] - b[2]); };
      pc.sort(cmpK); oc.sort(cmpK);
      var cmap = new Map();
      pairs.forEach(function (pr, i) { if (pc[i]) { cmap.set(pr[0], pc[i][2]); cmap.set(pr[1], pc[i][2]); } });
      orphans.forEach(function (cf, i) { if (oc[i]) cmap.set(cf, oc[i][2]); });
      var per = new Map();
      v2v3.forEach(function (lst, cf) {
        var ci = cmap.get(cf); if (ci === undefined) return;
        var bucket = per.get(ci); if (!bucket) per.set(ci, bucket = new Map());
        for (var i = 0; i < lst.length; i += 3) {
          var ex = bucket.get(lst[i]);
          if (!ex || lst[i + 2] > ex[1]) bucket.set(lst[i], [lst[i + 1], lst[i + 2]]);
        }
      });
      per.forEach(function (bucket, ci) {
        var a = accAt(accC, ci), keys = Array.from(bucket.keys()).sort(function (x, y) { return x - y; });
        keys.forEach(function (t) { if (t <= a.last) return; a.last = t; a.tc.push(t); a.off.push(bucket.get(t)[0]); });
      });
    }

    // --- session time offset (ms): first LAP start, else earliest sample
    var cand = lapOffset !== null ? [lapOffset] : [];
    [accS, accC, accM, accG].forEach(function (arr) { arr.forEach(function (a) { if (a && a.tc.n) cand.push(a.tc.a[0]); }); });
    if (gpsOffs.n) cand.push(dv.getInt32(gpsOffs.a[0], true));
    var off0 = cand.length ? Math.min.apply(null, cand) : 0;
    info.timeOffsetMs = off0;

    // --- decode CHS channels
    var series = [], tCache = new Map(), half = null;
    function timeOf(a) {
      var t = tCache.get(a); if (t) return t;
      t = new Float64Array(a.tc.n); for (var i = 0; i < a.tc.n; i++) t[i] = (a.tc.a[i] - off0) / 1000;
      tCache.set(a, t); return t;
    }
    var gpsPresent = gpsOffs.n > 0, seen = {};
    if (gpsPresent) GPS_NAMES.forEach(function (n) { seen[n] = 1; });
    var chOut = [];
    channels.forEach(function (c) {
      if (!c) return;
      var k = (seen[c.name] || 0) + 1; seen[c.name] = k;
      var disp = (k > 1 && !HIDDEN[c.name]) ? c.name + ' dup ' + k : c.name;
      chOut.push([c, disp]);
    });
    chOut.forEach(function (pair) {
      var c = pair[0], disp = pair[1];
      if (HIDDEN[disp]) return;
      var d = MANUAL_DECODERS[c.name] || DECODERS[c.decoder]; if (!d) return;
      var a, extra = 0;
      if (c.group) { a = accG[c.group.index]; extra = c.gOff; }
      else if (accS[c.index] && accS[c.index].tc.n) a = accS[c.index];
      else if (accC[c.index] && accC[c.index].tc.n) a = accC[c.index];
      else a = accM[c.index];
      if (!a || !a.tc.n) return;
      var n = a.tc.n, offs = a.off.a, typ = d[0], fix = d[2], i, o;
      var v = (typ === 'i' || typ === 'Q') ? new Float64Array(n) : new Float32Array(n);
      for (i = 0; i < n; i++) {
        o = offs[i] + extra;
        switch (typ) {
          case 'i': v[i] = dv.getInt32(o, true); break;
          case 'H': v[i] = dv.getUint16(o, true); break;
          case 'h': v[i] = dv.getInt16(o, true); break;
          case 'f': v[i] = dv.getFloat32(o, true); break;
          case 'B': v[i] = u8[o]; break;
          case 'Q': { var lo = dv.getUint32(o, true); v[i] = (lo & 0x80000) ? 0 : (lo >>> 16) & 7; break; }
        }
      }
      if (fix === 'half') { half = half || halfTable(); for (i = 0; i < n; i++) v[i] = half[v[i]]; }
      else if (fix === 'gear') { for (i = 0; i < n; i++) { var g = v[i]; v[i] = g === 78 ? 0 : (g >= 49 && g <= 54 ? g - 48 : g); } }
      if (c.unit === 'V') for (i = 0; i < n; i++) v[i] = v[i] / 1000;
      var t = timeOf(a), mono = monotonic(t, [v]);
      if (mono) { t = mono.t; v = mono.v[0]; info.warnings.push(disp + ': ' + mono.dropped + ' out-of-order samples dropped'); }
      series.push({ n: disp, u: c.size === 1 ? '' : c.unit, t: t, v: v, dp: c.dp, interp: !!d[1],
                    hz: estHz(t) || (c.mms ? 1000 / c.mms : 0) });
    });

    // --- GPS (u-blox NAV-SOL records, 56 bytes each incl. 4-byte logger timecode)
    var gpsSeries = [], gpsLat = null, gpsLon = null, gpsTcRaw = null;
    if (gpsPresent) {
      var gn = gpsOffs.n, go = gpsOffs.a, gtc = new Float64Array(gn), nonMono = false;
      for (i = 0; i < gn; i++) { gtc[i] = dv.getInt32(go[i], true); if (i && gtc[i] < gtc[i - 1]) nonMono = true; }
      if (nonMono) { // firmware bug: upper 16 bits unreliable -> phase unwrap of low 16 bits
        info.gpsTimecodesUnwrapped = true;
        for (i = 1; i < gn; i++) { var dlt = ((((gtc[i] - gtc[i - 1]) & 0xFFFF) ^ 0x8000) - 0x8000); gtc[i] = gtc[i - 1] + dlt; }
      }
      for (i = 0; i < gn; i++) gtc[i] -= off0;
      var spd = new Float64Array(gn), la = new Float64Array(gn), lo2 = new Float64Array(gn), al = new Float32Array(gn),
          sat = new Float32Array(gn), fx = new Float32Array(gn), pdop = new Float32Array(gn), pacc = new Float32Array(gn),
          vacc = new Float32Array(gn), hdg = new Float64Array(gn), lla = [0, 0, 0];
      for (i = 0; i < gn; i++) {
        var r = go[i];
        var X = dv.getInt32(r + 16, true) / 100, Y = dv.getInt32(r + 20, true) / 100, Z = dv.getInt32(r + 24, true) / 100;
        var vx = dv.getInt32(r + 32, true), vy = dv.getInt32(r + 36, true), vz = dv.getInt32(r + 40, true);
        ecef2lla(X, Y, Z, lla); la[i] = lla[0]; lo2[i] = lla[1]; al[i] = lla[2];
        spd[i] = Math.sqrt(vx * vx + vy * vy + vz * vz) / 100;
        var latr = lla[0] * Math.PI / 180, lonr = lla[1] * Math.PI / 180;
        var sla = Math.sin(latr), cla = Math.cos(latr), slo = Math.sin(lonr), clo = Math.cos(lonr);
        var ve = -slo * vx + clo * vy, vn = -sla * clo * vx - sla * slo * vy + cla * vz;
        hdg[i] = Math.atan2(ve, vn) * R2D;
        sat[i] = u8[r + 51]; fx[i] = u8[r + 14]; pdop[i] = dv.getUint16(r + 48, true) / 100;
        pacc[i] = dv.getUint32(r + 28, true) / 100; vacc[i] = dv.getUint32(r + 44, true) / 100;
      }
      var inl = new Float32Array(gn), yaw = new Float32Array(gn), latA = new Float32Array(gn);
      for (i = 1; i < gn; i++) {
        var dt = (gtc[i] - gtc[i - 1]) / 1000; if (!(dt > 0)) dt = Infinity;
        inl[i] = (spd[i] - spd[i - 1]) / dt / 9.81;
        var dh = hdg[i] - hdg[i - 1]; if (dh > 180) dh -= 360; if (dh < -180) dh += 360;
        yaw[i] = dh / dt;
      }
      for (i = 0; i < gn; i++) latA[i] = spd[i] * yaw[i] * (Math.PI / 180) / 9.81;
      gpsLat = la; gpsLon = lo2; gpsTcRaw = gtc;
      var gvals = [spd, la, lo2, al, sat, fx, pdop, pacc, vacc, inl, latA, yaw];
      var gmeta = [['m/s', 1, 1], ['deg', 4, 1], ['deg', 4, 1], ['m', 1, 1], ['', 0, 0], ['', 0, 0], ['', 2, 0],
                   ['m', 2, 1], ['m/s', 2, 1], ['g', 2, 1], ['g', 2, 1], ['deg/s', 1, 1]];
      gpsSeries = GPS_NAMES.map(function (n, j) { return { n: n, u: gmeta[j][0], v: gvals[j], dp: gmeta[j][1], interp: !!gmeta[j][2] }; });
    }

    // --- laps
    var laps = [], hasLapMsgs = lapMsgs.length > 0 && !opts.gpsLaps, lapNums = [], st0 = [], en0 = [];
    if (hasLapMsgs) {
      lapMsgs.forEach(function (m) {
        if (m.seg) return;
        var e = m.end - off0, L = lapNums.length;
        if (L && lapNums[L - 1] === m.lap) return;
        if (L && lapNums[L - 1] + 2 === m.lap) { lapNums.push(m.lap - 1); st0.push(en0[L - 1]); en0.push(e - m.dur); }
        else if (L && lapNums[L - 1] + 1 !== m.lap) info.warnings.push('lap gap ' + lapNums[L - 1] + ' -> ' + m.lap);
        lapNums.push(m.lap); st0.push(e - m.dur); en0.push(e);
      });
    } else if (gpsLat && trk) {
      var mk = findLaps(gpsLat, gpsLon, gpsTcRaw, trk.lat, trk.lon);
      if (mk.length) {
        mk.push(gpsTcRaw[gpsTcRaw.length - 1]);
        for (i = 0; i + 1 < mk.length; i++) { lapNums.push(i); st0.push(mk[i]); en0.push(mk[i + 1]); }
      }
    }
    if (hasLapMsgs && lapNums.length) { // logger stopped before writing the final LAP: add the partial in-lap
      var dataEnd = 0; series.forEach(function (s) { if (s.t.length) dataEnd = Math.max(dataEnd, s.t[s.t.length - 1] * 1000); });
      var lastEnd = en0[en0.length - 1];
      if (dataEnd - lastEnd > 2000) { lapNums.push(lapNums[lapNums.length - 1] + 1); st0.push(lastEnd); en0.push(Math.round(dataEnd)); info.partialLastLap = true; }
    }
    var types = lapNums.map(function () { return 'full'; });
    if (types.length) {
      if (hasLapMsgs) {
        if (st0[0] <= 0) types[0] = 'out';
        if (types[types.length - 1] !== 'out' && gpsLat && trk) {
          var eT = en0[en0.length - 1], ii = 0; while (ii < gpsTcRaw.length && gpsTcRaw[ii] < eT) ii++;
          ii = Math.min(ii, gpsTcRaw.length - 1);
          var A = lla2ecef(trk.lat, trk.lon, 0, [0, 0, 0]), B = lla2ecef(gpsLat[ii], gpsLon[ii], 0, [0, 0, 0]);
          if (Math.hypot(A[0] - B[0], A[1] - B[1], A[2] - B[2]) > 30) types[types.length - 1] = 'in';
        }
      } else types[types.length - 1] = 'in';
      var mn = Math.min.apply(null, lapNums); lapNums = lapNums.map(function (x) { return x - mn; });
    }

    // --- GPS 65533 ms timing-gap repair (libxrk fix_gps_timing_gaps)
    if (gpsPresent) {
      var corr = gpsGapCorrections(gpsTcRaw, gnfiOffs, dv, off0, series);
      if (corr.length) {
        info.gpsGapCorrections = corr;
        var fixed = new Float64Array(gpsTcRaw.length);
        for (i = 0; i < fixed.length; i++) {
          var x = gpsTcRaw[i]; corr.forEach(function (c) { if (gpsTcRaw[i] > c[0]) x -= c[1]; }); fixed[i] = Math.trunc(x);
        }
        if (!hasLapMsgs) for (i = 0; i < st0.length; i++) {
          var s0 = st0[i], e0 = en0[i];
          corr.forEach(function (c) { if (st0[i] > c[0]) s0 -= c[1]; if (en0[i] > c[0]) e0 -= c[1]; });
          st0[i] = Math.trunc(s0); en0[i] = Math.trunc(e0);
        }
        gpsTcRaw = fixed;
      }
      var gt = new Float64Array(gpsTcRaw.length); for (i = 0; i < gt.length; i++) gt[i] = gpsTcRaw[i] / 1000;
      var gm = monotonic(gt, gpsSeries.map(function (s) { return s.v; }));
      if (gm) { info.gpsDuplicatesDropped = gm.dropped; gt = gm.t; }
      var ghz = estHz(gt);
      gpsSeries.forEach(function (s, j) { s.t = gt; if (gm) s.v = gm.v[j]; s.hz = ghz; series.push(s); });
    }
    for (i = 0; i < lapNums.length; i++) {
      var lp = { n: lapNums[i], t: st0[i] / 1000, end: en0[i] / 1000, type: types[i] };
      if (info.partialLastLap && i === lapNums.length - 1) lp.synthetic = true;
      if (!hasLapMsgs) lp.gpsDetected = true;
      laps.push(lp);
    }

    var dur = 0; series.forEach(function (s) { if (s.t.length) dur = Math.max(dur, s.t[s.t.length - 1]); });
    info.duration = dur;
    return { name: name, source: source, series: series, laps: laps, meta: meta, info: info };
  }

  function estHz(t) { // mean sample rate over the channel's span
    var n = t.length; if (n < 2 || !(t[n - 1] > t[0])) return 0;
    return Math.round((n - 1) / (t[n - 1] - t[0]) * 100) / 100;
  }

  function gpsGapCorrections(tc, gnfiOffs, dv, off0, series) {
    var BUG = 65533, n = tc.length, gaps = [], i, out = [];
    if (n < 2) return out;
    for (i = 0; i + 1 < n; i++) if (tc[i + 1] - tc[i] > 400) gaps.push(i);
    if (!gaps.length) return out;
    var largest = gaps.reduce(function (b, g) { return (tc[g + 1] - tc[g]) > (tc[b + 1] - tc[b]) ? g : b; }, gaps[0]);
    if (gnfiOffs.n >= 2) { // method 1: GNFI (logger clock) end vs GPS end
      var gEnd = dv.getInt32(gnfiOffs.a[gnfiOffs.n - 1], true) - off0, d = tc[n - 1] - gEnd;
      if (d >= BUG - 5000 && d <= BUG + 5000) {
        var gs = tc[largest + 1] - tc[largest];
        out.push([tc[largest], (gs >= BUG - 5000 && gs <= BUG + 5000) ? gs - 40 : BUG]);
        return out;
      }
    }
    gaps.forEach(function (g) { var s = tc[g + 1] - tc[g]; if (s >= 60000 && s <= 70000) out.push([tc[g], s - 40]); });
    if (out.length) return out;
    var endMax = -Infinity; // method 3: GPS runs ~65.5 s past every other channel
    series.forEach(function (s) { if (s.t.length) endMax = Math.max(endMax, s.t[s.t.length - 1] * 1000); });
    if (endMax > -Infinity) { var eo = tc[n - 1] - endMax; if (eo >= 60000 && eo <= 70000) out.push([tc[largest], BUG]); }
    return out;
  }

  root.looksLikeXrk = looksLikeXrk;
  root.looksLikeXrz = looksLikeXrz;
  root.parseAim = parseAim;
  if (typeof module !== 'undefined' && module.exports) module.exports = { looksLikeXrk: looksLikeXrk, looksLikeXrz: looksLikeXrz, parseAim: parseAim };
})(typeof globalThis !== 'undefined' ? globalThis : this);
