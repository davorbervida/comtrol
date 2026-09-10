// Shared Puppeteer launch options for cOMtrol web search.
export const LAUNCH_ARGS = [
  "--no-sandbox",
  "--disable-setuid-sandbox",
  "--disable-dev-shm-usage",
  "--disable-gpu",
  "--disable-blink-features=AutomationControlled",
  "--lang=en-US,en",
]

export const USER_AGENT =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

export async function preparePage(page, opts = {}) {
  const width = opts.width || 1400
  const height = opts.height || 1000
  await page.setViewport({ width, height })
  await page.setUserAgent(USER_AGENT)
  await page.setExtraHTTPHeaders({
    "Accept-Language": opts.acceptLanguage || "en-US,en;q=0.9",
    ...(opts.headers || {}),
  })
  if (opts.hideWebdriver !== false) {
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(navigator, "webdriver", { get: () => undefined })
    }).catch(() => {})
  }
}
