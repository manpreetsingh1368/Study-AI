# Study AI

A native Flutter learning workspace with a self-hosted Fastify/TypeScript/SQLite backend. This is an incremental development build. See [PROGRESS.md](PROGRESS.md) for implemented features, verification results and release gaps.

## Ubuntu development

Keep the installed Flutter SDK. This project currently targets Dart 3.14 / Flutter 3.50; its Material widgets are provided by `material_ui` following that SDK's package split.

System dependencies: Node.js 22 or newer, a C++ compiler/build tools for `better-sqlite3`, Flutter Linux dependencies, SQLite, and Linux Secret Service headers/runtime:

```sh
sudo apt install build-essential clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libsqlite3-dev gnome-keyring poppler-utils
flutter pub get
cd server
npm ci
cp .env.example .env
npm run check
npm test
npm run dev
```

If npm 12 reports blocked lifecycle scripts, review and enable the required native build scripts with `npm install-scripts approve argon2 better-sqlite3 esbuild`, then `npm rebuild`. An unlocked Secret Service (for example GNOME Keyring) is required for persistent secure login on Linux. Passwords are never cached by Flutter.

Startup applies the four ordered transactional migrations in `server/migrations/`, records their version in SQLite `user_version`, and enables foreign keys and WAL. Upgrades preserve existing accounts, questions and attempts, backfill collections and publish new sync snapshots. Back up an existing database before upgrading. Use the same Node runtime for `npm ci` and the service because SQLite has a native binding.

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

No administrator password is generated or hardcoded. Refresh/sign in again to show Administration. Administrators choose activation and expiration dates for Pro access; this build has no payment processing. Limits are configurable in the backend environment and enforced there. Daily quotas use UTC dates. In-flight and successful generations reserve quota atomically; failed calls release the application quota. Provider-side charges may still apply. Generation operation IDs make retrying a lost response idempotent. Maintenance releases abandoned reservations older than ten minutes; it does not reverse any provider-side charges.

## Gemini

Set `GEMINI_API_KEY` and `GEMINI_MODEL` in `server/.env`. Select a currently supported `generateContent` model available to your Google account. There is no default model guess and no client-side API key. Notes and PDFs selected for generation are sent to Google Gemini; review Google's terms/data handling before public deployment.

Implementation follows Google's [generateContent API](https://ai.google.dev/api/generate-content) and [structured output documentation](https://ai.google.dev/gemini-api/docs/structured-output). Requests have a 60-second provider timeout, one retry for server failures, JSON Schema output and Zod validation. Quota errors and malformed responses never produce fabricated fallback materials. PDFs are limited to 10 MiB and 1,000 pages by default. MIME/signature checks are followed by isolated structural parsing with an eight-second timeout and 128 MiB JavaScript heap limit. Encrypted, malformed or over-complex documents are rejected. This is validation, not antivirus scanning.

## Data, offline use and synchronization

The backend is authoritative. Notes, PDFs, learning collections, attempt details and review records are cached per account in local SQLite. Opening a PDF or selecting **Keep offline** saves its bytes locally. Tokens use platform secure storage. Local SQLite is not encrypted; protect the operating-system account and disk.

Creating, editing and deleting study sets works offline. Local changes and their stable operation IDs are saved atomically before any network call. The backend checks record versions and stores operation receipts in the same transaction as the mutation, so a dropped HTTP response can be retried without duplicating work. PDFs also have a durable upload queue and stable document IDs. Edits to folders synchronize with the study set.

Conflicting or rejected material edits preserve the latest local copy in **Sync conflicts**. Compare it with the current server version, keep the server version, save local notes as a separate set, or merge them manually. The merged save still checks the server version, so another concurrent edit is never blindly overwritten. Deletion tombstones remain permanently and old devices cannot resurrect a set. Rejected uploads can be retried against the latest version, saved to disk, or discarded. Rejected study-progress operations remain available for retry or explicit discard rather than blocking unrelated changes.

Material and learning-history feeds have independent paginated cursors. Cache/cursor writes are atomic. Login and the toolbar trigger sync; an open app retries every 30 seconds after reconnect. Server-side scores always come from saved questions and submitted answers. Local offline scores are marked pending. Attempts and flashcard reviews use stable IDs for idempotent replay. Review state and due dates download to other devices. Due-only study queues use the latest review; a known card's interval doubles up to 180 days, and a card needing review returns the next day.

Each generation creates a separate immutable collection within its study set. Old question IDs remain available for historical answer review. Quiz drafts are stored per collection. Optional timers persist as wall-clock deadlines; immediate explanations and an incorrect-answer filter are supported. Practice exams require Pro and an online start/submission: their deadline is set by the backend, persists across app restarts, and submissions more than ten seconds late score zero. Exam timing is a learning aid, not an anti-cheating certification mechanism.

