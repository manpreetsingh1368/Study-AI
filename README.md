# Study AI

A native Flutter learning workspace with a self-hosted Fastify/TypeScript/SQLite backend. This is an incremental development build. See [PROGRESS.md](PROGRESS.md) for implemented features, verification results and release gaps.

## Ubuntu development

Keep the installed Flutter SDK. This project currently targets Dart 3.14 / Flutter 3.50; its Material widgets are provided by `material_ui` following that SDK's package split.

System dependencies: Node.js 22 or newer, a C++ compiler/build tools for `better-sqlite3`, Flutter Linux dependencies, SQLite, and Linux Secret Service headers/runtime:

```sh
sudo apt install build-essential clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libsqlite3-dev gnome-keyring
flutter pub get
cd server
npm ci
cp .env.example .env
npm run check
npm test
npm run dev
```

If npm 12 reports blocked lifecycle scripts, review and enable the required native build scripts with `npm install-scripts approve argon2 better-sqlite3 esbuild`, then `npm rebuild`. An unlocked Secret Service (for example GNOME Keyring) is required for persistent secure login on Linux. Passwords are never cached by Flutter.

The first server startup applies the initial idempotent migration in `server/migrations/001_initial.sql`, enables foreign keys and WAL, and creates private directories. Do not run migrations against a database without a backup. The initial migration is transactional and recorded in SQLite `user_version`; later schema versions must ship additional ordered migrations.

In another terminal from the project root:

```sh
flutter run -d linux --dart-define=API_URL=http://127.0.0.1:3000
flutter analyze
flutter test
flutter build linux
```

Register an account through the application. To make an existing account an administrator, on the backend host, as the database owner:

```sh
cd server
npm run admin -- your-registered-email@example.com
```

No administrator password is generated or hardcoded. Refresh/sign in again to show Administration. Administrators choose expiration dates for Pro access; this build has no payment processing. Limits are configurable in the backend environment and enforced there. Daily quotas use UTC dates. In-flight and successful generations reserve quota atomically; failed calls release the application quota. Provider-side charges may still apply. After a process crash, pending reservations remain conservative for that UTC day.

## Gemini

Set `GEMINI_API_KEY` and `GEMINI_MODEL` in `server/.env`. Select a currently supported `generateContent` model available to your Google account. There is no default model guess and no client-side API key. Notes and PDFs selected for generation are sent to Google Gemini; review Google's terms/data handling before public deployment.

Implementation follows Google's [generateContent API](https://ai.google.dev/api/generate-content) and [structured output documentation](https://ai.google.dev/gemini-api/docs/structured-output). Requests have a 60-second provider timeout, one retry for server failures, JSON Schema output and Zod validation. Quota errors and malformed responses never produce fabricated fallback materials. PDFs are limited to 10 MiB by default and checked for MIME/signature, not comprehensively scanned or parsed.

## Data, offline use and synchronization

The backend is authoritative. Each account owns its sets, questions, cards, attempts and reviews. The client stores notes/questions/cards and server analytics in local SQLite under the platform application-support directory. Tokens use platform secure storage. Original PDF bytes are not cached offline yet.

Study sets have stable IDs and monotonically increasing versions. Edits/deletes require the version read by the device. Stale writes return 409; refresh, compare and reapply your changes manually. Deleted sets generate permanent tombstones and cannot be resurrected by an old device. Sync is paginated with a per-account cursor and atomic cache/cursor writes. Changes are fetched after login and every 30 seconds while the app is open; the toolbar supports manual sync.

Quiz attempts and flashcard review actions are queued locally with stable operation IDs, then replayed after reconnect. The server recomputes scores and makes replay idempotent. A deleted source discards its now-unapplicable pending operation on 404. Other failures retain the queue and show a sync error. Local scoring is provisional offline. Draft quiz answers persist per study set; timers do not persist through restart. Explicit sign-out clears that account's cache if no queued work remains; pending records remain isolated until the same account signs in again. Expired/revoked credentials clear active local state while keeping any queued records isolated for a later authenticated login. Account deletion clears the server and current cache. Local SQLite content is not encrypted; use operating-system account/disk protection.

Material and learning-history feeds have independent paginated cursors. Cache/cursor writes are atomic. Login and the toolbar trigger sync; an open app retries every 30 seconds after reconnect. Server-side scores always come from saved questions and submitted answers. Local offline scores are marked pending. Attempts and flashcard reviews use stable IDs for idempotent replay. Review state and due dates download to other devices. Due-only study queues use the latest review; a known card's interval doubles up to 180 days, and a card needing review returns the next day.

Each generation creates a separate immutable collection within its study set. Old question IDs remain available for historical answer review. Quiz drafts are stored per collection. Optional timers persist as wall-clock deadlines; immediate explanations and an incorrect-answer filter are supported. Practice exams require Pro and an online start/submission: their deadline is set by the backend, persists across app restarts, and submissions more than ten seconds late score zero. Exam timing is a learning aid, not an anti-cheating certification mechanism.

