import sys, re
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:80], s.count(a)); s = s.replace(a, b)
# no personal logs in the app build (the repo is public): drop the embedded HP Tuners samples
s, n = re.subn(r'const (HPL2?_B64) = (\[\n[\s\S]*?\n\]\.join\(""\)|""[^\n]*);', r'const \1 = "";', s); assert n == 2, n
s = re.sub(r'\s*<button id="mSampleHpl2?">[\s\S]*?</button>', '', s)
rep("  $('mSampleHpl').onclick = () => { menu.hidden = true; openLog(async () => b64(HPL_B64), HPL_NAME); };\n", "")
rep("  $('mSampleHpl2').onclick = () => { menu.hidden = true; openLog(async () => b64(HPL2_B64), HPL2_NAME); };\n", "")
rep("  openLog(async () => b64(HPL_B64), HPL_NAME);\n",
    "  openLog(async () => new TextEncoder().encode(document.getElementById('sampleCsv').textContent).buffer, 'sample: datalog3.csv');\n")
# full-screen app mode: no phone frame, no notes
rep("<style>\n", """<style>
html.app, html.app body { padding: 0 !important; margin: 0; height: 100%; overflow: hidden; }
html.app .caption, html.app .notes, html.app .phone::before { display: none; }
html.app .stage { display: block; }
html.app .fit, html.app .phone-holder { width: 100vw !important; height: 100vh !important; max-width: none; }
html.app .phone { position: fixed; inset: 0; width: 100vw; height: 100vh; padding: 0; border-radius: 0; box-shadow: none; transform: none !important; background: var(--bg); }
html.app .screen { width: 100%; height: 100%; border-radius: 0; }
""")
s = s.replace("<script>\n", "<script>document.documentElement.classList.add('app');</script>\n<script>\n", 1)
rep("  function layoutPhone() {\n", "  function layoutPhone() {\n    if (document.documentElement.classList.contains('app')) { scale = 1; resizeCanvases(); return; }\n")

# Inside the Android app, "Open log…" asks the app to pick files; the app reads them and
# streams them in as base64 chunks (the WebView's own file field is unreliable on phones).
rep("""  $('fileIn').onchange = async () => {
    const files = [...$('fileIn').files]; if (!files.length) return;""",
"""  $('fileIn').onchange = () => openPicked([...$('fileIn').files]);
  async function openPicked(files) {
    if (!files.length) return;""")
rep("""    await openLog(() => f.arrayBuffer(), f.name);
  };""", """    await openLog(() => f.arrayBuffer(), f.name);
  }
  const incoming = [];
  window.__pwpReceive = {
    begin(name) { incoming.push({ name, parts: [] }); $('loading').hidden = false; $('loading').textContent = `Reading ${name}…`; },
    chunk(b) {
      const s = atob(b), u = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
      incoming[incoming.length - 1].parts.push(u);
    },
    done() {
      const files = incoming.splice(0).map(f => {
        const n = f.parts.reduce((a, q) => a + q.length, 0), u = new Uint8Array(n);
        let o = 0; for (const q of f.parts) { u.set(q, o); o += q.length; }
        return { name: f.name, arrayBuffer: async () => u.buffer, text: async () => new TextDecoder().decode(u) };
      });
      if (!files.length) { $('loading').hidden = !!channels; return; }
      openPicked(files);
    },
    fail(msg) { incoming.length = 0; $('loading').hidden = !!channels; toast(`Could not read the file: ${msg}`); },
  };""")
rep("""  $('mOpen').onclick = () => { menu.hidden = true; $('fileIn').value = ''; $('fileIn').click(); };""",
"""  $('mOpen').onclick = () => {
    menu.hidden = true;
    if (window.PWPApp) { PWPApp.postMessage('open'); return; }       // Android app: native file picker
    $('fileIn').value = ''; $('fileIn').click();
  };""")

open(out, 'w').write(s)
print('ok', len(s))
