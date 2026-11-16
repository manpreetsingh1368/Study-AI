import { test } from "node:test";
import assert from "node:assert/strict";
import { generate } from "../src/ai/gemini.js";
test("Gemini configuration, retry, quota and structured response validation", async () => {
  const oldFetch = globalThis.fetch,
    oldKey = process.env.GEMINI_API_KEY,
    oldModel = process.env.GEMINI_MODEL;
  const input = {
    notes: "ATP stores chemical energy",
    kind: "quiz" as const,
    count: 1,
    difficulty: "medium" as const,
  };
  try {
    delete process.env.GEMINI_API_KEY;
    await assert.rejects(generate(input), /Configure/);
    process.env.GEMINI_API_KEY = "test-only";
    process.env.GEMINI_MODEL = "test-model";
    let calls = 0;
    globalThis.fetch = async () => {
      calls++;
      return new Response("{}", { status: 503 });
    };
    await assert.rejects(generate(input), /provider/);
    assert.equal(calls, 2);
    globalThis.fetch = async () => new Response("{}", { status: 429 });
    await assert.rejects(generate(input), /quota/);
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: JSON.stringify({
                      questions: [
                        { question: "Q", choices: ["A", "B"], answer: 7 },
                      ],
                      flashcards: [],
                    }),
                  },
                ],
              },
            },
          ],
        }),
      );
    await assert.rejects(generate(input));
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [
                  { text: JSON.stringify({ questions: [], flashcards: [] }) },
                ],
              },
            },
          ],
        }),
      );
    await assert.rejects(generate(input), /item count/);
  } finally {
    globalThis.fetch = oldFetch;
    if (oldKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = oldKey;
    if (oldModel === undefined) delete process.env.GEMINI_MODEL;
    else process.env.GEMINI_MODEL = oldModel;
  }
});
