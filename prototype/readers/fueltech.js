// FuelTech (FTManager / PowerFT: FT450, FT500, FT550, FT600) native datalog reader: .ftml
// Format worked out from sample files; FuelTech publishes no spec. See report for confidence.
//
// Container
//   The whole file is one raw DEFLATE stream (no zlib/gzip header; .NET DeflateStream).
//   Inflated, it is a .NET BinaryFormatter stream ([MS-NRBF], a public Microsoft spec)
//   whose root object is FTManager_Bll.FTDatalogger.DataloggerFile. Members used here:
//     SW_Version (string), FileVersion, Version, StartTime, EndTime, OffSetTime (double)
//     Times: DataloggerFileTimes { EcuInfo, MapInfo, DateSession (DateTime), Driver, Track, ... }
//     Channels: List<DataloggerChannel>, each
//       ChannelType      enum InSensor+MeasureTypeEnum (int; e.g. 24 = RPMIndex)
//       ChannelValueType enum (0 analog, 1 on/off, 2 cut-type counter, 3 small integer state)
//       SampleRate       int, sample period in ms (40 = 25 Hz)
//       Values           List<double>, already in engineering units
//       Enable           shown/exported by FTManager
//       Dividend, Divider, ValOffset (1,1,0 in every sample, applied as v*Dividend/Divider+ValOffset)
//     Adjust: the ECU map/config object graph. Its DataloggerSettings.Channels / .FTManagerChannels
//       lists carry ChannelID as the same enum (int). AdjustSream (sic) holds the same Adjust
//       XML-serialised, where enums appear by NAME, in the same list order; pairing the two lists
//       gives an in-file int -> enum-name map (e.g. 24 -> "RPMIndex").
//       Adjust.InOutSensors.Config_In_* (InSensor) give MeasureType + SensorDescription + SensorUnit
//       for the analog inputs (TPS "%", pressures "bar", temps "ºC", ...).
//     LogStream: the raw ECU memory dump the channels were decoded from (not needed here).
//   Time base: sample i of a channel is at i * SampleRate / 1000 s. StartTime/EndTime/OffSetTime
//   were 0/10/0 in both samples and do not describe the data span; they are reported in meta only.
//
// Host contract: inflateRaw(u8, size) and td (TextDecoder) are used when present; a small
// built-in inflater is used otherwise and for the cheap detection probe.

