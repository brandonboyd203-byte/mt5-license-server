# Payment (Coinbase Commerce) and Email Setup

Step-by-step so checkout works and invoices email correctly. Do these in order.

---

## 1. Coinbase Commerce (so “Continue to crypto payment” works)

### Get the API key

1. Go to [Coinbase Commerce](https://commerce.coinbase.com/) and sign in (or create an account).
2. Open **Settings** (gear or profile) → **API keys** (or **Developers**).
3. Click **Create API key**.
4. Give it a name (e.g. “GOLDMINE license server”), leave permissions as **Merchant** (create charges).
5. Copy the key. It looks like a long string (e.g. `a1b2c3d4-...`). You only see it once; store it somewhere safe.

### Common “not accepting” issues

- **Wrong key type**  
  Use a **Commerce** API key from [commerce.coinbase.com](https://commerce.coinbase.com/), not a regular Coinbase or Exchange API key.

- **Test vs live**  
  If you’re in test mode on Commerce, charges won’t take real money. For live: use a live API key and ensure the Commerce account is out of test mode.

- **Key in env**  
  The server only uses the key from the **environment variable**. If it’s missing or wrong, checkout will fail.

### Set it on Railway

1. Railway → your **mt5-license-server** service → **Variables**.
2. Add (or edit):
   - **Name:** `COINBASE_COMMERCE_API_KEY`
   - **Value:** paste the API key (no quotes, no spaces).
3. Save. Railway will redeploy. Wait for the deploy to finish.

### Check it

1. Open your live site → **Checkout**.
2. Fill name, email, choose a plan, click **Continue to crypto payment**.
3. You should be redirected to a Coinbase Commerce payment page.  
   If you see an error message on the page, that message is the reason (e.g. “Coinbase Commerce is not configured” = key not set; “Invalid API key” = wrong key).

---

## 2. Public URL (redirects after payment)

After paying, Coinbase sends the customer back to your site. The server uses your public URL for that.

1. Railway → **Variables**.
2. Add or edit:
   - **Name:** `PUBLIC_BASE_URL`
   - **Value:** your live site URL, e.g. `https://mt5-license-server-production.up.railway.app`  
     (no trailing slash)
3. Save. Redeploy if needed.

---

## 3. Email (Gmail) for copier invoices

Used to send monthly copier invoices (and any “send invoice” from admin). Not required for the main checkout link; only for **sending** the invoice email with the link.

### Gmail App Password (not your normal password)

1. Use a Gmail account (e.g. goldminebotsltd@gmail.com).
2. Turn on 2-Step Verification for that Google account (Google Account → Security).
3. In Google Account → Security → **2-Step Verification** → **App passwords**.
4. Create an app password for “Mail” (or “Other” → name it “GOLDMINE server”).
5. Copy the 16-character password (no spaces).

### Set SMTP on Railway

In Railway → **Variables**, add (replace with your email and app password):

| Variable       | Value                     |
|----------------|---------------------------|
| `SMTP_HOST`    | `smtp.gmail.com`          |
| `SMTP_PORT`    | `465`                     |
| `SMTP_SECURE`  | `true`                    |
| `SMTP_USER`    | `goldminebotsltd@gmail.com` |
| `SMTP_PASS`    | *the 16-char app password* |
| `SMTP_FROM`    | `goldminebotsltd@gmail.com` |
| `SMTP_FROM_NAME` | `GOLDMINE`              |

Save. Redeploy.

### If Gmail blocks or “not accepting”

- Use an **App Password**, not your normal Gmail password.
- “Less secure app access” is no longer used; App Passwords are the correct method.
- If you use a different provider (e.g. Outlook), set `SMTP_HOST`, `SMTP_PORT`, and `SMTP_SECURE` for that provider and keep `SMTP_USER` / `SMTP_PASS` for that account.

---

## 4. Quick checklist

| What you want              | What to set |
|----------------------------|-------------|
| Checkout link works        | `COINBASE_COMMERCE_API_KEY` (Commerce API key from commerce.coinbase.com) |
| Redirect after payment     | `PUBLIC_BASE_URL` = your live site URL |
| Invoice emails send        | `SMTP_USER`, `SMTP_PASS` (Gmail + app password), plus other `SMTP_*` if needed |

After changing variables, always let Railway finish redeploying, then test checkout (and one invoice email if you use copier).

---

## 5. If checkout still fails

1. **Check the error on the page**  
   The site now shows the message returned by the server (e.g. “Coinbase Commerce is not configured”, “Invalid API key”).

2. **Check Railway logs**  
   After clicking “Continue to crypto payment”, look at the service logs for “Coinbase checkout error” and the line after it; that’s the exact reason.

3. **Verify the key**  
   In Coinbase Commerce, confirm the API key is active and that you’re using the right environment (test vs live).

4. **Manual fallback**  
   The checkout page tells users to email goldminebotsltd@gmail.com for a manual invoice if something is misconfigured.
