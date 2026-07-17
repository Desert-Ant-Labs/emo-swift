# EmoWasmExample

Node and headless-browser examples for `@desert-ant-labs/emo`.

```bash
npm install
npm run node-example      # API-shape smoke test (LiteRT.js is browser-only)
npm run browser-example   # headless Chromium + LiteRT.js (needs playwright)
```

The browser example suggests emoji for a phrase on device via LiteRT.js.
LiteRT.js needs a DOM, so the Node example only exercises the API shape and the
graceful "runtime absent" path. The browser test serves the model from the
local LiteRT resources (by intercepting the Hugging Face Hub requests), so it
runs before the model is published; after publish it works against the real Hub.