Sign-out clears private cached data when no work remains. Otherwise the pending work is isolated under its original account and resumes only after that account logs in. Expired/revoked credentials clear active state. Account deletion removes server data and the current device's cache. Other offline devices cannot be remotely wiped; their credentials fail when they reconnect.

The app includes first-run onboarding, saved appearance, folders, desktop PDF drag/drop, a resizable PDF/notes reading panel, and global search with Ctrl/Command+K. Ctrl/Command+N creates a set; quiz answers support keys 1–4, flashcards support Space and arrow keys.

## Notebook workspace and Studio

Open a library notebook to work in **Sources / Chat / Studio**. Desktop uses three panels; mobile uses focused tabs with less navigation chrome. The library now presents notebook cards with collection/note counts and recent updates.

- Check up to 50 saved materials as sources. Add another text source or PDF directly from the source panel, or open a source to read its notes/PDF.
- Ask a question in Chat; Ctrl/Command+Enter sends it. Answers carry clickable source excerpts. PDF references open at their cited page when the original document is still available. Changed sources are clearly identified as older snapshots.
- Studio generates source overviews, structured study guides and FAQs. Each request uses **one** unit of the existing Free/Pro AI allowance, just like a quiz generation. No additional paid provider is involved.
- Save an answer to Studio notes, write a personal note, copy an answer, export reports/notes as Markdown, and reopen older conversations. Notes queue safely offline; saved answers/reports remain available from the local cache.
- Quizzes, flashcards and exams remain available under **Study tools** and the Studio collection list.

The backend extracts PDF text using the open-source `pdftotext` command from `poppler-utils` (`PDFTOTEXT_BIN` may specify an alternate executable). Source extraction has a timeout/output bound; selected text is limited to 100,000 characters in total. Oversized selections are rejected explicitly. Scanned PDFs without selectable text require pasted notes or a transcript.

Only checked source material and prior conversation turns confined to those same sources are sent for notebook requests. Responses use structured JSON. Every citation must reference a supplied chunk and contain a quotation found in that chunk after whitespace/Unicode normalization. Unsupported citations are rejected and failed application quota reservations are released. A verified quotation proves the excerpt exists, not that every AI interpretation is correct: inspect sources for important claims. Insufficient-evidence responses are shown explicitly.

The most recent 80 responses are cached per notebook, with an earlier-response loader for history; up to 50 saved notes are supported per notebook. Deleting a source does not automatically remove excerpts already saved into a different notebook. Account deletion still removes all owned records. Retention maintenance purges content belonging to deleted notebooks while preserving sync tombstones.

Live Gemini notebook output remains an acceptance requirement when you configure your server key/model. Tests use dependency-injected fixtures confined to `server/test`, never a production fallback. Native acceptance also checks chat citations, saved notes, cross-device downloads and offline note capture. Optional `SCREENSHOT_DIR` on the native test writes desktop light/dark and mobile render captures.

## Recovery codes

While signed in, enter your current password in Settings and choose **Create a one-time recovery code**. Store it privately; generating another invalidates the old code. Only its SHA-256 digest is retained on the server. The 256-bit code expires after one year and can reset the password once through **Use a recovery code** on the login screen. Resetting the password consumes the code and revokes all sessions. Changing the password also invalidates recovery codes and outstanding email-reset links. Password registration does not verify email ownership; verified provider email is required for Google/Apple sign-in. Email reset delivery is available with the SMTP configuration below.

## Verification

```sh
flutter analyze
flutter test
cd server
npm run check
npm test
npm audit --omit=dev
```

A native Linux acceptance test starts an isolated Fastify fixture server, uses real HTTP and SQLite, renders a real PDF, completes a quiz and a flashcard review, verifies a second client's downloads and offline cache, and creates/reads/revokes a public snapshot through the sharing UI. Its generated content and secure-storage mock are confined to tests; it does not call Gemini or change your login keyring:

```sh
# From the project root. NODE_BINARY must match the Node used for npm ci.
xvfb-run -a flutter test integration_test/learning_flow_test.dart -d linux \
  --dart-define=PROJECT_ROOT="$PWD" \
  --dart-define=NODE_BINARY="$(command -v node)"
```

If a Swiftly clang shim shadows the system compiler, run Flutter commands with a PATH that resolves `/usr/bin/clang` first. Do not change or reinstall Flutter. On this host, missing libsecret development packages were extracted under `/tmp/study-ai-build-deps`; normal installations should install `libsecret-1-dev` using the dependency instructions above.

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

