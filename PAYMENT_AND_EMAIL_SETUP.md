# Payment (Coinbase Commerce) and Email Setup

Step-by-step so checkout works, redirects are correct, and copier invoices email correctly. Do these in order.

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

After paying, Coinbase sends the customer back to your site. The server uses **PUBLIC_BASE_URL** for that (and for copier invoice links).

1. Railway → **Variables**.
2. Add or edit:
   - **Name:** `PUBLIC_BASE_URL`
   - **Value:** your live site URL, e.g. `https://mt5-license-server-production.up.railway.app`  
     (no trailing slash)
3. Save. Redeploy if needed.

---

## 3. Support / contact email (shown on the site)

Set your support email so the website shows it in “Email GOLDMINE” links and in the checkout error message (“Email X for a manual invoice”).

1. Railway → **Variables**.
2. Add or edit:
   - **Name:** `SUPPORT_EMAIL`
   - **Value:** your support email, e.g. `support@yourdomain.com` or `hello@goldmine.com`
3. Save. Redeploy. The main site and setup page will load this via `/api/config` and update all mailto links and the fallback checkout message.

If you don’t set `SUPPORT_EMAIL`, the site falls back to `goldminebotsltd@gmail.com`.

---

## 4. Copier invoice emails (Resend or SMTP)

Used to send **monthly copier invoices** (and “Send Invoice” from the admin panel). Not required for the main checkout; only for sending the invoice email with the payment link.

You can use **either** Resend (recommended, no Gmail) **or** SMTP (Gmail, Mailgun, SendGrid, Outlook, etc.).

### Option A: Resend (recommended – no app passwords)

1. Sign up at [resend.com](https://resend.com) and create an API key.
2. (Optional) Verify your domain in Resend so you can send from e.g. `invoices@goldminetrading.store`. Until then you can use their test address.
3. Railway → **Variables**, add:
   - **Name:** `RESEND_API_KEY`  
   - **Value:** your Resend API key (e.g. `re_...`)
4. (Optional) If you want a specific “From” for invoices:
   - **Name:** `RESEND_FROM_EMAIL`  
   - **Value:** e.g. `GOLDMINE <invoices@yourdomain.com>` or just `invoices@yourdomain.com`  
   If you don’t set this, the server uses `SUPPORT_EMAIL` or a default.
5. Save. Redeploy. Run **npm install** (or ensure `resend` is in `package.json`) so the server can send via Resend.

Invoice emails will be sent with Resend; no Gmail or SMTP needed.

#### Fix "Missing required SPF records" / Enable Sending (Failed)

If Resend shows **Domain Verification: Verified** (DKIM) but **Enable Sending: Failed** with "Missing required SPF records", add these at your **domain DNS host** (where `goldminetrading.store` is managed – e.g. Cloudflare, Namecheap, GoDaddy, Route 53):

1. **MX record** (for `send` subdomain):
   - **Name/host:** `send` (or `send.goldminetrading.store` if the host is the full name)
   - **Value:** copy from Resend (e.g. `feedback-smtp.ap-northeast-1.amazonses.com`)
   - **Priority:** `10`
   - **TTL:** 3600 or Auto

2. **TXT record (SPF)** (for `send` subdomain):
   - **Name/host:** `send`
   - **Value:** `v=spf1 include:amazonses.com ~all`
   - **TTL:** 3600 or Auto

Then in Resend click **Verify** (or wait a few minutes and refresh). DNS can take 5–60 minutes to propagate. If it still fails, double-check the **exact** host name and values in Resend and that there are no typos or extra spaces.

### Option B: SMTP (Gmail, Mailgun, SendGrid, Outlook, etc.)

If you prefer SMTP (e.g. Gmail with an app password, or another provider):

**Gmail**

1. Use a Gmail account. Turn on 2-Step Verification (Google Account → Security).
2. In Security → **2-Step Verification** → **App passwords**, create an app password for “Mail”.
3. In Railway → **Variables**, add:

| Variable         | Value                          |
|------------------|--------------------------------|
| `SMTP_HOST`      | `smtp.gmail.com`               |
| `SMTP_PORT`      | `465`                          |
| `SMTP_SECURE`    | `true`                         |
| `SMTP_USER`      | your Gmail address             |
| `SMTP_PASS`      | the 16-character app password |
| `SMTP_FROM`      | same as SMTP_USER (or desired) |
| `SMTP_FROM_NAME` | `GOLDMINE`                     |

**Other providers (Mailgun, SendGrid, Outlook, etc.)**

- Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE` for that provider.
- Set `SMTP_USER` and `SMTP_PASS` (often an API key or app password).
- Set `SMTP_FROM` and `SMTP_FROM_NAME` as desired.

If **both** Resend and SMTP are configured, the server uses **Resend first**; if Resend is not set, it uses SMTP.

---

## 5. Quick checklist

| What you want           | What to set |
|-------------------------|-------------|
| Checkout link works     | `COINBASE_COMMERCE_API_KEY` (Commerce API key from commerce.coinbase.com) |
| Redirect after payment  | `PUBLIC_BASE_URL` = your live site URL (no trailing slash) |
| Your email on the site  | `SUPPORT_EMAIL` = your support/contact email |
| Invoice emails send     | **Option A:** `RESEND_API_KEY` (and optionally `RESEND_FROM_EMAIL`) **or** **Option B:** `SMTP_USER`, `SMTP_PASS`, and other `SMTP_*` as needed |

After changing variables, let Railway finish redeploying, then test checkout and (if you use copier) one “Send Invoice” from the admin panel.

---

## 6. If checkout still fails

1. **Check the error on the page**  
   The site shows the message returned by the server (e.g. “Coinbase Commerce is not configured”, “Invalid API key”).

2. **Check Railway logs**  
   After clicking “Continue to crypto payment”, look for “Coinbase checkout error” and the line after it.

3. **Verify the key**  
   In Coinbase Commerce, confirm the API key is active and that you’re using the right environment (test vs live).

4. **Manual fallback**  
   The checkout page tells users to email your support address (from `SUPPORT_EMAIL`) for a manual invoice if something is misconfigured.
