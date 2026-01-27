# Deploy License Server to Railway

## 🚀 Quick Deployment Steps

### Method 1: Deploy from GitHub (Recommended)

1. **Push to GitHub:**
   ```bash
   cd license-server
   git init
   git add .
   git commit -m "Initial commit - License Server"
   git remote add origin https://github.com/yourusername/mt5-license-server.git
   git push -u origin main
   ```

2. **Deploy on Railway:**
   - Go to https://railway.app
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Choose your repository
   - Railway auto-detects Node.js and deploys!

3. **Set Environment Variables:**
   - In Railway project, go to "Variables"
   - Add: `SECRET_KEY` = (generate a random string)
   - `PORT` is set automatically by Railway

4. **Get Your Server URL:**
   - Go to "Settings" → "Domains"
   - Railway provides: `https://your-project.railway.app`
   - Copy this URL!

### Method 2: Direct Upload (No GitHub)

1. **Create Railway Project:**
   - Go to https://railway.app
   - Click "New Project"
   - Select "Empty Project"

2. **Upload Files:**
   - Click "Add Service" → "GitHub Repo" OR "Empty Service"
   - If empty, you can upload files via Railway CLI or connect a folder

3. **Or Use Railway CLI:**
   ```bash
   # Install Railway CLI
   npm install -g @railway/cli
   
   # Login
   railway login
   
   # Initialize project
   cd license-server
   railway init
   
   # Deploy
   railway up
   ```

### Method 3: Deploy from Local Folder

1. **Install Railway CLI:**
   ```bash
   npm install -g @railway/cli
   ```

2. **Login:**
   ```bash
   railway login
   ```

3. **Deploy:**
   ```bash
   cd license-server
   railway init
   railway up
   ```

## ⚙️ Configuration

### Environment Variables

In Railway dashboard → Variables, set:

- `SECRET_KEY` = Your secret key (generate random string)
- `PORT` = (Railway sets this automatically, don't change)

### Generate Secret Key

```bash
# On Mac/Linux:
openssl rand -hex 32

# Or use online generator:
# https://randomkeygen.com/
```

## 🔗 Get Your Server URL

1. In Railway project, go to **Settings**
2. Click **Domains**
3. Railway provides: `https://your-project.railway.app`
4. **Copy this URL** - you'll need it for the EAs!

## ✅ Verify Deployment

1. **Check Health:**
   ```
   https://your-project.railway.app/health
   ```
   Should return: `{"status":"online","timestamp":"..."}`

2. **Test License Validation:**
   ```bash
   curl -X POST https://your-project.railway.app/validate \
     -H "Content-Type: application/json" \
     -d '{
       "accountNumber": "123456",
       "broker": "Test",
       "eaName": "BigBeluga"
     }'
   ```

## 📝 Next Steps

1. **Update EAs:**
   - Set `LicenseServerURL = "https://your-project.railway.app"`
   - Set `UseRemoteValidation = true`

2. **Add Licenses:**
   - Use admin panel or API to add licenses

3. **Monitor:**
   - Check Railway logs for validation requests
   - Monitor usage in Railway dashboard

## 💰 Railway Pricing

- **Free Tier:** $5/month credit (usually enough for small scale)
- **Hobby Plan:** $5/month (if you exceed free tier)
- **Pro Plan:** $20/month (for higher traffic)

## 🔒 Security Notes

1. **Keep SECRET_KEY secret** - don't commit it to GitHub
2. **Use HTTPS** - Railway provides this automatically
3. **Monitor logs** - check for suspicious activity
4. **Backup licenses.json** - Railway persists files, but backup regularly

## 🐛 Troubleshooting

### Server Not Starting
- Check Railway logs for errors
- Verify `package.json` has correct start script
- Check environment variables are set

### 404 Errors
- Verify URL is correct (include https://)
- Check Railway domain is active
- Verify service is deployed

### License Validation Fails
- Check server logs in Railway
- Verify license exists in server
- Check account number matches exactly

## 📊 Monitoring

Railway provides:
- **Logs:** Real-time server logs
- **Metrics:** CPU, Memory, Network usage
- **Deployments:** Deployment history

Check these regularly to monitor your license server!
