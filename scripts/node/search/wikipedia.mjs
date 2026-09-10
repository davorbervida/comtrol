#!/usr/bin/env node
// Wikipedia search via Puppeteer + MediaWiki API.
// Usage: node wikipedia.mjs <query>

import path from "node:path"
import { fileURLToPath } from "node:url"
import puppeteer from "puppeteer"

const PAGES = 2
const PAGE_SIZE = 15
const MAX_RESULTS = 30
const __filename = fileURLToPath(import.meta.url)

// Always use English Wikipedia.
const WIKIS = [
  { lang: "en", host: "en.wikipedia.org" },
]

function fail(message, code = 1) {
  process.stderr.write(String(message || "wikipedia search failed") + "\n")
  process.exit(code)
}

function apiUrl(host, params) {
  const u = new URL("https://" + host + "/w/api.php")
  for (const [k, v] of Object.entries(params))
    u.searchParams.set(k, String(v))
  return u.toString()
}

async function loadJson(page, url) {
  const response = await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: 45000,
  })
  const status = response ? response.status() : 0
  const text = await page.evaluate(() => document.body?.innerText || document.body?.textContent || "")
  if (status && status >= 400)
    throw new Error("Wikipedia HTTP " + status)
  try {
    return JSON.parse(text)
  } catch {
    throw new Error("Wikipedia returned non-JSON")
  }
}

function pagesFromQuery(data, host, lang) {
  const map = data?.query?.pages
  if (!map || typeof map !== "object")
    return []
  const list = Object.values(map)
  list.sort((a, b) => Number(a.index || 0) - Number(b.index || 0))
  const out = []
  for (const p of list) {
    const title = String(p?.title || "").trim()
    if (!title)
      continue
    const pageid = String(p?.pageid || title)
    const url = String(p?.fullurl || ("https://" + host + "/wiki/" + encodeURIComponent(title.replace(/ /g, "_"))))
    const extract = String(p?.extract || "").trim().replace(/\s+/g, " ").slice(0, 220)
    const thumb = String(p?.thumbnail?.source || "")
    out.push({
      type: "article",
      id: lang + ":" + pageid,
      title,
      lang,
      detail: [lang.toUpperCase(), extract].filter(Boolean).join(" · "),
      url,
      thumbnail: thumb,
    })
  }
  return out
}

async function searchWiki(page, host, lang, q, offset) {
  const url = apiUrl(host, {
    action: "query",
    generator: "search",
    gsrsearch: q,
    gsrnamespace: 0,
    gsrlimit: PAGE_SIZE,
    gsroffset: offset,
    prop: "info|extracts|pageimages",
    inprop: "url",
    exintro: 1,
    explaintext: 1,
    exchars: 220,
    piprop: "thumbnail",
    pithumbsize: 128,
    pilicense: "any",
    format: "json",
    formatversion: 2,
    redirects: 1,
    utf8: 1,
  })
  const data = await loadJson(page, url)
  return pagesFromQuery(data, host, lang)
}

export async function search(browser, query) {
  const q = String(query || "").trim()
  if (!q)
    return []

  const page = await browser.newPage()
  try {
    await page.setViewport({ width: 1100, height: 900 })
    await page.setUserAgent(
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    await page.setExtraHTTPHeaders({
      "Accept-Language": "en-US,en;q=0.9",
      Accept: "application/json,text/plain,*/*",
    })

    const merged = []
    const seen = new Set()

    function pushAll(items) {
      for (const item of items || []) {
        const key = String(item?.url || item?.id || "")
        if (!key || seen.has(key))
          continue
        // Also dedupe by title across languages (prefer first = HR).
        const titleKey = String(item?.title || "").toLowerCase()
        if (titleKey && seen.has("title:" + titleKey))
          continue
        seen.add(key)
        if (titleKey)
          seen.add("title:" + titleKey)
        merged.push(item)
      }
    }

    for (const wiki of WIKIS) {
      for (let p = 0; p < PAGES; p++) {
        const offset = p * PAGE_SIZE
        try {
          const batch = await searchWiki(page, wiki.host, wiki.lang, q, offset)
          pushAll(batch)
        } catch (e) {
          // Continue with other wiki/page if one fails.
          if (p === 0 && wiki === WIKIS[0])
            process.stderr.write(String(e?.message || e) + "\n")
        }
        if (merged.length >= MAX_RESULTS)
          break
      }
      if (merged.length >= MAX_RESULTS)
        break
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