/* ---------- small raw-DEFLATE decoder (RFC 1951); maxOut bounds the output ---------- */
const FT_LBASE = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
const FT_LEXT = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
const FT_DBASE = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
const FT_DEXT = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
const FT_CLORD = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
function ftHuff(len, n) {
  const count = new Uint16Array(16), offs = new Uint16Array(16), sym = new Uint16Array(n);
  for (let i = 0; i < n; i++) count[len[i]]++;
  count[0] = 0;
  for (let i = 1; i < 16; i++) offs[i] = offs[i - 1] + count[i - 1];
  for (let i = 0; i < n; i++) if (len[i]) sym[offs[len[i]]++] = i;
  return { count, sym };
}
function ftInflate(src, maxOut, sizeHint) {
  let out = new Uint8Array(Math.min(maxOut || Infinity, sizeHint || src.length * 8) | 0 || 1024), op = 0;
  let pos = 0, bb = 0, bc = 0;
  const limit = maxOut || Infinity;
  const grow = (n) => { if (op + n > out.length) { const g = new Uint8Array(Math.max(out.length * 2, op + n)); g.set(out.subarray(0, op)); out = g; } };
  const bits = (n) => {
    while (bc < n) { if (pos >= src.length) throw new Error('deflate: data ended early'); bb |= src[pos++] << bc; bc += 8; }
    const v = bb & ((1 << n) - 1); bb >>>= n; bc -= n; return v;
  };
  const dec = (h) => {
    let code = 0, first = 0, idx = 0;
    for (let l = 1; l < 16; l++) {
      code |= bits(1); const c = h.count[l];
      if (code - c < first) return h.sym[idx + code - first];
      idx += c; first = (first + c) << 1; code <<= 1;
    }
    throw new Error('deflate: bad code');
  };
  let last = 0;
  while (!last && op < limit) {
    last = bits(1); const type = bits(2);
    if (type === 0) {
      bb = 0; bc = 0;
      if (pos + 4 > src.length) throw new Error('deflate: data ended early');
      const len = src[pos] | (src[pos + 1] << 8); pos += 4;
      grow(len); out.set(src.subarray(pos, pos + len), op); op += len; pos += len; continue;
    }
    let lit, dst;
    if (type === 1) {
      const l = new Uint8Array(288); l.fill(8, 0, 144); l.fill(9, 144, 256); l.fill(7, 256, 280); l.fill(8, 280, 288);
      lit = ftHuff(l, 288); dst = ftHuff(new Uint8Array(30).fill(5), 30);
    } else if (type === 2) {
      const nl = bits(5) + 257, nd = bits(5) + 1, nc = bits(4) + 4, cl = new Uint8Array(19);
      for (let i = 0; i < nc; i++) cl[FT_CLORD[i]] = bits(3);
      const ch = ftHuff(cl, 19), L = new Uint8Array(nl + nd);
      for (let i = 0; i < nl + nd;) {
        const s = dec(ch);
        if (s < 16) { L[i++] = s; continue; }
        let rep, val = 0;
        if (s === 16) { if (!i) throw new Error('deflate: bad lengths'); val = L[i - 1]; rep = 3 + bits(2); }
        else if (s === 17) rep = 3 + bits(3); else rep = 11 + bits(7);
        if (i + rep > nl + nd) throw new Error('deflate: bad lengths');
        while (rep--) L[i++] = val;
      }
      lit = ftHuff(L.subarray(0, nl), nl); dst = ftHuff(L.subarray(nl), nd);
    } else throw new Error('deflate: bad block type');
    for (;;) {
      let s = dec(lit);
      if (s < 256) { grow(1); out[op++] = s; if (op >= limit) break; continue; }
      if (s === 256) break;
      s -= 257; if (s >= 29) throw new Error('deflate: bad length code');
      const len = FT_LBASE[s] + bits(FT_LEXT[s]);
      const ds = dec(dst); if (ds >= 30) throw new Error('deflate: bad distance code');
      const d = FT_DBASE[ds] + bits(FT_DEXT[ds]);
      if (d > op) throw new Error('deflate: distance too far');
      grow(len);
      for (let k = 0; k < len; k++, op++) out[op] = out[op - d];
      if (op >= limit) break;
    }
  }
  return out.subarray(0, Math.min(op, limit));
}

