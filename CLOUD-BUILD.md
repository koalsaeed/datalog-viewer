# Build the APK — no installs, no computer software

You only need a browser. GitHub builds the app on its servers and gives you a
finished `app-release.apk`.

**Time per build:** 5–8 minutes.
**Cost:** free (public repo = unlimited build minutes).

---

## Step 1 — Create the repository

1. Go to https://github.com/new
2. Repository name: `datalog-viewer`
3. Choose **Public** (unlimited free build minutes)
4. **Do not** add a README, .gitignore, or license
5. Click **Create repository**

---

## Step 2 — Upload the project

On the empty repo page click **uploading an existing file**.

Then open this folder in File Explorer:

```
C:\Users\k-als\Documents\deepseek-harness\default-workspace\car-datalog\app
```

**Before selecting:** in Explorer click **View → Show → Hidden items**
(otherwise the `.github` folder stays invisible and the build will never run).

Press **Ctrl+A** to select everything, then drag it into the browser upload box.

Click **Commit changes**.

> You should end up with `lib/`, `assets/`, `pubspec.yaml` and `.github/` at the
> repo root — **not** inside an `app/` folder.

---

## Step 3 — Check the workflow file landed

Look at the repo file list. Do you see a `.github` folder?

**Yes** → skip to Step 4.

**No** → create it by hand (30 seconds):

1. **Add file → Create new file**
2. In the filename box type exactly:
   ```
   .github/workflows/build-apk.yml
   ```
   (typing `/` automatically creates folders)
3. Open `build-apk.yml` from your local folder in Notepad, copy all of it,
   paste it in the editor
4. **Commit changes**

---

## Step 4 — Let it build

1. Open the **Actions** tab
2. If GitHub asks, click **I understand my workflows, go ahead and enable them**
3. A run named **Build Android APK** starts by itself (or press **Run workflow**)
4. Wait 5–8 minutes. Green tick = done.

---

## Step 5 — Get the APK

1. Click the finished run
2. Scroll to **Artifacts** at the bottom
3. Download **datalog-viewer-apk** (it arrives as a `.zip`)
4. Unzip it → you get `app-release.apk`

You can do all of this from your phone browser if you prefer.

---

## Step 6 — Install on the phone

1. Transfer the APK to the phone (Google Drive, WhatsApp to yourself, USB…)
2. Tap it
3. Android asks for permission → **Settings → Install unknown apps → allow**
   for the app you opened it from (Chrome / Files)
4. Install

> **No Developer Mode needed.** This is ordinary sideloading.

If the "Install unknown apps" switch is greyed out or missing, the phone is
under company management (Knox/MDM) and blocks sideloading. In that case tell
me — we switch to a browser preview instead.

---

## Changing the app later

Every push triggers a new build. Two ways to change code:

- **I give you a file** → open it on GitHub, click the pencil, paste, commit.
- **I give you a patch** → you edit the one file I name.

The build starts automatically and a new APK appears in ~7 minutes.

---

## If the build fails

| Symptom | Fix |
|---|---|
| No run appears in Actions | `.github/workflows/build-apk.yml` is missing or nested too deep — must be at repo root |
| "Workflows aren't being run" | Settings → Actions → General → **Allow all actions** |
| Red X on a step | Open the step, copy the red error text, send it to me |
| APK won't install | Allow unknown sources; or the phone is MDM-managed |

---

## Trade-off you should know

Cloud builds are ~7 minutes per change, and there is **no live debugger**. When
something looks wrong you describe it, I read the code, and we rebuild.

If that gets painful we can add a **web build** (one more workflow file) so you
open a URL and see the current state instantly — same code, no install.
