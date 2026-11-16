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

- `flutter analyze`: passed, no issues.
- `flutter test`: 4 passed (registration/validation, 390px and 1200px responsive navigation, real SQLite offline cache/outbox/reconnect/account isolation).
- `npm run check` in server: passed.
- `npm test` in server: 7 passed (auth/revocation/expiry/deletion, two-device sync/conflicts/tombstones, output validation/scoring/idempotent offline replay/reviews, atomic concurrent quota/admin/Pro expiry, PDF authorization/validation, restart/password revocation, Gemini retry/quota/malformed output).
- `npm audit --omit=dev`: zero reported vulnerabilities after updating Drizzle.
- Real HTTP API startup/registration, administrator bootstrap CLI, backup CLI and backup SQLite integrity check: passed with temporary test data.
- Linux release build: passed. Missing libsecret development packages were downloaded/extracted under `/tmp/study-ai-build-deps` without changing system packages; the build used `PKG_CONFIG_PATH=/tmp/study-ai-build-deps/root/usr/lib/x86_64-linux-gnu/pkgconfig`. Normal development should install `libsecret-1-dev` as described in README.
- Linux executable: 12-second Xvfb launch smoke test, no Dart crash observed; process deliberately stopped by timeout. This is not a full native acceptance test.
- Android debug APK: passed (`flutter build apk --debug`), output `build/app/outputs/flutter-apk/app-debug.apk`. First build installed the required Android SDK platforms/NDK/CMake through the existing toolchain. No Android device/emulator runtime acceptance test was performed.
- iOS/macOS: not built/tested on Ubuntu.
- Live Gemini generation: unverified; no API credentials configured. Test fixtures are test-only and never a production fallback.

## Remaining before production

- Live Gemini acceptance tests using genuine documents; stronger PDF parsing/scanning beyond signature checks; abuse/content policy and operational review.
- Full bidirectional sync for offline study-set creation/editing, richer conflict UI, full attempt/review delta synchronization. Attempts/reviews upload and contribute to synchronized server analytics; per-card due state is not yet surfaced or used to filter a due-only review session.
- Offline PDF binary cache/viewer. Notes/questions/cards are cached; original PDF files are server-side only.
- Drag/drop upload, resizable panels, global search shortcut, onboarding tour, persistent appearance preference, complete accessibility/reduced-motion audits and native visual QA.
- Timed exam persistence/enforcement, immediate question feedback mode, detailed historical attempt answer review, daily activity charts, distinct advanced analytics entitlement/UI.
- Document folder organization, generation into additional decks per set, PDF replacement UI and comprehensive study-set create/upload rollback behavior.
- Migration upgrades beyond the versioned transactional initial schema, broader Drizzle query adoption, cursor retention/compaction, crash-recovery policy for pending generations, filesystem garbage collection after soft deletion.
- Deploy TLS, persistent server storage, automatic private backup scheduling and restore drills, monitoring, retention/privacy policy, security/load audit and full native integration tests.
- Password recovery/email delivery intentionally absent. There is no configured delivery system. No payments or external subscription service.

## Source file inventory

The directory did not contain a Git repository, so no commit/diff was created. Build artifacts, downloaded dependencies, and temporary build tooling are excluded from this source inventory.

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
