import "dotenv/config";
import { createApp } from "./app.js";
const app = createApp();
await app.listen({
  host: process.env.HOST || "127.0.0.1",
  port: Number(process.env.PORT || 3000),
});
console.log("Study AI backend listening.");
for (const signal of ["SIGTERM", "SIGINT"])
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
  });
