import sys, os, re
base, out, rd = sys.argv[1], sys.argv[2], sys.argv[3]
samples = sys.argv[4:6]   # optional: the two HP Tuners logs the prototype page embeds (private, never committed)
s = open(base).read()
if samples:
    import base64
    for var, path in zip(['HPL_B64', 'HPL2_B64'], samples):
        b = base64.b64encode(open(path, 'rb').read()).decode()
        lines = ',\n'.join('"' + b[i:i + 2000] + '"' for i in range(0, len(b), 2000))
        s, n = re.subn(r'const %s = "";' % var, lambda m: 'const %s = [\n%s\n].join("");' % (var, lines), s)
        assert n == 1, var
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:90], s.count(a)); s = s.replace(a, b)

mods = [('LINK', 'link.js', ['looksLikeLink', 'parseLink']),
        ('AIM', 'aim.js', ['looksLikeXrk', 'looksLikeXrz', 'parseAim']),
        ('FT', 'fueltech.js', ['looksLikeFuelTech', 'parseFuelTech']),
        ('EMU', 'ecumaster.js', ['looksLikeEmublog', 'looksLikeEmuPro', 'parseEcuMaster']),
        ('EMR', 'emerald.js', ['looksLikeEmeraldLg1', 'parseEmerald']),
        ('DEFI', 'dynamicefi.js', ['looksLikeDynamicEfi', 'parseDynamicEfi'])]
