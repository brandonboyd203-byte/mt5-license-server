# Keep Licenses + Logo on Railway (do this once)

Without this, **every redeploy wipes licenses** and the **logo won’t show** until you add the file. Follow these steps in Railway so both persist.

---

## 1. Create a volume and attach it

1. In **Railway** → open your **mt5-license-server** (or license-server) service.
2. Click the **⋮** (three dots) or **Settings** on the service tile.
3. Click **“Attach volume”** (or **Volumes** → **Add volume**).
4. Set **Mount path** to: **`/data`**
5. Save. Railway will create a volume that survives redeploys.

---

## 2. Set environment variables

In the same service: **Variables** (or **Settings** → **Environment**).

Add these **exact** names and values:

| Variable | Value |
|----------|--------|
| `LICENSE_FILE` | `/data/licenses.json` |
| `COPIER_SUBSCRIBERS_FILE` | `/data/copier_subscribers.json` |

Save. The app will now read/write licenses and copier subscribers under `/data`, which is on the volume, so they **persist across deploys**.

---

## 3. Logo (pick one)

**Option A – Logo in the repo (recommended)**  
- Put your logo file in the project: **`assets/LOGO.png`** (or `assets/logo.png`).  
- Commit and push to `main`.  
- After deploy, the site will serve it at `/logo`. Hard-refresh the page (Cmd+Shift+R).

**Option B – Logo on the volume**  
- Add variable: **`LOGO_PATH`** = **`/data/LOGO.png`**  
- Upload your logo into the volume (e.g. via a one-off script or Railway’s volume tools if available).  
- Redeploy. The app will serve the file from `/data/LOGO.png`.

---

## 4. Redeploy once

After adding the volume and variables, trigger a **Redeploy** (or push a small commit to `main`).  
On startup the server will log:

- `License File: /data/licenses.json`
- `Copier File: /data/copier_subscribers.json`

If you see **`WARNING: Using default paths...`** then the env vars are not set; fix the variable names (no typos) and redeploy.

---

## Summary

| Goal | What to do |
|------|------------|
| Licenses kept on redeploy | Volume at `/data` + `LICENSE_FILE=/data/licenses.json` + `COPIER_SUBSCRIBERS_FILE=/data/copier_subscribers.json` |
| Logo shows | Add `assets/LOGO.png` to repo and push, **or** set `LOGO_PATH=/data/LOGO.png` and put the file on the volume |

Do this once; then every push to `main` updates the app **without** wiping licenses, and the logo will show.
