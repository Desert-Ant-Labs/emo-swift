// The emo-node test suite. Runs server-side in Node against the native core (the
// `node` conditional-exports entry), with model files loaded from the local
// resources instead of the Hugging Face Hub. The browser entry (WebAssembly +
// LiteRT.js) is exercised by the headless-Chromium example.
import assert from "node:assert/strict";
import { test } from "node:test";

import { Emo } from "../node.js";

// The npm package bundles the LiteRT model (packages/emo-node/model), so the
// default `Emo.load()` runs real on-device inference offline, no directory or
// network needed.
let emo;
let loadError;
try {
  emo = await Emo.load();
} catch (e) {
  loadError = e;
}
const modelOpts = emo ? {} : { skip: `native model unavailable: ${String(loadError).slice(0, 120)}` };

test("suggests emoji for an English phrase", modelOpts, async () => {
  const suggestions = await emo.suggestions("Pay my bills", { limit: 5 });
  assert.ok(suggestions.length > 0, "expected suggestions");
  assert.ok(suggestions.some((s) => ["💰", "💳", "🧾", "🏦", "📄"].includes(s.emoji)),
    `got ${suggestions.map((s) => s.emoji).join(" ")}`);
});

test("suggests emoji for a multilingual phrase", modelOpts, async () => {
  const suggestions = await emo.suggestions("犬の散歩", { limit: 5 });
  assert.ok(suggestions.some((s) => ["🐕", "🐾"].includes(s.emoji)),
    `got ${suggestions.map((s) => s.emoji).join(" ")}`);
});

test("ranks by confidence and honors limit", modelOpts, async () => {
  const suggestions = await emo.suggestions("book a flight to Tokyo", { limit: 3 });
  assert.equal(suggestions.length, 3);
  assert.ok(suggestions[0].confidence >= suggestions[1].confidence);
  assert.ok(suggestions.every((s) => s.confidence >= 0 && s.confidence <= 1));
});

test("empty input returns []", modelOpts, async () => {
  assert.deepEqual(await emo.suggestions("   "), []);
});

test.after(() => emo?.dispose());
