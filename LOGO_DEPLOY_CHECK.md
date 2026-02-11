# Logo still not showing – checklist

## "GitHub says it's all up to date" – what that means

**"All up to date"** usually means: you're on branch **cursor/bot-and...** and you pushed that branch. So **that branch** is up to date with GitHub. But **Railway is almost certainly deploying from `main`**, not from your branch. So Railway never gets your logo changes until they're on **main**.

**Fix: get your changes onto `main` and push `main`.** Run these in the **license-server** folder (or your repo root):

```bash
# 1. Make sure your logo branch has everything committed
git status

# 2. Switch to main and pull (in case someone else updated it)
git checkout main
git pull origin main

# 3. Merge your branch (replace with your actual branch name if different)
git merge cursor/bot-and-copy-trading-platform-10da

# 4. Push main – this triggers Railway to deploy
git push origin main
```

If your branch has a different name, run `git branch` to see it, then use that name in the `git merge` line. After `git push origin main`, Railway will deploy from **main** and the logo code will be included.

---

## 1. Is Railway deploying the branch you pushed?

Your screenshot showed branch **cursor/bot-and...**. Railway usually deploys from **main** (or **master**).

- If you only pushed to **cursor/bot-and...**, Railway will not have the logo changes.
- **Fix:** Merge into **main** and push **main**, or change Railway to deploy from **cursor/bot-and...**.

**Check in Railway:** Project → your service → **Settings** (or the service source). Look for **Branch** or **Source**. That branch is what gets deployed.

**Then either:**
- Push your logo changes to that branch (e.g. merge and push `main`), or  
- Change the deploy branch to the one you’re using.

## 2. Trigger a new deploy

After the correct branch has the latest code:

- **Option A:** Push an empty commit to that branch:  
  `git commit --allow-empty -m "Trigger redeploy for logo"`  
  then `git push origin main` (or whatever branch Railway uses).
- **Option B:** In Railway, open the latest deployment and use **Redeploy** (if shown).

## 3. Test the logo URL

After a deploy finishes, open in a new tab:

**https://mt5-license-server-production.up.railway.app/logo**

- If you see the logo image → server is fine; do a **hard refresh** on the main page (Ctrl+Shift+R or Cmd+Shift+R).
- If you get 404 → the branch Railway builds from doesn’t have the new `server.js` or `assets/LOGO.png`.

## 4. Confirm these are in the repo

On the branch Railway deploys from, make sure you have:

- `server.js` – with `getLogoPath()` and `app.get('/logo', ...)`
- `index.html` – with `src="/logo?v=4"`
- `assets/LOGO.png` – the image file (must be committed, not ignored)
