import {
  type AnySQLiteColumn,
  sqliteTable,
  text,
  integer,
  primaryKey,
} from "drizzle-orm/sqlite-core";
export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  name: text("name").notNull(),
  passwordHash: text("password_hash").notNull(),
  role: text("role").notNull().default("student"),
  passwordEnabled: integer("password_enabled").notNull().default(1),
  createdAt: integer("created_at").notNull(),
});
export const studySets = sqliteTable("study_sets", {
  id: text("id").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  parentNotebookId: text("parent_notebook_id").references(
    (): AnySQLiteColumn => studySets.id,
    { onDelete: "cascade" },
  ),
  title: text("title").notNull(),
  notes: text("notes").notNull(),
  folder: text("folder").notNull().default(""),
  version: integer("version").notNull().default(1),
  deleted: integer("deleted").notNull().default(0),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
});
export const sessions = sqliteTable("sessions", {
  tokenHash: text("token_hash").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  expiresAt: integer("expires_at").notNull(),
  createdAt: integer("created_at").notNull().default(0),
});
export const documents = sqliteTable("documents", {
  id: text("id").primaryKey(),
  setId: text("set_id")
    .notNull()
    .unique()
    .references(() => studySets.id, { onDelete: "cascade" }),
  filename: text("filename").notNull(),
  bytes: integer("bytes").notNull(),
});
export const collections = sqliteTable("collections", {
  id: text("id").primaryKey(),
  setId: text("set_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  kind: text("kind").notNull(),
  title: text("title").notNull(),
  createdAt: integer("created_at").notNull(),
});
export const questions = sqliteTable("questions", {
  id: text("id").primaryKey(),
  setId: text("set_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  position: integer("position").notNull(),
  question: text("question").notNull(),
  choices: text("choices").notNull(),
  answer: integer("answer").notNull(),
  explanation: text("explanation").notNull(),
  difficulty: text("difficulty").notNull(),
  topic: text("topic").notNull(),
  collectionId: text("collection_id").references(() => collections.id),
});
export const flashcards = sqliteTable("flashcards", {
  id: text("id").primaryKey(),
  setId: text("set_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  front: text("front").notNull(),
  back: text("back").notNull(),
  topic: text("topic").notNull(),
  difficulty: text("difficulty").notNull(),
  collectionId: text("collection_id").references(() => collections.id),
});
export const flashcardReviews = sqliteTable("flashcard_reviews", {
  id: text("id").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  cardId: text("card_id")
    .notNull()
    .references(() => flashcards.id, { onDelete: "cascade" }),
  known: integer("known").notNull(),
  reviewedAt: integer("reviewed_at").notNull(),
  dueAt: integer("due_at").notNull(),
  intervalDays: integer("interval_days").notNull(),
});
export const quizAttempts = sqliteTable("quiz_attempts", {
  id: text("id").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  setId: text("set_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  score: integer("score").notNull(),
  total: integer("total").notNull(),
  createdAt: integer("created_at").notNull(),
  collectionId: text("collection_id").references(() => collections.id),
});
export const quizAnswers = sqliteTable("quiz_answers", {
  attemptId: text("attempt_id")
    .notNull()
    .references(() => quizAttempts.id, { onDelete: "cascade" }),
  questionId: text("question_id")
    .notNull()
    .references(() => questions.id, { onDelete: "cascade" }),
  answer: integer("answer").notNull(),
});
export const subscriptions = sqliteTable("subscriptions", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  startsAt: integer("starts_at").notNull(),
  expiresAt: integer("expires_at").notNull(),
});
export const generationUsage = sqliteTable("generation_usage", {
  id: text("id").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  day: text("day").notNull(),
  status: text("status").notNull(),
  requestHash: text("request_hash"),
  requestConfig: text("request_config"),
  collectionId: text("collection_id").references(() => collections.id, {
    onDelete: "set null",
  }),
  createdAt: integer("created_at").notNull(),
});
export const syncChanges = sqliteTable("sync_changes", {
  seq: integer("seq").primaryKey({ autoIncrement: true }),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  setId: text("set_id").notNull(),
  version: integer("version").notNull(),
  deleted: integer("deleted").notNull(),
});
export const adminAuditLogs = sqliteTable("admin_audit_logs", {
  id: text("id").primaryKey(),
  adminId: text("admin_id").references(() => users.id, {
    onDelete: "set null",
  }),
  targetId: text("target_id"),
  action: text("action").notNull(),
  createdAt: integer("created_at").notNull(),
});
export const applicationErrors = sqliteTable("application_errors", {
  id: text("id").primaryKey(),
  code: text("code").notNull(),
  createdAt: integer("created_at").notNull(),
});

export const mutationReceipts = sqliteTable(
  "mutation_receipts",
  {
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    operationId: text("operation_id").notNull(),
    payloadHash: text("payload_hash").notNull(),
    response: text("response").notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.operationId] })],
);
export const quizSessions = sqliteTable("quiz_sessions", {
  id: text("id").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  setId: text("set_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  collectionId: text("collection_id").references(() => collections.id),
  questionIds: text("question_ids").notNull(),
  startedAt: integer("started_at").notNull(),
  deadline: integer("deadline").notNull(),
  attemptId: text("attempt_id").unique(),
});
export const learningChanges = sqliteTable("learning_changes", {
  seq: integer("seq").primaryKey({ autoIncrement: true }),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  kind: text("kind").notNull(),
  recordId: text("record_id").notNull(),
});

export const recoveryCodes = sqliteTable("recovery_codes", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  codeHash: text("code_hash").notNull().unique(),
  expiresAt: integer("expires_at").notNull(),
  createdAt: integer("created_at").notNull(),
});