/* ---------- [MS-NRBF] reader ---------- */
// Class instances become { $class, member: value, ... }; references stay { $ref: id }.
function ftNrbf(u8) {
  const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  const dec = (typeof td !== 'undefined' && td) ? td : new TextDecoder('utf-8');
  const objs = new Map(), meta = new Map();
  let p = 0, rootId = 0, depth = 0;
  const N = u8.length;
  const chk = (n) => { if (p + n > N) throw new Error('FuelTech: object stream truncated'); };
  const i32 = () => { chk(4); const v = dv.getInt32(p, true); p += 4; return v; };
  const u8r = () => { chk(1); return u8[p++]; };
  const str = () => {
    let len = 0, sh = 0, b;
    do { b = u8r(); len |= (b & 0x7f) << sh; sh += 7; } while ((b & 0x80) && sh < 35);
    chk(len); const s = dec.decode(u8.subarray(p, p + len)); p += len; return s;
  };
  const SZ = { 1: 1, 2: 1, 6: 8, 7: 2, 8: 4, 9: 8, 10: 1, 11: 4, 12: 8, 13: 8, 14: 2, 15: 4, 16: 8 };
  function prim(t) {
    let v;
    switch (t) {
      case 1: chk(1); return u8[p++] !== 0;
      case 2: chk(1); return u8[p++];
      case 3: { chk(1); const b = u8[p], n = b < 0x80 ? 1 : b < 0xe0 ? 2 : b < 0xf0 ? 3 : 4; chk(n); v = dec.decode(u8.subarray(p, p + n)); p += n; return v; }
      case 5: return parseFloat(str());
      case 6: chk(8); v = dv.getFloat64(p, true); p += 8; return v;
      case 7: chk(2); v = dv.getInt16(p, true); p += 2; return v;
      case 8: chk(4); v = dv.getInt32(p, true); p += 4; return v;
      case 9: case 12: chk(8); v = Number(dv.getBigInt64(p, true)); p += 8; return v;
      case 13: chk(8); v = dv.getBigUint64(p, true); p += 8; return { $dateData: v };
      case 10: chk(1); v = dv.getInt8(p); p += 1; return v;
      case 11: chk(4); v = dv.getFloat32(p, true); p += 4; return v;
      case 14: chk(2); v = dv.getUint16(p, true); p += 2; return v;
      case 15: chk(4); v = dv.getUint32(p, true); p += 4; return v;
      case 16: chk(8); v = Number(dv.getBigUint64(p, true)); p += 8; return v;
      case 17: return null;
      case 18: return str();
      default: throw new Error('FuelTech: bad primitive type ' + t);
    }
  }
  function primArray(t, n) {
    const sz = SZ[t];
    if (sz && (t === 6 || t === 2 || t === 11)) {
      chk(n * sz); const bytes = u8.slice(p, p + n * sz); p += n * sz;
      return t === 6 ? new Float64Array(bytes.buffer) : t === 11 ? new Float32Array(bytes.buffer) : bytes;
    }
    if (n > N) throw new Error('FuelTech: bad array length');
    const a = new Array(n);
    for (let i = 0; i < n; i++) a[i] = prim(t);
    return a;
  }
  function classInfo() {
    const id = i32(), name = str(), cnt = i32();
    if (cnt < 0 || cnt > 100000) throw new Error('FuelTech: bad member count');
    const names = new Array(cnt);
    for (let i = 0; i < cnt; i++) names[i] = str();
    return { id, name, names };
  }
  function memberTypes(cnt) {
    const bt = new Array(cnt), ex = new Array(cnt);
    for (let i = 0; i < cnt; i++) bt[i] = u8r();
    for (let i = 0; i < cnt; i++) {
      const b = bt[i];
      if (b === 0 || b === 7) ex[i] = u8r();
      else if (b === 3) ex[i] = str();
      else if (b === 4) { ex[i] = str(); i32(); }
      else ex[i] = null;
    }
    return { bt, ex };
  }
  function members(id, m) {
    const o = { $class: m.name };
    if (id) objs.set(id, o);
    for (let i = 0; i < m.names.length; i++) o[m.names[i]] = (m.types && m.types.bt[i] === 0) ? prim(m.types.ex[i]) : record();
    return o;
  }
  function newClass(withTypes, withLib) {
    const ci = classInfo();
    const m = { name: ci.name, names: ci.names, types: withTypes ? memberTypes(ci.names.length) : null };
    if (withLib) i32();
    meta.set(ci.id, m);
    return members(ci.id, m);
  }
  function objArray(n) {
    if (n < 0 || n > N) throw new Error('FuelTech: bad array length');
    const a = new Array(n);
    for (let i = 0; i < n;) {
      const v = record();
      if (v && v.$nulls !== undefined) { for (let k = 0; k < v.$nulls && i < n; k++) a[i++] = null; }
      else a[i++] = v;
    }
    return a;
  }
  function record() {
    if (++depth > 2000) throw new Error('FuelTech: object graph too deep');
    try {
      const rt = u8r();
      switch (rt) {
        case 0: rootId = i32(); i32(); i32(); i32(); return undefined;
        case 1: { const id = i32(), mid = i32(), m = meta.get(mid); if (!m) throw new Error('FuelTech: unknown class ref'); return members(id, m); }
        case 2: return newClass(false, false);
        case 3: return newClass(false, true);
        case 4: return newClass(true, false);
        case 5: return newClass(true, true);
        case 6: { const id = i32(), s = str(); objs.set(id, s); return s; }
        case 7: {
          const id = i32(), at = u8r(), rank = i32();
          if (rank < 1 || rank > 32) throw new Error('FuelTech: bad array rank');
          const lens = []; for (let i = 0; i < rank; i++) lens.push(i32());
          if (at >= 3 && at <= 5) for (let i = 0; i < rank; i++) i32();
          const ty = memberTypes(1);
          const n = lens.reduce((a, b) => a * b, 1);
          let arr = ty.bt[0] === 0 ? primArray(ty.ex[0], n) : objArray(n);
          if (rank > 1) arr = { $dims: lens, data: arr };
          objs.set(id, arr); return arr;
        }
        case 8: return prim(u8r());
        case 9: return { $ref: i32() };
        case 10: return null;
        case 11: return { $end: true };
        case 12: { i32(); str(); return record(); }
        case 13: return { $nulls: u8r() };
        case 14: return { $nulls: i32() };
        case 15: { const id = i32(), n = i32(), t = u8r(); if (n < 0) throw new Error('FuelTech: bad array'); const a = primArray(t, n); objs.set(id, a); return a; }
        case 16: case 17: { const id = i32(), n = i32(); const a = objArray(n); objs.set(id, a); return a; }
        default: throw new Error('FuelTech: unsupported record type ' + rt + ' at ' + (p - 1));
      }
    } finally { depth--; }
  }
  while (p < N) { const v = record(); if (v && v.$end) break; }
  const R = (v) => (v && v.$ref !== undefined ? objs.get(v.$ref) : v);
  return { root: objs.get(rootId), objs, R };
}

