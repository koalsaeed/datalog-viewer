// DynamicEFI / EBL Flash ("What's Up Display") datalog reader: .dat
// Format reverse-engineered from ONE sample file (20251006_0834_toWorkNewCap.dat, GM TBI with an
// EBL Flash calibration) and its CSV export. No public spec was used. Offsets below are verified
// against that CSV only; other ECM definitions / EBL versions may use a different layout, in which
// case the parser refuses the file instead of guessing.
//
// File = CRLF text header + binary frames.
//   Header: first line "TIME: MM/DD/YYYY - hh:mm:ss[ID] EBL Flash ...", then "[KEY] value" lines
//           ([PORT], [TEMPERSCALE] 0=degF, [KPHORMPH] 0=mph, [UDn...], [ADn...]). The last line in
//           the sample is "[AD7FPPREF] n"; binary data starts right after its CRLF.
//   Binary: fixed 277-byte frames, no length/sync header; bytes 67..68 are always 0x55 0xAA.
//           The last frame may be truncated (sample: 199 of 277 bytes).
//   One logical sample (= one CSV row) is  frame[i][0..63]  +  frame[i-1][64..276]:
//   the low part (PC-side / fast values: ECM run time, 160 Hz counter, G/S, IAC, BARO, CTS,
//   AE pulse, wideband ADC) comes from frame i, the rest from the previous frame. The split point
//   is only bracketed to 51..71 by the data; 64 is used. The CSV's first row is a default/initial
//   row that is not in the file and is not reproduced here.
//   Time base: byte 13 is a 0..159 counter (GM 160 Hz minor-loop style) - unwrapped modulo 160.
//   Multi-byte values are big-endian.

function looksLikeDynamicEfi(u8) {
  if (!u8 || u8.length < 64) return false;
  const head = String.fromCharCode.apply(null, Array.from(u8.subarray(0, Math.min(400, u8.length))));
  return /^TIME: \d\d\/\d\d\/\d{4} - \d\d:\d\d:\d\d\[ID\] EBL Flash/.test(head);
}

