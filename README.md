# MT5 License Server

Remote license validation server for BigBeluga and Advanced Scalper EAs.

## Quick Deploy to Railway

1. Push this repo to GitHub
2. Connect to Railway
3. Set `SECRET_KEY` environment variable
4. (Optional) Set `COINBASE_COMMERCE_API_KEY` for crypto checkout
5. (Optional) Set Gmail SMTP env vars for auto invoices
6. Get your server URL
7. Update EAs with the URL

See `DEPLOY_TO_RAILWAY.md` for detailed instructions.

## Features

- Remote license validation
- Account-based locking
- Broker restrictions
- Time-limited licenses
- Admin API for license management
- Web admin panel

## API Endpoints

- `POST /validate` - Validate license
- `GET /admin/licenses` - List all licenses
- `POST /admin/licenses` - Add new license
- `DELETE /admin/licenses/:id` - Deactivate license
- `GET /admin/stats` - Get statistics
- `POST /api/coinbase/charge` - Create Coinbase Commerce checkout
- `GET /admin/copier-subscribers` - List copier subscribers
- `POST /admin/copier-subscribers` - Add copier subscriber
- `DELETE /admin/copier-subscribers/:id` - Deactivate subscriber
- `POST /admin/copier-subscribers/:id/invoice` - Send invoice now

## Auto Invoices (Gmail SMTP)

To automatically email monthly copier invoices, set:

- `SMTP_USER` (your Gmail address)
- `SMTP_PASS` (Gmail app password)
- `SMTP_FROM` (sender address, usually same as SMTP_USER)
- `COINBASE_COMMERCE_API_KEY` (required to create payment links)

The invoice schedule is controlled by:

- `INVOICE_CRON` (default: `0 9 1 * *` = 9am UTC on the 1st)
- `INVOICE_TIMEZONE` (default: `UTC`)

Copier subscribers can be managed via `/admin/copier-subscribers` on the admin panel.

## License

Private - For authorized use only.
