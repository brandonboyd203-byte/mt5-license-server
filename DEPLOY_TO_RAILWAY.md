# 🚂 Deploy License Server to Railway - Step by Step

## Prerequisites
- Railway account (free at https://railway.app)
- GitHub account (optional, but recommended)

## Method 1: Deploy from GitHub (Easiest)

### Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Create new repository: `mt5-license-server`
3. **Don't initialize with README** (we already have files)

### Step 2: Push Code to GitHub

```bash
cd /Users/brandonboyd/Documents/discord-gpt-bot/license-server

# Initialize git (if not already)
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit - License Server for MT5 EAs"

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/mt5-license-server.git

# Push
git branch -M main
git push -u origin main
```

### Step 3: Deploy on Railway

1. **Go to Railway:**
   - Visit https://railway.app
   - Sign up/Login (free)

2. **Create New Project:**
   - Click **"New Project"**
   - Select **"Deploy from GitHub repo"**
   - Authorize Railway to access GitHub
   - Select your `mt5-license-server` repository
   - Click **"Deploy Now"**

3. **Railway Auto-Deploys:**
   - Railway detects Node.js automatically
   - Installs dependencies (`npm install`)
   - Starts server (`node server.js`)
   - Takes 1-2 minutes

### Step 4: Configure Environment Variables

1. In Railway project, click on your service
2. Go to **"Variables"** tab
3. Click **"New Variable"**
4. Add:
   - **Name:** `SECRET_KEY`
   - **Value:** (generate a random string - see below)
5. Click **"Add"**

**Generate Secret Key:**
```bash
# In terminal:
openssl rand -hex 32
```

Or use: https://randomkeygen.com/

**Note:** `PORT` is automatically set by Railway - don't add it!

### Step 5: Get Your Server URL

1. In Railway project, go to **"Settings"**
2. Scroll to **"Domains"** section
3. Railway provides: `https://your-project-name.railway.app`
4. **Copy this URL!** You'll need it for the EAs.

### Step 6: Verify It Works

Open in browser:
```
https://your-project-name.railway.app/health
```

Should see:
```json
{"status":"online","timestamp":"2024-01-01T00:00:00.000Z"}
```

## Method 2: Deploy Using Railway CLI (Alternative)

### Step 1: Install Railway CLI

```bash
npm install -g @railway/cli
```

### Step 2: Login

```bash
railway login
```
Opens browser to authenticate.

### Step 3: Initialize Project

```bash
cd /Users/brandonboyd/Documents/discord-gpt-bot/license-server
railway init
```

### Step 4: Set Environment Variables

```bash
railway variables set SECRET_KEY=your-secret-key-here
```

### Step 5: Deploy

```bash
railway up
```

### Step 6: Get URL

```bash
railway domain
```

## ✅ After Deployment

### 1. Update Your EAs

In both `BigBeluga_EA.mq5` and `Advanced_Scalper_EA.mq5`:

Set the input:
```
LicenseServerURL = "https://your-project-name.railway.app"
UseRemoteValidation = true
```

### 2. Add First License

**Option A: Using Admin Panel**
1. Open `admin.html` in browser
2. Enter your Railway URL when prompted
3. Add license

**Option B: Using API**
```bash
curl -X POST https://your-project-name.railway.app/admin/licenses \
  -H "Content-Type: application/json" \
  -d '{
    "accountNumber": "123456",
    "userName": "Test User",
    "eaName": "BigBeluga"
  }'
```

### 3. Test in MT5

1. **Allow WebRequest:**
   - MT5 → Tools → Options → Expert Advisors
   - Check "Allow WebRequest for listed URL"
   - Add: `https://your-project-name.railway.app`

2. **Attach EA:**
   - Set `LicenseServerURL` to your Railway URL
   - Set `UseRemoteValidation = true`
   - Attach to chart
   - Check logs for "REMOTE LICENSE VALIDATION: SUCCESS"

## 📊 Monitoring

### View Logs
- Railway dashboard → Your service → **"Deployments"** → Click deployment → **"View Logs"**

### View Metrics
- Railway dashboard → Your service → **"Metrics"**
- See CPU, Memory, Network usage

### View Variables
- Railway dashboard → Your service → **"Variables"**
- See all environment variables

## 🔒 Security Checklist

- ✅ `SECRET_KEY` is set and secret
- ✅ Server URL is HTTPS (Railway provides this)
- ✅ Licenses are stored securely
- ✅ Admin endpoints should have authentication (add later)

## 💰 Railway Pricing

- **Free Tier:** $5/month credit (usually enough)
- **Hobby:** $5/month if you exceed free tier
- **Pro:** $20/month for higher traffic

**For license server, free tier is usually enough!**

## 🐛 Troubleshooting

### "Service failed to start"
- Check Railway logs
- Verify `package.json` has `"start": "node server.js"`
- Check environment variables are set

### "Cannot connect to server"
- Verify URL is correct (include `https://`)
- Check Railway service is running (green status)
- Check domain is active in Railway settings

### "404 Not Found"
- Verify URL includes `/validate` endpoint
- Check server is deployed and running
- Check Railway logs for errors

## 📝 Next Steps

1. ✅ Server deployed to Railway
2. ✅ URL copied
3. ⏭️ Update EAs with server URL
4. ⏭️ Add licenses via admin panel
5. ⏭️ Test in MT5
6. ⏭️ Distribute EAs to customers

**Your license server is now live on Railway! 🎉**