/* ---------- channel naming ---------- */
// Fallback MeasureTypeEnum names (seen in the sample files' own XML), used only when a file
// lacks the XML copy of its Adjust. Files normally supply the full map themselves.
const FT_ENUM_FALLBACK = {
  0: 'TPSIndex', 1: 'MAPIndex', 2: 'AirTempIndex', 3: 'EngineTempIndex', 4: 'OilPressureIndex',
  5: 'FuelPressureIndex', 8: 'VBatIndex', 24: 'RPMIndex', 25: 'InjBankAIndex', 51: 'InjAdvanceIndex',
  54: 'IgnDwellIndex', 55: 'IgnAdvanceIndex', 79: 'IdlePWMIndex', 89: 'VPGNDIndex', 92: 'StatusEventIndex',
  98: 'InjBankADutyIndex', 100: 'IdleActuatorPosIndex', 125: 'ActualGearIndex', 151: 'LambdaTargetIndex',
  152: 'LambdaCorrectionIndex', 171: 'RPM2Index', 204: 'Exhaust_O2Index', 230: 'DeltaTPS_Index',
  231: 'LambdaMF_Index', 351: 'FuelFlowBankAIndex', 365: 'WheelSpeed_TractionHiResIndex',
  403: 'CamSyncSensorRPMIndex', 434: 'PedalPosIndex', 450: 'Eletro1_InjEnrichIndex', 632: 'Inj_Fast_DecayIndex',
  761: 'FuelCalc_FuelLevel_Index', 764: 'FuelCalc_Consu_Total_Index', 765: 'FuelCalc_Consu_Avg_Index',
  766: 'FuelCalc_Consu_Instant_Index', 767: 'EnginePower_Index', 768: 'EngineTorque_Index',
  770: 'FuelCalc_Dist_Total_Index', 771: 'FuelCalc_Autonomy_Index',
  5000: 'TwoStep_Digital_Index', 5003: 'Eletro1_Digital_Index', 5007: 'CutOff_Digital_Index',
  5008: 'Pump_Digital_Index', 5010: 'Gear_Digital_Index', 5023: 'GapSync_Digital_Index',
  5037: 'TwoStep_Validated_Digital_Index', 5047: 'ActiveAdjust_Digital_Index', 5057: 'FastInj_Digital_Index',
  5058: 'DecayInj_DigitalIndex', 5059: 'CutOffInj_DigitalIndex', 5060: 'Idle_Digital_Index',
  5061: 'PostStart_Digital_Index', 5139: 'Engine_Cranking_Digital_Index', 5140: 'Engine_Idle_Digital_Index',
  5142: 'PrimePulse_Digital_Index', 5158: 'StarterButton_Digital_Index', 7002: 'CUT_HARD_CUT_RPM_Index',
};
// Display names (FTManager's own English CSV export labels where known) and units.
// Units assume FTManager's default unit settings (pressure bar, temperature °C, lambda, km/h);
// analog-input units are taken from the file's sensor configuration when present.
const FT_NAMES = {
  RPMIndex: ['RPM', 'rpm'], RPM2Index: ['RPM 2', 'rpm'], CamSyncSensorRPMIndex: ['Cam sync sensor RPM', 'rpm'],
  TPSIndex: ['TPS', '%'], PedalPosIndex: ['Pedal position', '%'], MAPIndex: ['MAP', 'bar'],
  IgnAdvanceIndex: ['Ignition timing', '°'], IgnDwellIndex: ['Ignition dwell', 'ms'],
  LambdaTargetIndex: ['O2 target', 'λ'], LambdaCorrectionIndex: ['O2 correction', '%'],
  Exhaust_O2Index: ['O2 general', 'λ'], LambdaMF_Index: ['O2 closed loop', 'λ'],
  InjBankAIndex: ['Primary injection time', 'ms'], InjBankADutyIndex: ['Primary injector duty', '%'],
  EngineTempIndex: ['Engine temp.', '°C'], AirTempIndex: ['Air temperature', '°C'],
  OilPressureIndex: ['Oil pressure', 'bar'], FuelPressureIndex: ['Fuel pressure', 'bar'],
  VBatIndex: ['Battery voltage', 'V'], WheelSpeed_TractionHiResIndex: ['Wheel speed traction', 'km/h'],
  ActualGearIndex: ['Gear (actual)', ''], Gear_Digital_Index: ['Gear', ''], ActiveAdjust_Digital_Index: ['Active map', ''],
  TwoStep_Digital_Index: ['2-step', ''], TwoStep_Validated_Digital_Index: ['Validated launch', ''],
  GapSync_Digital_Index: ['RPM sync valid', ''], CutOff_Digital_Index: ['Cutoff', ''],
  Engine_Cranking_Digital_Index: ['Engine cranking', ''], Engine_Idle_Digital_Index: ['Idle', ''],
  PrimePulse_Digital_Index: ['Prime pulse', ''], Eletro1_Digital_Index: ['Thermatic fan #1', ''],
  Eletro2_Digital_Index: ['Thermatic fan #2', ''], Pump_Digital_Index: ['Fuel pump', ''],
  FastInj_Digital_Index: ['Acceleration fuel enrichment', ''], DecayInj_DigitalIndex: ['Decay fuel enrichment', ''],
  CutOffInj_DigitalIndex: ['Deceleration cutoff enrichment', ''], Idle_Digital_Index: ['Idle speed control', ''],
  PostStart_Digital_Index: ['Post start enrichment', ''], StarterButton_Digital_Index: ['Engine Start/Stop button', ''],
  CUT_HARD_CUT_RPM_Index: ['Cut: RPM limiter', ''],
};
function ftPretty(e) {
  return e.replace(/_?Digital_?Index$|_?Index$/, '').replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').trim() || e;
}

