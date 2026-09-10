#!/usr/bin/env node
// Reddit search via Puppeteer — prints JSON results to stdout.
// Usage: node reddit.mjs <query>

import path from "node:path"
import { fileURLToPath } from "node:url"
import puppeteer from "puppeteer"

const MAX_RESULTS = 50
const __filename = fileURLToPath(import.meta.url)

function fail(message, code = 1) {
  process.stderr.write(String(message || "reddit search failed") + "\n")
  process.exit(code)
}

async function scrapeSearch(page, searchUrl) {
  await page.goto(searchUrl, { waitUntil: "domcontentloaded", timeout: 45000 })
  await page.waitForSelector('[data-testid="post-title"], a[href*="/r/"], a[href*="/user/"]', {
    timeout: 20000,
  }).catch(() => {})
  await new Promise((r) => setTimeout(r, 1200))
  await page.evaluate(() => window.scrollBy(0, 1600)).catch(() => {})
  await new Promise((r) => setTimeout(r, 600))

  return page.evaluate(() => {
    function clean(s) {
      return String(s || "").replace(/\s+/g, " ").trim()
    }

    function parentText(el, depth) {
      let n = el
      for (let i = 0; i < depth && n; i++) {
        const t = clean(n.innerText || "")
        if (t)
          return t
        n = n.parentElement
      }
      return ""
    }

    function firstImg(root) {
      if (!root)
        return ""
      const imgs = Array.from(root.querySelectorAll("img"))
      for (const img of imgs) {
        const src = String(img.currentSrc || img.src || "")
        if (!src || src.indexOf("http") !== 0)
          continue
        if (/sprite|emoji|award/i.test(src))
          continue
        return src
      }
      return ""
    }

    const posts = []
    const seenPosts = new Set()
    for (const a of document.querySelectorAll('[data-testid="post-title"]')) {
      const href = String(a.href || "")
      const title = clean(a.textContent)
      if (!href || !title || seenPosts.has(href))
        continue
      seenPosts.add(href)
      const m = href.match(/\/r\/([^/]+)\//)
      const sub = m ? ("r/" + m[1]) : ""
      const block = a.closest("faceplate-tracker") || a.closest("div") || a.parentElement
      const thumb = firstImg(block)
      const blob = parentText(a, 5)
      const lines = blob.split("\n").map(clean).filter(Boolean)
      const extras = lines.filter((l) => l !== title && l !== sub).slice(0, 3)
      posts.push({
        type: "post",
        id: href,
        title,
        subreddit: sub,
        author: "",
        detail: [sub].concat(extras).filter(Boolean).join(" · "),
        url: href,
        thumbnail: thumb,
      })
    }

    const communities = []
    const seenComm = new Set()
    for (const a of document.querySelectorAll('a[href*="/r/"]')) {
      const href = String(a.href || "").split("?")[0]
      if (!/^https:\/\/www\.reddit\.com\/r\/[^/]+\/?$/.test(href))
        continue
      const key = href.replace(/\/$/, "")
      if (seenComm.has(key))
        continue
      seenComm.add(key)
      let name = clean(a.textContent)
      const m = key.match(/\/r\/([^/]+)$/)
      const fallback = m ? ("r/" + m[1]) : key
      if (!name || name.length > 40)
        name = fallback
      if (name.indexOf("r/") !== 0 && m)
        name = "r/" + m[1]
      const block = a.closest("faceplate-tracker") || a.closest("div") || a.parentElement
      const thumb = firstImg(block)
      const blob = parentText(a, 4)
      const lines = blob.split("\n").map(clean).filter(Boolean)
      const extras = lines.filter((l) => l !== name && l !== fallback && l.indexOf("r/") !== 0).slice(0, 2)
      communities.push({
        type: "subreddit",
        id: key,
        title: name,
        subreddit: name,
        author: "",
        detail: ["Subreddit"].concat(extras).filter(Boolean).join(" · "),
        url: key + "/",
        thumbnail: thumb,
      })
    }

    const people = []
    const seenUser = new Set()
    for (const a of document.querySelectorAll('a[href*="/user/"]')) {
      const href = String(a.href || "").split("?")[0]
      if (!/^https:\/\/www\.reddit\.com\/user\/[^/]+\/?$/.test(href))
        continue
      const key = href.replace(/\/$/, "")
      if (seenUser.has(key))
        continue
      seenUser.add(key)
      const m = key.match(/\/user\/([^/]+)$/)
      const user = m ? m[1] : ""
      if (!user)
        continue
      let label = clean(a.textContent) || user
      if (label.indexOf("u/") !== 0)
        label = "u/" + user
      const block = a.closest("faceplate-tracker") || a.closest("div") || a.parentElement
      const thumb = firstImg(block)
      people.push({
        type: "user",
        id: key,
        title: label,
        subreddit: "",
        author: label,
        detail: "User",
        url: key + "/",
        thumbnail: thumb,
      })
    }

    return { posts, communities, people }
  })
}

export async function search(browser, query) {
  const qRaw = String(query || "").trim()
  if (!qRaw)
    return []

  const page = await browser.newPage()
  try {
    await page.setViewport({ width: 1400, height: 1100 })
    await page.setUserAgent(
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    await page.setExtraHTTPHeaders({ "Accept-Language": "en-US,en;q=0.9" })

    const q = encodeURIComponent(qRaw)
    // All tab first (posts + some communities/people), then dedicated tabs to fill gaps.
    const all = await scrapeSearch(page, "https://www.reddit.com/search/?q=" + q + "&type=all")
    let communities = all.communities || []
    let people = all.people || []
    const posts = all.posts || []

    if (communities.length < 6) {
      const more = await scrapeSearch(page, "https://www.reddit.com/search/?q=" + q + "&type=communities")
      communities = (more.communities || []).concat(communities)
    }
    if (people.length < 5) {
      const more = await scrapeSearch(page, "https://www.reddit.com/search/?q=" + q + "&type=people")
      people = (more.people || []).concat(people)
    }

    const results = []
    const seen = new Set()
    function push(item) {
      if (!item || !item.url)
        return
      const key = item.type + ":" + item.url
      if (seen.has(key))
        return
      seen.add(key)
      results.push(item)
    }

    for (const c of communities.slice(0, 10))
      push(c)
    for (const u of people.slice(0, 6))
      push(u)
    for (const p of posts)
      push(p)

    return results.slice(0, MAX_RESULTS)
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
