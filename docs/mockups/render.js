const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const [html, outDir, scale] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: Number(scale) });
  await page.goto('file://' + path.resolve(html));
  await page.evaluate(() => document.fonts.ready);
  for (const id of (process.argv[5] || 'library,keyboard,polish,dictate,quicksave,hues,sync,mac,palette,studio,wifi,scan,vault,member,collection,quickpanel').split(',')) {
    const box = await page.locator('#' + id).boundingBox();
    const pad = (id === 'mac' || id === 'quickpanel') ? 30 : id === 'palette' ? 0 : 16;
    await page.screenshot({ fullPage: true, path: `${outDir}/${id}.png`,
      clip: { x: box.x - pad, y: box.y - pad, width: box.width + pad*2, height: box.height + pad*2 + ((id==='mac' || id==='quickpanel')?20:0) } });
  }
  await browser.close();
})();
