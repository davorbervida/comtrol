#!/usr/bin/env node
// X (Twitter) search via Puppeteer + DuckDuckGo HTML.
// X blocks guest search; DDG returns real x.com / twitter.com links.
// Usage: node x.mjs <query>

import path from "node:path"
import { fileURLToPath } from "node:url"
import puppeteer from "puppeteer"

const PAGES = 2
const PAGE_SIZE = 30
const MAX_RESULTS = 40
const __filename = fileURLToPath(import.meta.url)

const RESERVED = new Set([
  "home", "explore", "search", "settings", "messages", "notifications",
  "i", "intent", "compose", "login", "signup", "trending", "tos", "privacy",
  "hashtag", "share", "about", "download", "jobs", "help",
])

function fail(message, code = 1) {
  process.stderr.write(String(message || "x search failed") + "\n")
  process.exit(code)
}

function ddgQuery(q) {
  return "(site:x.com OR site:twitter.com) " + q
}

function unwrapDdg(href) {
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

function normalizeXUrl(raw) {
  let u = String(raw || "").trim()
  if (!u)
    return ""
  try {
    const url = new URL(u)
    let host = url.hostname.replace(/^www\./, "").toLowerCase()
    if (host === "twitter.com" || host === "mobile.twitter.com" || host === "t.co")
      host = "x.com"
    if (host !== "x.com")
      return ""
    url.hash = ""
    url.search = ""
    let path = url.pathname.replace(/\/+$/, "")
    if (!path || path === "/")
      return ""
    path = path.replace(/\/(with_replies|media|likes|followers|following)$/i, "")
    const parts = path.split("/").filter(Boolean)
    if (parts.length === 0)
      return ""
    if (RESERVED.has(parts[0].toLowerCase()))
      return ""
    return "https://x.com/" + parts.join("/")
  } catch {
    return ""
  }
}

function classify(url) {
  const mStatus = url.match(/^https:\/\/x\.com\/([^/]+)\/status\/(\d+)/i)
  if (mStatus) {
    return { type: "tweet", user: mStatus[1], id: mStatus[2] }
  }
  const mUser = url.match(/^https:\/\/x\.com\/([^/]+)\/?$/i)
  if (mUser && !RESERVED.has(mUser[1].toLowerCase())) {
    return { type: "user", user: mUser[1], id: mUser[1] }
  }
  return { type: "post", user: "", id: url }
}

function avatarFor(user) {
  const u = String(user || "").trim()
  if (!u)
    return "https://www.google.com/s2/favicons?domain=x.com&sz=64"
  return "https://unavatar.io/x/" + encodeURIComponent(u)
}

function scrapeDdgPage() {
  const out = []
  const seen = new Set()
  const results = document.querySelectorAll(".result, .web-result, .results_links")
  const nodes = results.length > 0
    ? results
    : document.querySelectorAll(".result__body, .links_main")

  function pushFromAnchor(a, snippetEl) {
    if (!a)
      return
    const title = String(a.textContent || "").trim()
    if (!title)
      return
    const raw = a.getAttribute("href") || a.href || ""
    let target = raw
    try {
      const u = new URL(raw, "https://duckduckgo.com")
      const uddg = u.searchParams.get("uddg")
      if (uddg)
        target = decodeURIComponent(uddg)
    } catch {
      // ignore
    }
    // normalize twitter/x
    let url = ""
    try {
      const parsed = new URL(target)
      let host = parsed.hostname.replace(/^www\./, "").toLowerCase()
      if (host === "twitter.com" || host === "mobile.twitter.com")
        host = "x.com"
      if (host !== "x.com")
        return
      let path = parsed.pathname.replace(/\/+$/, "")
      path = path.replace(/\/(with_replies|media|likes|followers|following)$/i, "")
      const parts = path.split("/").filter(Boolean)
      if (!parts.length)
        return
      const reserved = new Set([
        "home", "explore", "search", "settings", "messages", "notifications",
        "i", "intent", "compose", "login", "signup", "trending", "tos", "privacy",
        "hashtag", "share", "about", "download", "jobs", "help",
      ])
      if (reserved.has(parts[0].toLowerCase()))
        return
      url = "https://x.com/" + parts.join("/")
    } catch {
      return
    }
    if (!url || seen.has(url))
      return
    seen.add(url)

    let type = "post"
    let user = ""
    let id = url
    const mStatus = url.match(/^https:\/\/x\.com\/([^/]+)\/status\/(\d+)/i)
    if (mStatus) {
      type = "tweet"
      user = mStatus[1]
      id = mStatus[2]
    } else {
      const mUser = url.match(/^https:\/\/x\.com\/([^/]+)\/?$/i)
      if (mUser) {
        type = "user"
        user = mUser[1]
        id = mUser[1]
      }
    }

    const snippet = String(snippetEl?.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200)
    const handle = user ? ("@" + user) : ""
    const kindLabel = type === "tweet" ? "Post" : (type === "user" ? "Profile" : "X")
    out.push({
      type,
      id,
      title,
      user,
      detail: [kindLabel, handle, snippet].filter(Boolean).join(" · ").slice(0, 240),
      url,
      thumbnail: user
        ? ("https://unavatar.io/x/" + encodeURIComponent(user))
        : "https://www.google.com/s2/favicons?domain=x.com&sz=64",
    })
  }

  for (const node of nodes) {
    const a = node.querySelector("a.result__a") || node.querySelector("a[href*='uddg=']") || node.querySelector("a")
    const snip = node.querySelector(".result__snippet") || node.querySelector(".result__snippet.js-result-snippet")
    pushFromAnchor(a, snip)
  }

  // Fallback: any result links.
  if (out.length === 0) {
    for (const a of document.querySelectorAll("a.result__a, a.result__url")) {
      pushFromAnchor(a, a.parentElement)
    }
  }

  return out
}

async function loadDdgPage(page, q, offset) {
  const url = "https://html.duckduckgo.com/html/?q="
    + encodeURIComponent(ddgQuery(q))
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

    // Prefer tweets, then profiles.
    merged.sort((a, b) => {
      const rank = (t) => (t === "tweet" ? 0 : (t === "user" ? 1 : 2))
      return rank(a.type) - rank(b.type)
    })

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
