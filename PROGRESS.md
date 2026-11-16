# Study AI implementation progress

Updated: 2026-11-16. This is an incremental development build, not a production release candidate.

## Implemented

- Existing native Flutter project retained; Material 3 light/dark application, adaptive sidebar/bottom navigation, reusable study components, GoRouter navigation, Riverpod dependency injection.
- Registration/login, Argon2id, hashed expiring bearer sessions, revocation, secure client token storage, profile/password change, account deletion.
- Fastify TypeScript API, SQLite WAL/foreign keys/indexes, initial idempotent SQL migration. Drizzle account queries and typed normalized schemas; other domain operations currently use prepared SQL through the same SQLite connection.
- Saved notes, title editing, deletion tombstones, authenticated private PDF upload/download endpoints, per-user size/storage constraints, PDF MIME/signature checks.
- Real Gemini REST integration with server-only credentials, structured JSON schema, Zod validation, timeout, bounded server-error retry, quota errors. No fallback generated content.
- Server-side atomic plan quota reservation, Free/Pro limits, manual grants/expiry, role-protected admin UI/API, audit records and sanitized application error records.
- Quizzes, answer selection/navigation, optional timer, results/explanations, server scoring, locally persisted draft answers. AI flashcards, flip/swipe/keyboard navigation, known/review decisions, increasing review intervals.
- Real dashboard totals, quiz trends/history, weak-topic analysis.
- Account-isolated local SQLite JSON cache; paginated incremental material sync; periodic reconnect polling; durable quiz/review outbox with stable IDs and idempotent replay. Stale note edits/deletions receive HTTP 409; refresh and manually reapply rather than overwrite another device.
- Backend integration tests and Flutter responsive/auth/offline tests. Verification results are recorded below.

## Verification

- `flutter analyze`: clean.
- `flutter test`: 8 passed, including onboarding/preferences, registration validation, 390/1200px responsive learning flows and real SQLite offline mutation/replay/conflict/merge/deletion/account-isolation tests.
- Backend TypeScript checking: passed.
- Backend tests: 12 passed, covering authentication, revocation/expiry/deletion, isolation/admin permissions, concurrent quota enforcement, entitlements, scoring/review scheduling, PDF validation/privacy, immutable collections, learning deltas, deadlines, recovery codes, generation replay and upgrade from v1.

## Configuration and remaining release work

- Supply backend `GEMINI_API_KEY` and a supported `GEMINI_MODEL`, then perform live-provider acceptance using genuine materials. No production API key was available here.
- Install normal Ubuntu build dependencies (`libsecret-1-dev` etc.) from README. This host used extracted development packages under `/tmp/study-ai-build-deps` and the matching `PKG_CONFIG_PATH`; Flutter was not reinstalled.
- Deploy your always-online backend with TLS, persistent owner-controlled storage, monitoring and a documented privacy/retention policy. A local development server is not worldwide hosting.
- Adapt/install/enable the supplied backup/maintenance systemd units and conduct a host-level disaster-recovery drill. Units were created, not installed into the host.
- Complete Apple-platform builds and Keychain/signing QA on macOS; configure production Android signing and store distribution. The debug APK is not a store release.
- Complete independent security, load and accessibility/native visual audits. PDF structural validation is not antivirus scanning. Local cached content is protected by operating-system access/disk security rather than database encryption.
- Regular quizzes/cards/notes work offline. Practice exams require online start/submission and are learning tools rather than anti-cheating certification.
- There is no permanent demo login, hardcoded administrator password, payment processor or email verification/reset service. Register through the app; recovery uses a code the account owner previously generated and saved.

## Commit policy requested by owner

The owner explicitly requested **one commit per changed line**, including individual deletions and additions, after being informed that intermediate commits may not compile. Only local history is updated; nothing is pushed. Existing commits remain intact. Final content is verified against the pre-commit snapshot and each new commit is checked for exactly one changed line. The final response records the resulting count/range.

## Source inventory

Application, backend, tests, deployment and documentation files created or updated across this development work:

- `.gitignore`
- `PROGRESS.md`
- `README.md`
- `integration_test/learning_flow_test.dart`
- `lib/app/app.dart`
- `lib/core/api/study_controller.dart`
- `lib/core/storage/local_store.dart`
- `lib/features/admin/admin_page.dart`
- `lib/features/auth/auth_screen.dart`
- `lib/features/auth/recovery_screen.dart`
- `lib/features/dashboard/workspace.dart`
- `lib/features/documents/notes_editor.dart`
- `lib/features/documents/pdf_screen.dart`
- `lib/features/documents/set_detail.dart`
- `lib/features/onboarding/onboarding_screen.dart`
- `lib/features/quizzes/study_sessions.dart`
- `lib/features/settings/settings_page.dart`
- `lib/features/sync/conflicts_screen.dart`
- `lib/main.dart`
- `lib/shared/components.dart`
- `pubspec.lock`
- `pubspec.yaml`
- `server/.env.example`
- `server/deploy/Caddyfile`
- `server/deploy/backup.sh`
- `server/deploy/study-ai-backup.service`
- `server/deploy/study-ai-backup.timer`
- `server/deploy/study-ai-maintenance.service`
- `server/deploy/study-ai-maintenance.timer`
- `server/deploy/study-ai.service`
- `server/migrations/001_initial.sql`
- `server/migrations/002_learning_sync.sql`
- `server/migrations/003_recovery_and_generation.sql`
- `server/package-lock.json`
- `server/package.json`
- `server/src/admin.ts`
- `server/src/ai/gemini.ts`
- `server/src/ai/pdf.ts`
- `server/src/ai/pdf_check.mjs`
- `server/src/app.ts`
- `server/src/backup.ts`
- `server/src/database/db.ts`
- `server/src/database/schema.ts`
- `server/src/index.ts`
- `server/src/maintenance.ts`
- `server/src/routes/learning.ts`
- `server/test/app.test.ts`
- `server/test/fixture-server.ts`
- `server/test/gemini.test.ts`
- `server/test/migration.test.ts`
- `server/tsconfig.json`
- `test/offline_sync_test.dart`
- `test/widget_test.dart`

Native setup changes include `linux/CMakeLists.txt`, `android/app/src/main/AndroidManifest.xml`, both macOS entitlement files, and Flutter-generated plugin registrants. Ignored native build caches and artifacts are excluded from commits.

Build outputs: `build/linux/x64/release/bundle/` and `build/app/outputs/flutter-apk/app-debug.apk`.