function parseDynamicEfi(buf, name) {
  const u8 = new Uint8Array(buf);
  const N = u8.length;
  if (!looksLikeDynamicEfi(u8)) throw new Error('Not a DynamicEFI / EBL Flash .dat file');

  // ---- text header ----
  const meta = {};
  let o = 0;
  const readLine = () => {
    let e = o;
    while (e + 1 < N && !(u8[e] === 13 && u8[e + 1] === 10)) e++;
    if (e + 1 >= N) return null;
    let s = '';
    for (let i = o; i < e; i++) s += String.fromCharCode(u8[i]);
    o = e + 2;
    return s;
  };
  const first = readLine();
  const m0 = /^TIME: (\d\d)\/(\d\d)\/(\d{4}) - (\d\d:\d\d:\d\d)\[ID\] (.*)$/.exec(first || '');
  if (m0) { meta.date = m0[3] + '-' + m0[1] + '-' + m0[2]; meta.time = m0[4]; meta.id = m0[5]; }
  let binStart = -1;
  for (;;) {
    const save = o;
    if (o >= N || u8[o] !== 0x5b) { binStart = save; break; } // binary does not start with '['
    const line = readLine();
    if (line === null) { binStart = save; break; }
    const m = /^\[([A-Z0-9._]+)\] ?(.*)$/.exec(line);
    if (!m) { binStart = save; break; }
    meta[m[1]] = m[2];
    if (m[1] === 'AD7FPPREF') { binStart = o; break; } // last header key in the sample
  }

  // ---- frame layout check ----
  const FL = 277, SPLIT = 64;
  const nFull = Math.floor((N - binStart) / FL);
  const tail = (N - binStart) % FL;
  if (nFull < 2) throw new Error('DynamicEFI: no data frames');
  let good = 0;
  for (let i = 0; i < nFull; i++) {
    const b = binStart + i * FL;
    if (u8[b + 67] === 0x55 && u8[b + 68] === 0xaa) good++;
  }
  if (good < nFull * 0.95) throw new Error('DynamicEFI: unsupported frame layout (expected 277-byte frames with 55 AA at +67)');

  const nRec = nFull - 1 + (tail >= SPLIT ? 1 : 0);
  // byte accessor for logical sample r (1-based frame index i = r + 1)
  const at = (i, off) => u8[binStart + (off < SPLIT ? i : i - 1) * FL + off];
  const be16 = (i, off) => (at(i, off) << 8) | at(i, off + 1);

  const tempF = String(meta.TEMPERSCALE || '0').trim() !== '1'; // 0 => degF (verified); 1 => degC (assumed)
  const kph = String(meta.KPHORMPH || '0').trim() === '1';       // 0 => mph (verified); 1 => km/h (assumed)
  const temp = (x) => (tempF ? x * 1.35 - 40 : x * 0.75 - 40);
  const tU = tempF ? '°F' : '°C';
  const mapK = (x) => x * 0.369 + 10.41; // fitted: slope 1/2.71, intercept in [10.408, 10.415]

  const DEF = [
    // [name, unit, fn(i)] - verified against the CSV export unless noted in the report
    ['RUNTIME', 's', (i) => be16(i, 27)],
    ['RPM', 'rpm', (i) => be16(i, 98) * 12.5 / 256],
    [kph ? 'KPH' : 'MPH', kph ? 'km/h' : 'mph', (i) => (kph ? at(i, 121) * 1.609344 : at(i, 121))],
    ['MAP', 'kPa', (i) => mapK(at(i, 114))],
    ['BRO', 'kPa', (i) => mapK(at(i, 46))],
    ['VAC', 'kPa', (i) => 80 - at(i, 118) * 0.3125],
    ['VE%', '%', (i) => at(i, 238) * 100 / 256],
    ['TPS', '%', (i) => at(i, 142) * 100 / 256],
    ['CTS', tU, (i) => temp(at(i, 19))],
    ['IAT', tU, (i) => temp(at(i, 195))],
    ['I/C', tU, (i) => temp(at(i, 194))],
    ['O2', 'mV', (i) => at(i, 131) * 4.42],
    ['G/S', 'g/s', (i) => at(i, 32)],
    ['SA', '°', (i) => at(i, 79) * 90 / 256],
    ['Rt', '°', (i) => at(i, 188) * 45 / 256],
    ['KnkCt', 'count', (i) => be16(i, 184)],
    ['sPW', 'ms', (i) => be16(i, 236) / 65.536],
    ['BPC', '', (i) => be16(i, 175) / 256],
    ['IAC', 'steps', (i) => at(i, 45)],
    ['AFR', ':1', (i) => at(i, 234) / 10],
    ['WB', 'AFR', (i) => 9.6082 + be16(i, 49) * 10 / 1023], // AD0 Zeitronix 0V=9.6 .. 5V=19.6, 10-bit ADC
    ['dTPS', '%', (i) => Math.max(0, at(i, 142) - at(i, 144)) * 100 / 256],
    ['tpsAE', 'ms', (i) => at(i, 223) / 65.536],
    ['dMAP', 'kPa', (i) => at(i, 119) * 0.3125],
    ['mapAE', 'ms', (i) => at(i, 222) / 65.536],
    ['aePW', 'ms', (i) => be16(i, 42) / 65.536],
    ['Cl (2)', '', (i) => at(i, 231)], // second "Cl" column of the CSV; meaning unknown
  ];
  const BITS = [
    ['Ae', 82, 6], ['De', 82, 4], ['Id', 72, 3],
  ];

  const t = new Float64Array(nRec);
  const ch = DEF.map(([n, u]) => ({ n, u, v: new Float64Array(nRec) }));
  const fl = BITS.map(([n]) => ({ n, u: '', v: new Float64Array(nRec), labels: ['N', 'Y'] }));
  const gr = { n: 'Gr', u: '', v: new Float64Array(nRec), labels: ['D', 'P/N'] };
  // DC% as the tool computes it: floor(sPW * RPM / 300) using the displayed RPM (12.5 rpm steps)
  const dc = { n: 'DC%', u: '%', v: new Float64Array(nRec) };

  let ticks = 0;
  for (let r = 0; r < nRec; r++) {
    const i = r + 1;
    const c = at(i, 13);
    if (r > 0) ticks += (((c - at(i - 1, 13)) % 160) + 160) % 160;
    t[r] = ticks / 160;
    for (let j = 0; j < DEF.length; j++) ch[j].v[r] = DEF[j][2](i);
    for (let j = 0; j < BITS.length; j++) fl[j].v[r] = (at(i, BITS[j][1]) >> BITS[j][2]) & 1;
    gr.v[r] = (at(i, 84) >> 4) & 1;
    const rpmDisp = Math.floor(Math.round(be16(i, 98) / 256) * 12.5);
    dc.v[r] = Math.floor(be16(i, 236) / 65.536 * rpmDisp / 300 + 1e-9);
  }
  // CSV column order
  const byName = (n) => ch.find((c) => c.n === n);
  const all = ch.slice(0, 17).concat([dc], fl, [gr, byName('Cl (2)')],
    ch.slice(17).filter((c) => c.n !== 'Cl (2)'));

  meta.frames = nFull + (tail ? 1 : 0);
  meta.frameLength = FL;
  meta.truncatedTailBytes = tail;
  return {
    name,
    source: 'DynamicEFI / EBL Flash .dat' + (meta.id ? ' (' + meta.id + ')' : ''),
    meta,
    t,
    ch: all,
  };
}
