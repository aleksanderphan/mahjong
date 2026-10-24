# 🀄 Mahjong SG Tracker (Flutter)

Score tracker for a 4-player Singapore / SEA mahjong table. Flutter app for **Android** and **Web**, with a shared live database on **Supabase** (free tier). The original JavaScript / Firebase app is kept in [legacy_web/](legacy_web/) for reference.

## What is in this version

| Area | Status |
|---|---|
| Scoring engine, Tai catalogue, house rules, dealer / 连庄 tracking | ✅ ported 1:1 from the web app ([lib/core/](lib/core/)), covered by tests |
| New game (4 players, starting score, scorekeeper), **continue a closed table** | ✅ |
| Game table: dealer, seat winds, scores, zero-sum check, live updates for everyone | ✅ |
| Record win (self-draw / discard / pay-all, Quick · Limit · Tai-only picker), edit past round | ✅ |
| Instant payouts, draw, manual adjust (zero-sum, reason), undo, audit log (void / restore) | ✅ |
| Recap, share (WhatsApp / Teams / text / CSV), host corrects who discarded | ✅ |
| Ranking: all players or one table of 4, by period and metric | ✅ |
| Players directory, score calculator, rules guide, house-rules editor | ✅ |
| Host control (host-only writes, PIN take-over), app password | ✅ enforced by Supabase RLS |
| Backup / import (reads the old web app's JSON export) | ✅ |
| 📷 AI hand scan | ✅ camera/gallery → Supabase Edge Function [scan-hand](supabase/functions/scan-hand/index.ts) → Gemini (key stays server-side) |
| 🔔 Notifications | ✅ in-app list + Android phone alerts for house-rule changes, game start / finish, new host — while the app is running |
| **Not yet ported** | winning-hand simulator, "🙋 I won!" player requests and lobby/QR, named rule sets, tile picture guide, on-device ONNX tile detector |

## Setup

1. **Supabase project** (supabase.com, free plan)
   - SQL Editor → run [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql).
   - Authentication → Providers → enable **Anonymous sign-ins**.
   - Set the shared app password (replaces the Firestore `config/access` doc):
     `insert into app_config(key, value) values ('access_password', 'your password');`
   - **AI hand scan** (optional): `supabase secrets set GEMINI_API_KEY=<key from aistudio.google.com>` then `supabase functions deploy scan-hand`.
2. **Keys**: copy `env.example.json` to `env.json` (git-ignored) and fill in the project URL and the publishable (anon) key.
3. **Run**
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=env.json            # connected Android device / emulator
   flutter run -d chrome --dart-define-from-file=env.json  # web
   flutter test
   ```
   Without `env.json` the app runs in **demo mode** (data stays on the device).
4. **Build**
   ```bash
   flutter build apk --release --dart-define-from-file=env.json
   flutter build web --release --dart-define-from-file=env.json   # host build/web anywhere static (GitHub Pages, Netlify, Supabase storage…)
   ```

## Hosting

The web build is static. [.github/workflows/web.yml](.github/workflows/web.yml) builds it and publishes to **GitHub Pages** on every push to `main` (Settings → Pages → Source: *GitHub Actions*; add repo secrets `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`). Supabase Storage cannot host it (it serves HTML as plain text), so Pages / Netlify / Cloudflare Pages are the options.

## Notifications — what is and isn't possible

Supabase has no push service. Alerts are driven by Realtime and shown while the app is open or backgrounded. Alerts when the app is fully closed need FCM (Android) or Web Push, which is a separate piece of work.

## Moving your existing data from Firebase

In the old web app: **More → Backup → Download / copy JSON**. In the new app: **More → Backup & import → paste → Import**. Games, rounds and players keep their ids; games that already exist are skipped. The importing phone becomes host of the imported games.

## Security model (was `firestore.rules`)

- All tables use row-level security and require the app password (`unlock_app()` RPC) before anything is readable.
- Only a game's host can add events or change the game; the host column moves only through `give_host()` / `claim_host()`.
- `events` is append-only: a CHECK constraint forces 4 integer deltas that sum to 0, and only `voided` / `void_reason` / `voided_at` can be updated; there is no delete.
- The host PIN lives in `room_secrets`, which no API role can read.

## Layout

```
lib/core/   pure Dart rules (scoring, rules, hand, stats, recap, continuation) — no Flutter imports
lib/data/   Repository interface, SupabaseRepository, LocalRepository (demo)
lib/ui/     screens
supabase/   SQL migration
test/       unit + widget tests
legacy_web/ previous JS / Firebase implementation
```