Sign-out clears private cached data when no work remains. Otherwise the pending work is isolated under its original account and resumes only after that account logs in. Expired/revoked credentials clear active state. Account deletion removes server data and the current device's cache. Other offline devices cannot be remotely wiped; their credentials fail when they reconnect.

The app includes first-run onboarding, saved appearance, folders, desktop PDF drag/drop, a resizable PDF/notes reading panel, and global search with Ctrl/Command+K. Ctrl/Command+N creates a set; quiz answers support keys 1–4, flashcards support Space and arrow keys.

## Recovery codes


## Android, iOS and macOS

```sh
flutter run -d <android-device> --dart-define=API_URL=https://your-domain
flutter build apk --debug --dart-define=API_URL=https://your-domain
flutter build appbundle --release --dart-define=API_URL=https://your-domain
```

Android emulator loopback to the host is `10.0.2.2`, not `127.0.0.1`. Use HTTPS; release manifests do not enable cleartext traffic. Configure signing and replace `com.example.study_ai` identifiers before distribution. Android release signing, store listing/privacy documentation and device QA are not completed here.

iOS/macOS require macOS, Xcode, appropriate signing/provisioning and native validation. Validate iOS Keychain configuration for your final bundle/team identifiers, native picker permissions and HTTPS backend connectivity. macOS uses the platform login Keychain without cross-application sharing. macOS client-network and user-selected-file entitlements are included. Neither Apple platform was built or tested from Ubuntu. No web support is claimed.

## Self-hosted production

A development server on your laptop does not provide worldwide availability. Deploy an always-online server you control with persistent local disk. Use a dedicated unprivileged service account and a supported Node runtime. Copy the application and run `npm ci`. Store secrets in `/etc/study-ai.env` with owner-only permissions; set:

```dotenv
HOST=127.0.0.1
PORT=3000
DATA_DIR=/var/lib/study-ai/data
UPLOAD_DIR=/var/lib/study-ai/uploads
GEMINI_API_KEY=configure-on-server
GEMINI_MODEL=configure-supported-model
```

Create `/var/lib/study-ai` owned by the service account with mode 700. Adapt `server/deploy/study-ai.service` and `server/deploy/Caddyfile` to your host, executable paths and domain. Caddy is an optional open-source TLS reverse proxy, not a required hosted service. Bind the backend to loopback and expose HTTPS at the proxy only. Fastify trusts forwarded IPs only from loopback; never expose a loopback-trusting proxy arrangement to untrusted local tenants. Configure DNS, firewall, TLS renewal, monitoring and a privacy/retention policy. Do not expose the uploads or data directories via static hosting. Only owner-authorized download endpoints serve PDFs.

SQLite is intended for one initial server process on local persistent disk. Do not mount the WAL database on a network filesystem or assume unlimited concurrent writes. Domain changes use prepared statements and short synchronous transactions; Gemini calls run outside transactions. Drizzle maps the normalized tables, with prepared SQL retained for transaction-heavy domain operations. Runtime errors are sanitized and recorded without request bodies, tokens or provider responses. This is not a substitute for a production security audit.

## Backups and restore

`server/src/backup.ts` uses SQLite's online backup API, but the API must be stopped while copying the uploads so files and DB form a consistent snapshot. `server/deploy/backup.sh` is a concrete maintenance-window script to adapt and schedule using a root cron/systemd timer (for example daily at 03:00 UTC). It restarts the API even if backup fails. Nothing is scheduled or installed automatically by this repository. Store backups privately on owner-controlled storage; encrypt off-machine copies and implement retention. Concrete `study-ai-backup.service`/`.timer` units are provided for a daily 03:00 UTC snapshot; copy/adapt them and enable the timer on your host. No host services have been installed or enabled by this development session.

Manual procedure:

1. Stop the service and run `npm run backup -- /private/destination` from `server/` with the same `DATA_DIR`/`UPLOAD_DIR` environment.
2. Confirm both `study.sqlite` and `uploads/` exist; inspect a copy with `sqlite3 study.sqlite 'PRAGMA integrity_check;'`.
3. Restore while the service is stopped: first preserve the current database, WAL/SHM sidecars and upload tree in a separate recovery directory, then copy the snapshot DB into the empty data directory and restore uploads.
4. Restore ownership/mode 700 directories and 600 private files; start the service and verify accounts, authenticated downloads and synchronization.

Never copy an active database file without its WAL or the backup API.

`npm run maintenance` removes expired sessions/recovery codes, releases abandoned generation reservations, removes stale temporary uploads, and purges original PDFs/notes for sets deleted more than `DELETED_FILE_RETENTION_DAYS` (30 by default). Tombstones and historical learning records remain. Adapt the supplied hourly maintenance service/timer to the host; review retention before enabling it. This command intentionally deletes expired private blobs, so use backups and the documented retention setting.

Remaining release requirements include live Gemini acceptance with your credentials, HTTPS deployment, production signing/distribution, native Android/iOS/macOS runtime QA, backup retention/restore drills, operational monitoring and independent security/load/accessibility audits. Neither Apple platform was built on Ubuntu.
