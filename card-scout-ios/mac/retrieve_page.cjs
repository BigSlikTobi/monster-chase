// One public page per isolated process. No login, persistent profile or paid service.
const fs = require('node:fs');
const hosts = new Set(['www.sportscardspro.com', 'sportscardspro.com', 'www.ebay.com', 'www.ebay.de']);
function allowed(raw) {
  const u = new URL(raw);
  return u.protocol === 'https:' && hosts.has(u.hostname) && !u.username && !u.password && (!u.port || u.port === '443');
}
(async () => {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (!allowed(input.url)) throw new Error('Source outside allowlist');
  const {chromium} = require(input.module);
  const browser = await chromium.launch({headless: true, chromiumSandbox: true});
  try {
    const context = await browser.newContext({serviceWorkers: 'block', acceptDownloads: false});
    await context.route('**/*', route => {
      const request = route.request();
      if (!allowed(request.url()) || ['image', 'media', 'font'].includes(request.resourceType())) return route.abort();
      return route.continue();
    });
    const page = await context.newPage();
    const response = await page.goto(input.url, {waitUntil: 'domcontentloaded', timeout: 16000});
    const status = response?.status() || 0;
    const url = page.url();
    if (!allowed(url)) throw new Error('Redirect outside allowlist');
    if (status !== 200) {
      process.stdout.write(JSON.stringify({url, status: [401,403,429].includes(status) ? 'blocked' : 'unavailable', httpStatus: status}));
    } else {
      const html = await page.content();
      process.stdout.write(JSON.stringify(html.length > 1500000 ? {url, status: 'too_large'} : {url, status: 'ok', html}));
    }
  } finally { await browser.close(); }
})().catch(() => { process.stderr.write('Public-page browser retrieval unavailable\n'); process.exitCode = 1; });
