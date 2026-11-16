// Native acceptance fixture only. Never imported by src/index.ts or production.
import { createApp } from "../src/app.js";
const directory = process.argv[2];
if (!directory) throw new Error("Provide a temporary test data directory.");
const app = createApp({
  dataDir: `${directory}/data`,
  uploadDir: `${directory}/uploads`,
  generate: async (input) => ({
    questions:
      input.kind === "flashcards"
        ? []
        : Array.from({ length: input.count }, (_, index) => ({
            question: `What does ATP carry? (${index + 1})`,
            choices: ["Energy", "Oxygen", "Water", "DNA"],
            answer: 0,
            explanation: "ATP transfers chemical energy.",
            topic: "Cell biology",
            difficulty: input.difficulty,
          })),
    flashcards:
      input.kind !== "flashcards"
        ? []
        : Array.from({ length: input.count }, () => ({
            front: "ATP",
            back: "An energy carrier",
            topic: "Cell biology",
            difficulty: input.difficulty,
          })),
  }),
});
await app.listen({ host: "127.0.0.1", port: 0 });
const address = app.server.address();
if (!address || typeof address === "string")
  throw new Error("No listening address.");
console.log(JSON.stringify({ port: address.port }));
for (const signal of ["SIGTERM", "SIGINT"])
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
