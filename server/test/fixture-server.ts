// Native acceptance fixture only. Never imported by src/index.ts or production.
import { createApp } from "../src/app.js";
const directory = process.argv[2];
if (!directory) throw new Error("Provide a temporary test data directory.");
const app = createApp({
  dataDir: `${directory}/data`,
  uploadDir: `${directory}/uploads`,
  notebookGenerate: async (input) => ({
    insufficientEvidence: false,
    blocks: [
      {
        heading: "Energy for cellular work",
        text: "ATP transfers chemical energy. Use this core idea to connect the cellular processes in your notes.",
        citations: [
          {
            chunkId: input.chunks[0].id,
            quote: input.chunks[0].text.slice(0, 70),
          },
        ],
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
  });