block = "  // ---------- ZIP (MaxxECU-Zip-log, zipped logs) ----------\n  // Reads the central directory, then opens the entry most likely to be the log.\n  const LOG_EXT = /\\.(maxxecu-log|maxxlog|hpl|mlg|ld|xrk|xrz|llg5?|ftml|emublog|emuprolog|gz|dat|lg1|vbo|msl|csv|tsv|txt|log)$/i;\n  const looksLikeZip = u8 => u8[0] === 0x50 && u8[1] === 0x4B && u8[2] === 3 && u8[3] === 4;\n  function unzipEntries(u8) {\n    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);\n    let e = -1;\n    for (let i = u8.length - 22; i >= Math.max(0, u8.length - 65557); i--) if (dv.getUint32(i, true) === 0x06054B50) { e = i; break; }\n    if (e < 0) throw new Error('damaged ZIP file (no directory)');\n    const count = dv.getUint16(e + 10, true);\n    let p = dv.getUint32(e + 16, true);\n    const out = [];\n    for (let k = 0; k < count && dv.getUint32(p, true) === 0x02014B50; k++) {\n      const method = dv.getUint16(p + 10, true), csize = dv.getUint32(p + 20, true), usize = dv.getUint32(p + 24, true);\n      const nl = dv.getUint16(p + 28, true), xl = dv.getUint16(p + 30, true), cl = dv.getUint16(p + 32, true), lho = dv.getUint32(p + 42, true);\n      const name = td.decode(u8.subarray(p + 46, p + 46 + nl));\n      p += 46 + nl + xl + cl;\n      if (name.endsWith('/')) continue;\n      out.push({ name, method, csize, usize, read: () => {\n        const ln = dv.getUint16(lho + 26, true), lx = dv.getUint16(lho + 28, true);\n        const raw = u8.subarray(lho + 30 + ln + lx, lho + 30 + ln + lx + csize);\n        if (method === 0) return raw.slice();\n        if (method === 8) return inflateRaw(raw, usize);\n        throw new Error(`ZIP entry ${name} uses an unsupported compression method (${method})`);\n      } });\n    }\n    return out;\n  }\n  function pickZipLog(u8) {\n    const entries = unzipEntries(u8).filter(x => !/\\.maxxecu-save$|\\.(bin|msq|ftm|ini|xml|pdf|png|jpe?g)$/i.test(x.name) && !/(^|\\/)(__MACOSX|\\.)/.test(x.name));\n    if (!entries.length) throw new Error('no log file inside the ZIP');\n    entries.sort((a, z) => (LOG_EXT.test(z.name) - LOG_EXT.test(a.name)) || (z.usize - a.usize));\n    const pick = entries[0];\n    return { name: pick.name.split('/').pop(), data: pick.read() };\n  }\n\n" + '  // EMU PRO logs carry every ECU channel (about 1,370); most never change. Hide those.\n  function dropFlat(r) {\n    if (!r.series || r.series.length < 200) return r;\n    const before = r.series.length;\n    r.series = r.series.filter(s => { const v = s.v; for (let i = 1; i < v.length; i++) if (v[i] !== v[0] && !(v[i] !== v[i] && v[0] !== v[0])) return true; return false; });\n    r.source += ` · ${before - r.series.length} unchanging channels hidden`;\n    return r;\n  }\n\n' + "  // Some Link G5 internal logs end with a short stretch where every channel holds another\n  // channel's bytes (4095, 4.97e8 …), all starting at the same moment. Cut the log there.\n  function trimCorruptTail(r) {\n    if (!r.series || r.series.length < 4) return r;\n    const tEnd = Math.max(...r.series.map(s => s.t[s.t.length - 1]));\n    const onsets = [];\n    for (const s of r.series) {\n      const n = s.v.length; if (n < 50) continue;\n      const head = Array.from(s.v.slice(0, Math.floor(n * 0.9))).filter(isFinite).sort((a, z) => a - z);\n      if (head.length < 20) continue;\n      const lo = head[Math.floor(head.length * 0.01)], hi = head[Math.floor(head.length * 0.99)];\n      const pad = Math.max(1, (hi - lo) * 3);\n      for (let i = Math.floor(n * 0.9); i < n; i++) {\n        const v = s.v[i];\n        if (isFinite(v) && (v < lo - pad || v > hi + pad)) { onsets.push(s.t[i]); break; }\n      }\n    }\n    if (onsets.length < r.series.length * 0.3) return r;\n    onsets.sort((a, z) => a - z);\n    const cut = onsets[Math.floor(onsets.length / 2)];\n    const together = onsets.filter(t => Math.abs(t - cut) < 0.05).length;\n    if (together < onsets.length * 0.6 || cut < tEnd * 0.8) return r;\n    for (const s of r.series) {\n      let k = 0; while (k < s.t.length && s.t[k] < cut - 1e-6) k++;\n      s.t = s.t.slice(0, k); s.v = s.v.slice(0, k);\n    }\n    r.series = r.series.filter(s => s.t.length);\n    r.source += ` · last ${(tEnd - cut).toFixed(2)} s dropped (corrupt in the file)`;\n    return r;\n  }\n\n" + '  // ---------- binary readers: Link, AiM, FuelTech, ECUMaster (each in its own scope) ----------\n'
have = []
for var, fn, names in mods:
    p = os.path.join(rd, fn)
    if not os.path.exists(p): block += f'  const {var} = null;\n'; continue
    code = open(p).read()
    block += f'  const {var} = (() => {{\n{code}\n  return {{ {", ".join(names)} }};\n  }})();\n'
    have.append(var)
rep("  window.__pwpReaders =", block + "\n  window.__pwpReaders =")

# readers that return per-channel time bases go onto the shared grid
rep("""      if (looksLikeHpl(head)) log = parseHpl(buf, name);""",
"""      const u8f = new Uint8Array(buf);
      const fromSeries = r => {
        if (!r.series) return r;
        const g = onGrid(r.series, name, r.source, 100);
        g.source = r.source; if (r.laps) g.laps = r.laps; if (r.markers) g.markers = r.markers;
        return g;
      };
      if (looksLikeHpl(head)) log = parseHpl(buf, name);
      else if (LINK && LINK.looksLikeLink(u8f)) log = fromSeries(trimCorruptTail(LINK.parseLink(buf, name)));
      else if (AIM && (AIM.looksLikeXrk(u8f) || AIM.looksLikeXrz(u8f))) log = fromSeries(AIM.parseAim(buf, name));
      else if (FT && FT.looksLikeFuelTech(u8f)) log = fromSeries(FT.parseFuelTech(buf, name));
      else if (EMU && (EMU.looksLikeEmublog(u8f) || EMU.looksLikeEmuPro(u8f))) log = fromSeries(dropFlat(EMU.parseEcuMaster(buf, name)));
      else if (EMR && /\\.lg1$/i.test(name) && EMR.looksLikeEmeraldLg1(u8f)) log = fromSeries(EMR.parseEmerald(buf, extra.lg2Text || null, name));
      else if (DEFI && DEFI.looksLikeDynamicEfi(u8f)) log = fromSeries(DEFI.parseDynamicEfi(buf, name));""")