export const notebookEntries = sqliteTable("notebook_entries", {
  id: text("id").primaryKey(),
  notebookId: text("notebook_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  kind: text("kind").notNull(),
  prompt: text("prompt").notNull(),
  sourceIds: text("source_ids").notNull(),
  requestHash: text("request_hash").notNull(),
  content: text("content").notNull(),
  createdAt: integer("created_at").notNull(),
});
export const notebookNotes = sqliteTable("notebook_notes", {
  id: text("id").primaryKey(),
  notebookId: text("notebook_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  text: text("text").notNull(),
  citations: text("citations").notNull(),
  createdAt: integer("created_at").notNull(),
  deleted: integer("deleted").notNull().default(0),
});
export const notebookPreferences = sqliteTable("notebook_preferences", {
  notebookId: text("notebook_id")
    .primaryKey()
    .references(() => studySets.id, { onDelete: "cascade" }),
  sourceIds: text("source_ids").notNull(),
});

export const passwordResets = sqliteTable("password_resets", {
  tokenHash: text("token_hash").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  expiresAt: integer("expires_at").notNull(),
  usedAt: integer("used_at"),
  createdAt: integer("created_at").notNull(),
});
export const oauthIdentities = sqliteTable(
  "oauth_identities",
  {
    provider: text("provider").notNull(),
    subject: text("subject").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.provider, table.subject] })],
);
export const oauthFlows = sqliteTable("oauth_flows", {
  id: text("id").primaryKey(),
  provider: text("provider").notNull(),
  stateHash: text("state_hash").notNull().unique(),
  nonce: text("nonce").notNull(),
  pkceVerifier: text("pkce_verifier").notNull(),
  clientChallenge: text("client_challenge").notNull(),
  expiresAt: integer("expires_at").notNull(),
  status: text("status").notNull().default("pending"),
  userId: text("user_id").references(() => users.id, { onDelete: "cascade" }),
  linkUserId: text("link_user_id").references(() => users.id, {
    onDelete: "cascade",
  }),
  linkSessionHash: text("link_session_hash"),
  error: text("error"),
  launchHash: text("launch_hash").notNull(),
  launched: integer("launched").notNull().default(0),
});
export const notebookShares = sqliteTable("notebook_shares", {
  id: text("id").primaryKey(),
  notebookId: text("notebook_id")
    .notNull()
    .references(() => studySets.id, { onDelete: "cascade" }),
  tokenHash: text("token_hash").notNull().unique(),
  title: text("title").notNull(),
  snapshot: text("snapshot").notNull(),
  createdAt: integer("created_at").notNull(),
  expiresAt: integer("expires_at").notNull(),
  revokedAt: integer("revoked_at"),
});
