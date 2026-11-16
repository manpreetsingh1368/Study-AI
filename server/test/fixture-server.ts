// Native acceptance fixture only. Never imported by src/index.ts or production.
import { createApp } from "../src/app.js";
const directory = process.argv[2];
if (!directory) throw new Error("Provide a temporary test data directory.");
const app = createApp({
  dataDir: `${directory}/data`,
  uploadDir: `${directory}/uploads`,
  generate: async (input) => ({