# ZIP first: MaxxECU-Zip-log or any zipped log opens the log inside
rep("""      const buf = await getBuffer();
""", """      let buf = await getBuffer();
      if (looksLikeZip(new Uint8Array(buf, 0, Math.min(4, buf.byteLength)))) {
        const z = pickZipLog(new Uint8Array(buf));
        buf = z.data.buffer.slice(z.data.byteOffset, z.data.byteOffset + z.data.byteLength);
        name = `${z.name} (from ${name})`;
      }
""")

rep("""      useLog(log);
      const ms""", """      if (log.source === 'CSV' && /maxxecu|maxxlog/i.test(name)) log.source = 'MaxxECU log';
      useLog(log);
      const ms""")

# several files at once: Emerald .lg1 + .lg2 pair up
rep("  async function openLog(getBuffer, name) {", "  async function openLog(getBuffer, name, extra = {}) {")
rep('<input type="file" id="fileIn" hidden>', '<input type="file" id="fileIn" multiple hidden>')
rep("""    const f = $('fileIn').files[0]; if (!f) return;
    await openLog(() => f.arrayBuffer(), f.name);""",
"""    const files = [...$('fileIn').files]; if (!files.length) return;
    const lg1 = files.find(f => /\\.lg1$/i.test(f.name));
    if (lg1) {                                                   // Emerald: data in .lg1, channel list in .lg2
      const base = lg1.name.replace(/\\.lg1$/i, '').toLowerCase();
      const lg2 = files.find(f => /\\.lg2$/i.test(f.name) && f.name.replace(/\\.lg2$/i, '').toLowerCase() === base) || files.find(f => /\\.lg2$/i.test(f.name));
      const lg2Text = lg2 ? await lg2.text() : null;
      if (!lg2) toast('Tip: pick the .lg1 and its .lg2 together to get channel names');
      await openLog(() => lg1.arrayBuffer(), lg1.name, { lg2Text });
      return;
    }
    const f = files.find(x => !/\\.lg2$/i.test(x.name)) || files[0];
    await openLog(() => f.arrayBuffer(), f.name);""")

# notes: the full list of formats
import re as _re
s = _re.sub(r'<li><b>الصيغ:</b>[^<]*</li>', '<li><b>الصيغ:</b> HP Tuners .hpl (الجديد والقديم)، VCM CSV، LiveLink CSV، MoTeC .ld (M150/M1/i2)، AiM .xrk/.xrz، Link .llg/.llg5، ECUMaster .emublog/.emuprolog، FuelTech .ftml، Emerald .lg1+.lg2 (اختارهم مع بعض)، DynamicEFI .dat، Haltech NSP، MaxxECU .MaxxECU-log و .MaxxECU-Zip-log، MegaLogViewer .mlg، ECUMaster/RomRaider/Woolich/MHD وغيرها CSV، VBO، وأي لوق داخل ZIP</li>', s, count=1)
s = s.replace('<span>v9</span>', '<span>v15</span>', 1)

# keep the shared grid inside a memory budget (long, many-channel logs)
rep("""    const step = 1 / Math.min(maxRate, Math.max(1, Math.round(rate)));""",
"""    const budget = 8e6 / series.length / Math.max(1, t1 - t0);     // about 64 MB of samples at most
    const step = 1 / Math.max(0.5, Math.min(maxRate, Math.max(1, Math.round(rate)), budget));""")
open(out, 'w').write(s)
print('modules:', have)
