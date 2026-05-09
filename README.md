# vaultrag

**Chat with your docs. Offline. Forever private.**

On-device RAG for Android: import PDFs, ask questions, get source-cited answers — powered by Gemma 4 via LiteRT-LM and ONNX Runtime Mobile. Zero data leaves the device. Ever.

## Quick Start

1. **Clone & install**
   ```bash
   git clone https://github.com/your-org/vaultrag
   cd vaultrag && npm install
   ```
2. **Configure environment**
   ```bash
   cp .env.example .env
   # Fill in SUPABASE_URL, SUPABASE_ANON_KEY, and LICENSE_SERVER_SECRET
   ```
3. **Apply database schema** (optional SaaS license server only)
   ```bash
   psql $DATABASE_URL < schema.sql
   # Or paste schema.sql into Supabase SQL Editor
   ```
4. **Run the license server locally** (optional)
   ```bash
   npm run dev
   # Deploys Hono dev server on http://localhost:8787
   ```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `SUPABASE_URL` | Yes | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Yes | Supabase anon/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Service role key (server-side only) |
| `LICENSE_SERVER_SECRET` | Yes | HMAC secret for license key signing |
| `GOOGLE_PLAY_PACKAGE_NAME` | Yes | Android package name for Play Billing verification |
| `GOOGLE_PLAY_API_KEY` | Yes | Google Play Developer API key for receipt validation |
| `ENVIRONMENT` | No | `development` or `production` (default: `production`) |

## Deploy Notes

- **Android app**: Build with `npx react-native run-android --variant=release`. Distribute via Google Play or managed APK sideload for Team licenses.
- **License server**: Deploy to Cloudflare Workers free tier via `npm run deploy` (Wrangler). Estimated cost ~$12/mo at scale. The app works fully offline after initial license validation — the server is only hit once post-purchase.
- **Supabase**: Used only for the license server's `waitlist` and `licenses` tables. All document/chat data lives exclusively on-device in SQLite + FAISS-lite.