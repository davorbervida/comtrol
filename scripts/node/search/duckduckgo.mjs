#!/usr/bin/env node
// DuckDuckGo web search via Puppeteer (html.duckduckgo.com) — prints JSON to stdout.
// Usage: node duckduckgo.mjs <query>
// Fetches the first two result pages.

import path from "node:path"
import { fileURLToPath } from "node:url"
import puppeteer from "puppeteer"

const PAGES = 2
const PAGE_SIZE = 30
const MAX_RESULTS = 20
const __filename = fileURLToPath(import.meta.url)

function fail(message, code = 1) {
  process.stderr.write(String(message || "duckduckgo search failed") + "\n")
  process.exit(code)
}

function scrapeDdgPage() {
  function unwrap(href) {
    const h = String(href || "")
    try {
      const u = new URL(h, "https://duckduckgo.com")
      const uddg = u.searchParams.get("uddg")
      if (uddg)
        return decodeURIComponent(uddg)
    } catch {
      // ignore
    }
    return h
  }

  function isDdgUrl(h) {
    return /duckduckgo\.com|duck\.com/i.test(String(h || ""))
  }

  function plausibleUrl(u) {
    try {
      const x = new URL(u)
      if (!/^https?:$/i.test(x.protocol))
        return false
      if (!/\./.test(x.hostname))
        return false
      if (isDdgUrl(u))
        return false
      return true
    } catch {
      return false
    }
  }

  function faviconFor(url) {
    try {
      const host = new URL(url).hostname
      if (!host)
        return ""
      return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(host) + "&sz=64"
    } catch {
      return ""
    }
  }

  const out = []
  const seen = new Set()
  const results = document.querySelectorAll(".result, .web-result, .results_links")
  const nodes = results.length > 0
    ? results
    : document.querySelectorAll(".result__body, .links_main")

  function pushFromAnchor(a, snippetEl, urlEl) {
    if (!a)
      return
    const title = String(a.textContent || "").trim()
    if (!title)
      return
    const raw = a.getAttribute("href") || a.href || ""
    const url = unwrap(raw)
    if (!url || !plausibleUrl(url) || seen.has(url))
      return
    seen.add(url)

    const snippet = String(snippetEl?.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200)
    const cite = String(urlEl?.textContent || "").trim().replace(/\s+/g, " ")
    const detail = [cite || url, snippet].filter(Boolean).join(" · ").slice(0, 240)
    out.push({
      type: "web",
      id: url,
      title,
      detail,
      url,
      thumbnail: faviconFor(url),
    })
  }

  for (const node of nodes) {
    const a = node.querySelector("a.result__a")
      || node.querySelector("a[href*='uddg=']")
      || node.querySelector("a")
    const snip = node.querySelector(".result__snippet")
      || node.querySelector(".result__snippet.js-result-snippet")
    const urlEl = node.querySelector("a.result__url") || node.querySelector(".result__url")
    pushFromAnchor(a, snip, urlEl)
  }

  if (out.length === 0) {
    for (const a of document.querySelectorAll("a.result__a")) {
      pushFromAnchor(a, a.parentElement, null)
    }
  }

  return out
}

async function loadDdgPage(page, q, offset) {
  const url = "https://html.duckduckgo.com/html/?q="
    + encodeURIComponent(q)
    + "&s=" + String(offset)
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 })
  await page.waitForSelector("a.result__a, .result", { timeout: 15000 }).catch(() => {})
  await new Promise((r) => setTimeout(r, 600))
  return page.evaluate(scrapeDdgPage)
}

export async function search(browser, query) {
  const q = String(query || "").trim()
  if (!q)
    return []

  const page = await browser.newPage()
  try {
    await page.setViewport({ width: 1280, height: 1000 })
    await page.setUserAgent(
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    await page.setExtraHTTPHeaders({ "Accept-Language": "en-US,en;q=0.9" })
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(navigator, "webdriver", { get: () => undefined })
    })

    const merged = []
    const seen = new Set()
    for (let p = 0; p < PAGES; p++) {
      const offset = p * PAGE_SIZE
      const batch = await loadDdgPage(page, q, offset)
      for (const item of batch || []) {
        const key = String(item?.url || "")
        if (!key || seen.has(key))
          continue
        seen.add(key)
        merged.push(item)
      }
    }

    return merged.slice(0, MAX_RESULTS)
  } finally {
    await page.close().catch(() => {})
  }
}

async function main() {
  const args = process.argv.slice(2).filter((a) => a !== "--")
  const query = args.join(" ").trim()

  if (!query) {
    process.stdout.write(JSON.stringify({ query: "", results: [] }) + "\n")
    return
  }

  let browser
  try {
    browser = await puppeteer.launch({
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--disable-blink-features=AutomationControlled",
        "--lang=en-US,en",
      ],
    })
    const results = await search(browser, query)
    process.stdout.write(JSON.stringify({ query, results }) + "\n")
  } catch (err) {
    fail(err?.stack || err?.message || String(err))
  } finally {
    if (browser)
      await browser.close().catch(() => {})
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main().catch((err) => fail(err?.stack || err?.message || String(err)))
}
