// Node example for packages/emo-node. In Node the package's conditional exports
// resolve to the prebuilt native core (node.js), so inference runs natively
// server-side - no browser, no LiteRT.js needed. (The browser example,
// browser.html / `npm run browser-example`, exercises the WebAssembly +
// LiteRT.js path instead.)
import { Emo } from "@desert-ant-labs/emo";

// Emo downloads, verifies (SHA-256), and caches the model from the Hub, then
// runs inference through the native core. First run fetches; later runs cache.
const emo = await Emo.load({});

const start = Date.now();
const suggestions = await emo.suggestions("Pay my bills", { limit: 3 });
console.log("suggestions:", suggestions.map((s) => s.emoji).join(" "));
console.log(JSON.stringify(suggestions, null, 2));
console.log(`(${Date.now() - start} ms)`);
emo.dispose();
