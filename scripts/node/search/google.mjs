#!/usr/bin/env node
// Google web search via Puppeteer — prints JSON results to stdout.
// Usage: node google.mjs <query>
// Fetches the first two result pages.

import path from "node:path"
import { fileURLToPath } from "node:url"
import puppeteer from "puppeteer"

const PAGES = 2
const RESULTS_PER_PAGE = 10
const MAX_RESULTS = PAGES * RESULTS_PER_PAGE
const __filename = fileURLToPath(import.meta.url)

function fail(message, code = 1) {
  process.stderr.write(String(message || "google search failed") + "\n")
  process.exit(code)
}

async function acceptConsent(page) {
  try {
    await page.evaluate(() => {
      const btn = document.querySelector("#L2AGLb")
        || Array.from(document.querySelectorAll("button")).find((b) =>
          /prihvati sve|accept all|i agree|akzeptieren|aceptar todo/i.test(b.innerText || ""))
      if (btn)
        btn.click()
    })
  } catch {
    // ignore
  }
  await new Promise((r) => setTimeout(r, 700))
}

function scrapeResultsInPage() {
  function isGoogleUrl(h) {
    return /google\.[a-z.]+\/|gstatic\.com|googleusercontent\.com\/favicon|accounts\.google|youtube\.com\/results/i.test(String(h || ""))
  }

  function plausibleUrl(u) {
    try {
      const x = new URL(u)
      if (!/^https?:$/i.test(x.protocol))
        return false
      if (!/\./.test(x.hostname))
        return false
      if (/[+\s]/.test(x.hostname))
        return false
      if (isGoogleUrl(u) && !/google\.[a-z.]+\/url\?/i.test(u))
        return false
      return true
    } catch {
      return false
    }
  }

  function fromCite(cite) {
    const c = String(cite || "").trim()
    if (!c)
      return ""
    const parts = c.split(/\s*[›>]\s*/).map((s) => s.trim().replace(/\s+/g, "")).filter(Boolean)
    if (parts.length === 0)
      return ""
    let url = parts[0]
    if (!/^https?:\/\//i.test(url))
      url = "https://" + url
    for (let i = 1; i < parts.length; i++) {
      if (!parts[i] || parts[i] === "...")
        continue
      url += "/" + parts[i]
    }
    return plausibleUrl(url) ? url : ""
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

  for (const h3 of document.querySelectorAll("#search a h3, #rso a h3")) {
    const a = h3.closest("a")
    if (!a)
      continue
    const title = String(h3.textContent || "").trim()
    if (!title)
      continue

    const block = a.closest("div.g")
      || a.closest("div[data-hveid]")
      || a.parentElement?.parentElement?.parentElement
    const citeText = String(block?.querySelector("cite")?.textContent || "").trim()

    let url = ""
    if (block) {
      for (const link of block.querySelectorAll('a[href^="http"]')) {
        const href = String(link.href || "")
        if (href && !isGoogleUrl(href) && plausibleUrl(href)) {
          url = href
          break
        }
      }
    }
    if (!url)
      url = fromCite(citeText)

    if (!url) {
      let href = String(a.href || "")
      if (href.includes("/url?")) {
        try {
          const u = new URL(href)
          const q = u.searchParams.get("q") || u.searchParams.get("url") || ""
          if (plausibleUrl(q))
            url = q
        } catch {
          // ignore
        }
      }
    }

    if (!url || !plausibleUrl(url) || seen.has(url))
      continue
    seen.add(url)

    const snippet = String(
      block?.querySelector(".VwiC3b, .aCOpRe, [data-sncf='1']")?.textContent || ""
    ).trim().replace(/\s+/g, " ").slice(0, 200)

    const detail = [citeText, snippet].filter(Boolean).join(" · ").slice(0, 240)
    out.push({
      type: "web",
      id: url,
      title,
      detail,
      url,
      thumbnail: faviconFor(url),
    })
  }

  return out
}

async function loadSearchPage(page, q, start) {
  const searchUrl = "https://www.google.com/search?q="
    + encodeURIComponent(q)
    + "&hl=en&pws=0&num=" + String(RESULTS_PER_PAGE)
    + "&start=" + String(start)
  await page.goto(searchUrl, { waitUntil: "domcontentloaded", timeout: 45000 })
  await acceptConsent(page)
  await page.waitForSelector("#search a h3, #rso a h3", { timeout: 20000 }).catch(() => {})
  await new Promise((r) => setTimeout(r, 800))
  return page.evaluate(scrapeResultsInPage)
}

export async function search(browser, query) {
  const q = String(query || "").trim()
  if (!q)
    return []

  const page = await browser.newPage()
  try {
    await page.setViewport({ width: 1400, height: 1100 })
    await page.setUserAgent(
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    await page.setExtraHTTPHeaders({ "Accept-Language": "en-US,en;q=0.9" })
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(navigator, "webdriver", { get: () => undefined })
    })

    await page.goto("https://www.google.com/?hl=en", {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    })
    await acceptConsent(page)

    const merged = []
    const seen = new Set()
    for (let p = 0; p < PAGES; p++) {
      const start = p * RESULTS_PER_PAGE
      const batch = await loadSearchPage(page, q, start)
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
