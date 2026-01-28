# MT5 License Server

Remote license validation server for BigBeluga and Advanced Scalper EAs.

## Quick Deploy to Railway

1. Push this repo to GitHub
2. Connect to Railway
3. Set `SECRET_KEY` environment variable
4. (Optional) Set `COINBASE_COMMERCE_API_KEY` for crypto checkout
5. Get your server URL
6. Update EAs with the URL

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

## License

Private - For authorized use only.