function looksLikeFuelTech(u8) {
  if (!u8 || u8.length < 64) return false;
  let head;
  const isNrbf = (h) => h.length > 40 && h[0] === 0 && h[1] === 1 && h[2] === 0 && h[3] === 0 && h[4] === 0 && h[5] === 0xff && h[9] === 1;
  if (isNrbf(u8)) head = u8.subarray(0, 512);       // uncompressed variant, if one exists
  else { try { head = ftInflate(u8.subarray(0, 65536), 512); } catch (e) { return false; } }
  if (!isNrbf(head)) return false;
  let s = '';
  for (let i = 0; i < head.length; i++) s += String.fromCharCode(head[i]);
  return s.indexOf('FTManager_Bll') >= 0 && s.indexOf('DataloggerFile') >= 0;
}

function parseFuelTech(buf, name, opts) {
  opts = opts || {};
  const src = new Uint8Array(buf);
  if (!looksLikeFuelTech(src)) throw new Error('Not a FuelTech .ftml datalog');
  let raw;
  if (src[0] === 0 && src[5] === 0xff) raw = src;
  else if (typeof inflateRaw === 'function') raw = inflateRaw(src, src.length * 24);
  else raw = ftInflate(src, 0, src.length * 24);
  const { root, objs, R } = ftNrbf(raw);
  if (!root || !/DataloggerFile$/.test(root.$class || '')) throw new Error('FuelTech: root object is not a DataloggerFile');
  const B = (o, k) => (o ? R(o['<' + k + '>k__BackingField'] !== undefined ? o['<' + k + '>k__BackingField'] : o[k]) : undefined);
  const ev = (v) => { v = R(v); return v && typeof v === 'object' && 'value__' in v ? v.value__ : v; };
  const listItems = (L) => { L = R(L); if (!L) return []; if (Array.isArray(L) || ArrayBuffer.isView(L)) return L; const it = R(L._items) || []; return Array.prototype.slice.call(it, 0, L._size == null ? it.length : L._size); };

  // int -> enum name, from the XML copy of the Adjust (enum names) paired with the binary lists.
  const enumName = new Map();
  let dls = null; const sensors = [];
  for (const o of objs.values()) {
    if (!o || !o.$class) continue;
    if (/\.DataloggerSettings$/.test(o.$class)) dls = o;
    else if (/\.IN\.InSensor$/.test(o.$class)) sensors.push(o);
  }
  const xmlBytes = B(root, 'AdjustSream') || B(root, 'AdjustStream');
  if (dls && xmlBytes && xmlBytes.length) {
    try {
      const xml = ((typeof td !== 'undefined' && td) ? td : new TextDecoder('utf-8')).decode(xmlBytes);
      const pair = (listKey, tag) => {
        const bin = listItems(B(dls, listKey)).map(R);
        const re = new RegExp('<' + tag + '>\\s*<ChannelID>([^<]*)</ChannelID>', 'g');
        const names = []; let m; while ((m = re.exec(xml))) names.push(m[1]);
        if (names.length !== bin.length) return;
        bin.forEach((c, k) => { const id = ev(B(c, 'ChannelID')); if (typeof id === 'number' && !enumName.has(id)) enumName.set(id, names[k]); });
      };
      pair('Channels', 'DataloggerChannelItem');
      pair('FTManagerChannels', 'FTManagerChannelConfig');
      // analog input sensors: <MeasureType>Name</MeasureType> in Config_In_* order
      const xs = []; const re2 = /<MeasureType>([^<]*)<\/MeasureType>/g; let m2; while ((m2 = re2.exec(xml))) xs.push(m2[1]);
      if (xs.length === sensors.length) sensors.forEach((s, k) => { const id = ev(B(s, 'MeasureType')); if (!enumName.has(id)) enumName.set(id, xs[k]); });
    } catch (e) { /* fall back to built-in names */ }
  }
  const sensorUnit = new Map();
  for (const s of sensors) {
    const id = ev(B(s, 'MeasureType')); let u = B(s, 'SensorUnit');
    if (typeof id !== 'number' || id === 65535 || typeof u !== 'string' || !u) continue;
    u = u.replace(/^º/, '°').replace(/^km\/$/, 'km/h').replace(/^mph?$/, 'mph');
    if (!sensorUnit.has(id)) sensorUnit.set(id, u);
  }

  // channels
  const chans = listItems(B(root, 'Channels')).map(R).filter(Boolean);
  const picked = [];
  for (const c of chans) {
    const id = ev(B(c, 'ChannelType'));
    const vl = R(B(c, 'Values'));
    let v = vl ? (Array.isArray(vl) || ArrayBuffer.isView(vl) ? vl : R(vl._items)) : null;
    if (!v) continue;
    const n = vl && vl._size != null ? vl._size : v.length;
    const enabled = B(c, 'Enable') !== false;
    if (!enabled && !opts.includeDisabled) continue;
    let sr = +B(c, 'SampleRate'); if (!(sr > 0)) sr = 40;
    const dvd = +B(c, 'Dividend'), dvs = +B(c, 'Divider'), off = +B(c, 'ValOffset') || 0;
    const scale = (dvd && dvs && (dvd !== 1 || dvs !== 1)) ? dvd / dvs : 1;
    const out = new Float64Array(n);
    let mn = Infinity, mx = -Infinity;
    for (let i = 0; i < n; i++) { const x = +v[i] * scale + off; out[i] = x; if (x < mn) mn = x; if (x > mx) mx = x; }
    if (!enabled && !(mx > mn)) continue;               // skip flat hidden channels
    const vt = ev(B(c, 'ChannelValueType'));
    const en = enumName.get(id) || FT_ENUM_FALLBACK[id] || ('Channel ' + id);
    const nm = FT_NAMES[en];
    let unit = sensorUnit.get(id) || (nm ? nm[1] : '');
    // 32.767 (0x7FFF / 1000) on every sample = input not connected
    if (n && mn === mx && (Math.abs(mn - 32.767) < 1e-9 || Math.abs(mn - 3276.7) < 1e-9)) out.fill(NaN);
    picked.push({ id, en, n: nm ? nm[0] : ftPretty(en), u: unit, sr, v: out, len: n, vt, enabled });
  }
  if (!picked.length) throw new Error('FuelTech: no channels with data');

  // common time grid at the fastest sample period; slower channels are sample-and-hold.
  let base = Infinity, span = 0;
  for (const c of picked) { if (c.sr < base) base = c.sr; span = Math.max(span, c.len * c.sr); }
  const T = Math.max(1, Math.round(span / base));
  const t = new Float64Array(T);
  for (let i = 0; i < T; i++) t[i] = i * base / 1000;
  const used = new Map();
  const ch = picked.map((c) => {
    let v;
    if (c.sr === base && c.len === T) v = c.v;
    else {
      v = new Float64Array(T); const r = base / c.sr;
      for (let i = 0; i < T; i++) { const k = Math.floor(i * r + 1e-9); v[i] = k < c.len ? c.v[k] : NaN; }
    }
    let n = c.n; const k = used.get(n) || 0; used.set(n, k + 1); if (k) n += ' ' + (k + 1);
    const o = { n, u: c.u, v, id: c.id, internal: c.en };
    if (c.vt === 1) o.labels = ['OFF', 'ON'];
    return o;
  });

  // metadata
  const times = B(root, 'Times') || {};
  const s = (x) => (typeof x === 'string' && x ? x : undefined);
  let date;
  const ds = B(times, 'DateSession');
  if (ds && ds.$dateData !== undefined) {
    const ticks = Number(ds.$dateData & 0x3FFFFFFFFFFFFFFFn);       // low 62 bits = ticks (100 ns since 0001-01-01)
    const ms = ticks / 1e4 - 62135596800000;
    if (isFinite(ms) && ms > 0) date = new Date(ms).toISOString().replace('Z', '').replace(/\.\d+$/, ''); // wall clock as recorded
  }
  const ecu = s(B(times, 'EcuInfo'));
  const meta = {
    ecu: ecu && ecu.replace(/\s+/g, ' ').trim(), map: s(B(times, 'MapInfo')), date, swVersion: s(B(root, 'SW_Version')),
    fileVersion: B(root, 'FileVersion'), driver: s(B(times, 'Driver')), track: s(B(times, 'Track')), car: s(B(times, 'CarInfo')),
    comments: s(B(times, 'Comments')), startTime: B(root, 'StartTime'), endTime: B(root, 'EndTime'), offsetTime: B(root, 'OffSetTime'),
    samplePeriodMs: base,
  };
  return { name, source: 'FuelTech FTManager .ftml' + (meta.ecu ? ' (' + meta.ecu + ')' : ''), t, ch, meta };
}
if (typeof module !== 'undefined' && module.exports) module.exports = { looksLikeFuelTech, parseFuelTech };
