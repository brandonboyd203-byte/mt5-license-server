# 🚀 Deploy to Railway - Step by Step (I'll Guide You!)

## What I Can't Do
❌ I cannot log into Railway for you (needs your account)  
❌ I cannot deploy directly (needs your authorization)

## What I CAN Do
✅ Prepared all files ready for deployment  
✅ Created deployment scripts  
✅ Guide you through every step  

## Let's Deploy Together! 🎯

### Method 1: Using Railway Website (Easiest - 5 minutes)

**Step 1: Create Railway Account**
1. Go to: https://railway.app
2. Click "Start a New Project"
3. Sign up with GitHub (easiest) or email

**Step 2: Create New Project**
1. Click "New Project"
2. Select "Deploy from GitHub repo" (if you have GitHub)
   - OR select "Empty Project" if no GitHub

**Step 3: If Using GitHub:**
```bash
# I'll help you push to GitHub
cd /Users/brandonboyd/Documents/discord-gpt-bot/license-server
git init
git add .
git commit -m "License Server"
# Then create repo on GitHub and push
```

**Step 4: If Using Empty Project:**
- Railway will let you upload files or connect a folder
- Upload the entire `license-server` folder

**Step 5: Set Environment Variable**
1. In Railway project → Click your service
2. Go to "Variables" tab
3. Click "New Variable"
4. Name: `SECRET_KEY`
5. Value: (I'll generate one for you - see below)
6. Click "Add"

**Step 6: Get Your URL**
1. Railway → Settings → Domains
2. Copy the URL: `https://your-project.railway.app`

**DONE!** 🎉

### Method 2: Using Railway CLI (Faster)

Run this command and I'll guide you:

```bash
cd /Users/brandonboyd/Documents/discord-gpt-bot/license-server
./DEPLOY_NOW.sh
```

Or manually:

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login (opens browser)
railway login

# Initialize
railway init

# Set secret key
railway variables set SECRET_KEY=$(openssl rand -hex 32)

# Deploy
railway up

# Get URL
railway domain
```

## Generate Secret Key

Run this to generate a secure key:

```bash
openssl rand -hex 32
```

Copy the output and use it as `SECRET_KEY` in Railway.

## After Deployment

1. **Test Server:**
   ```
   https://your-project.railway.app/health
   ```

2. **Update EAs:**
   - Set `LicenseServerURL = "https://your-project.railway.app"`
   - Set `UseRemoteValidation = true`

3. **Add First License:**
   - Use admin panel (`admin.html`) or API

## Need Help?

Tell me which method you want to use and I'll guide you through each step!

**Recommended:** Method 1 (Railway Website) - easiest for first time
