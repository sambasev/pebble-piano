// Renders docs/charts/eval_summary.html to docs/charts/eval_summary.png (1920x1080 slide, 2x).
// Usage: node scripts/render_eval_slide.js
const path = require("path");
const { chromium } = require("playwright");

(async () => {
  const dir = path.join(__dirname, "..", "docs", "charts");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 2 });
  await page.goto("file://" + path.join(dir, "eval_summary.html"));
  await page.screenshot({ path: path.join(dir, "eval_summary.png") });
  await browser.close();
})();
