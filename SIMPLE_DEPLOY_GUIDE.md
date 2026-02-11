# One simple way to keep the license server stable

You have too many branches and Railway only deploys from one. This gets you to one clear flow.

---

## The only thing that matters

**Railway deploys from one branch.** (Usually `main`.)  
Whatever is on **that** branch is what’s live. Other branches don’t affect the site.

So: **one branch = source of truth.** Everything you want live should be on that branch.

---

## Get to stable in 3 steps (do this once)

### Step 1: Decide your “live” branch

Pick one:

- **Option A – Use `main` (recommended)**  
  You’ll put all good work on `main` and push `main`. Railway keeps deploying from `main`.

- **Option B – Use your current branch**  
  In Railway: Service → Settings (or Source) → set **Branch** to `cursor/bot-and-copy-trading-platform-10da` (or whatever your branch is). From now on you only push that branch and Railway deploys it.

Stick with one. Most people use **main**.

### Step 2: Put everything on that branch

If you chose **main** and your latest work is on `cursor/bot-and...`:

1. Open Terminal in your **license-server** (or **mt5-license-server**) folder.
2. Run:

```bash
git checkout main
git pull origin main
git merge cursor/bot-and-copy-trading-platform-10da
git push origin main
```

(Use your real branch name if it’s different. Type `git branch` to see it.)

That copies all your work (logo, index, volumes, etc.) onto `main`. Railway will deploy from `main`.

### Step 3: From now on, only use that branch

- Make changes in your editor.
- Commit.
- Push **that one branch** (e.g. `git push origin main`).

No more “which branch?” — you always work on and push the same branch Railway uses.

---

## What was going wrong (short version)

- You had **main** (old) and **cursor/bot-and...** (new).
- You pushed to **cursor/bot-and...**, so GitHub said “up to date” for that branch.
- Railway was still building from **main**, so the site showed old content.
- Merging **cursor/bot-and...** into **main** and pushing **main** fixed it, because then the “live” branch had the new stuff.

---

## Quick reference

| I want to…              | Do this |
|-------------------------|--------|
| Update the live site    | Push to the branch Railway deploys from (usually `main`). |
| See what’s live         | Look at that branch on GitHub (e.g. `main`). |
| Stop going “backwards”  | Don’t push to a different branch; always push to the deploy branch. |
| Change logo / index     | Edit files, commit, push to the deploy branch. Wait for Railway to finish deploying. |

---

## If you’re still stuck

1. In **Railway** → your mt5-license-server service → **Settings** (or where the repo is connected).  
   Note the **Branch** it says (e.g. `main`).

2. In **Terminal**:  
   `git branch`  
   See which branch you’re on. If it’s not the Railway branch, run the merge steps above once so that branch has everything, then from now on always push that branch.

One branch, one push, one deploy. That’s the flow.
