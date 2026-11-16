import "dotenv/config";
import { randomUUID } from "node:crypto";
import { openDatabase } from "./database/db.js";
const email = process.argv[2]?.toLowerCase();
if (!email)
  throw new Error("Usage: npm run admin -- registered-account@example.com");
const { sqlite } = openDatabase(process.env.DATA_DIR || "./data");
try {
  sqlite.transaction(() => {
    const user = sqlite
      .prepare("SELECT id FROM users WHERE email=?")
      .get(email) as { id: string } | undefined;
    if (!user) throw new Error("Register the account through the app first.");
    sqlite.prepare("UPDATE users SET role='admin' WHERE id=?").run(user.id);
    sqlite
      .prepare("INSERT INTO admin_audit_logs VALUES(?,?,?,?,?)")
      .run(randomUUID(), user.id, user.id, "bootstrap_admin_cli", Date.now());
  })();
  console.log("Administrator role granted to the existing account.");
} finally {
  sqlite.close();
}