`npm run maintenance` removes expired sessions/recovery codes, password-reset tokens, OAuth flows and share links, releases abandoned generation reservations, removes stale temporary uploads, and purges original PDFs/notes for sets deleted more than `DELETED_FILE_RETENTION_DAYS` (30 by default). Tombstones and historical learning records remain. Adapt the supplied hourly maintenance service/timer to the host; review retention before enabling it. This command intentionally deletes expired private blobs, so use backups and the documented retention setting.

Remaining release requirements include live Gemini acceptance with your credentials, HTTPS deployment, production signing/distribution, native Android/iOS/macOS runtime QA, backup retention/restore drills, operational monitoring and independent security/load/accessibility audits. Neither Apple platform was built on Ubuntu.

## Email recovery, Google and Apple sign-in

Set `PUBLIC_BASE_URL` to the backend's public HTTPS origin (for example `https://study.example.com`), then restart the server. A localhost URL works only on the same computer; it cannot make shared links accessible worldwide. The server and its TLS proxy must be reachable from the recipients' browsers.

- **Forgot password:** configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, and optional `SMTP_USER`/`SMTP_PASSWORD`. Port 587 uses required STARTTLS; set `SMTP_SECURE=true` for an implicit TLS connection, usually port 465. Use a trusted TLS certificate. The UI explicitly reports missing SMTP configuration. Known and unknown emails receive the same response. Reset links expire in 20 minutes, work once, and revoke all sessions and recovery codes. Delivery jobs run in memory and drain on graceful shutdown; after an abrupt server crash, request another email. Delivery errors are recorded as `RESET_DELIVERY_FAILED` without tokens or addresses.
- **Google:** create a web OAuth client in your Google Cloud project. Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`. Register the exact redirect URI `https://study.example.com/auth/oauth/google/callback` and configure the consent screen/test users or production verification as required by Google.
- **Apple:** configure Sign in with Apple for a Services ID, register your domain and exact return URL `https://study.example.com/auth/oauth/apple/callback`, and set `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY_PATH` to your private `.p8` signing key. This requires your own Apple developer configuration and HTTPS. Keep the key outside the repository with private filesystem permissions. Apple ID sign-in supports iCloud accounts and Hide My Email; it does not access iCloud files.

Provider buttons become available only when their server settings exist. Browser authorization uses code exchange, state, nonce, browser cookies, PKCE for Google, signed ID-token verification and a separate client proof for one-time session collection. Study AI still issues and stores its own sessions. Matching email addresses never silently merge accounts: sign in to the existing account first and connect a provider in **Settings → Connected accounts**. Password accounts must confirm their current password; provider-only accounts need a sign-in within five minutes to connect another provider or delete the account. A provider-only account may set a password using the email-reset flow.

Real Google/Apple credentials and an SMTP server are required for live end-to-end verification. Automated tests use injected delivery/provider adapters and independently test signed-token validation; they do not send real mail or sign into external accounts.

## Notebook capacity and public sharing

Each root notebook supports 50 attached sources, 50 saved Studio notes, and 2 GiB of PDFs across itself and its attached sources. The primary notebook material is separate from the attached-source counter. AI requests can select up to 50 materials, with an existing 100,000-character extraction bound. Free/Pro notebook-count limits still apply to root notebooks; attaching sources does not consume another notebook slot. The default account-wide PDF budget is 20 GiB (`MAX_STORAGE_BYTES`). Existing material is retained during migration; notebooks above a new limit must remove material before adding more.

PDF selection and uploads stream to durable private files instead of buffering an entire notebook. `MAX_PDF_BYTES` defaults to 100 MiB per file, and the supplied Caddy configuration permits 110 MB request bodies. Adapt any other reverse proxy or hosting upload/time limits accordingly. Individual documents may still be loaded in memory for viewing. For quiz generation, PDFs above 15 MiB use bounded extracted text; scanned documents need selectable text or pasted notes.

Choose the share icon in a notebook, explicitly select source notes, saved notes and/or responses, and create a link. Anyone with that link can read the immutable snapshot without an account. Original PDFs, unrelated source content and account details are excluded. Links expire after 1–90 days (seven by default) and can be revoked in the sharing panel. Revocation stops future access; it cannot remove a recipient's saved copy. Links use random 256-bit secrets; only hashes persist on the server, while the originating device keeps the URL in secure storage for copying again. Other devices can list/revoke the link but cannot recover its secret URL. At most 20 active links are allowed per notebook. Deleting the notebook makes its links unavailable.
