#!/usr/bin/env node
// YouTube search via Puppeteer — prints JSON results to stdout.
// Usage: node youtube.mjs <query>

import puppeteer from "puppeteer"

const MAX_RESULTS = 40
const args = process.argv.slice(2).filter((a) => a !== "--")
const query = args.join(" ").trim()

function fail(message, code = 1) {
  process.stderr.write(String(message || "youtube search failed") + "\n")
  process.exit(code)
}

function textOf(runs) {
  if (!runs)
    return ""
  if (typeof runs === "string")
    return runs
  if (typeof runs?.simpleText === "string")
    return runs.simpleText
  if (typeof runs?.content === "string")
    return runs.content
  if (Array.isArray(runs?.runs))
    return runs.runs.map((r) => r?.text || "").join("")
  if (Array.isArray(runs?.sources))
    return ""
  if (Array.isArray(runs))
    return runs.map((r) => (typeof r === "string" ? r : (r?.text || r?.content || ""))).join("")
  return ""
}

function pickThumb(thumbnails) {
  let list = []
  if (Array.isArray(thumbnails))
    list = thumbnails
  else if (Array.isArray(thumbnails?.thumbnails))
    list = thumbnails.thumbnails
  else if (Array.isArray(thumbnails?.sources))
    list = thumbnails.sources
  if (list.length === 0)
    return ""
  let best = list[0]
  for (const t of list) {
    const w = Number(t?.width || 0)
    const bw = Number(best?.width || 0)
    if (w >= bw)
      best = t
  }
  return String(best?.url || "").replace(/^\/\//, "https://")
}

// Qt Image often cannot decode YouTube AVIF/WebP variants served behind .jpg URLs.
// Canonical hqdefault.jpg is reliably image/jpeg.
function safeVideoThumb(videoId, fallback) {
  const id = String(videoId || "").trim()
  if (id)
    return "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg"
  const fb = String(fallback || "").trim()
  if (!fb)
    return ""
  const m = fb.match(/\/vi\/([^/]+)\//)
  if (m && m[1])
    return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
  return fb
}

function parseVideo(v) {
  const id = String(v?.videoId || "")
  if (!id)
    return null
  const title = textOf(v?.title) || id
  const channel = textOf(v?.ownerText) || textOf(v?.shortBylineText) || textOf(v?.longBylineText)
  const views = textOf(v?.viewCountText) || textOf(v?.shortViewCountText)
  const published = textOf(v?.publishedTimeText)
  const length = textOf(v?.lengthText)
  const badges = []
  for (const b of v?.badges || []) {
    const label = textOf(b?.metadataBadgeRenderer?.label) || String(b?.metadataBadgeRenderer?.style || "")
    if (label)
      badges.push(label)
  }
  const isLive = badges.some((b) => /live/i.test(b)) || Boolean(v?.badges?.some?.((b) => /LIVE/i.test(String(b?.metadataBadgeRenderer?.label || ""))))
  const detailParts = [channel, views, published, length].filter(Boolean)
  return {
    type: isLive ? "live" : "video",
    id,
    title,
    channel,
    detail: detailParts.join(" · "),
    url: `https://www.youtube.com/watch?v=${id}`,
    thumbnail: safeVideoThumb(id, pickThumb(v?.thumbnail?.thumbnails)),
  }
}

function parseShort(r) {
  const id = String(r?.videoId || r?.onTap?.innertubeCommand?.reelWatchEndpoint?.videoId || "")
  if (!id)
    return null
  const title = textOf(r?.headline) || textOf(r?.overlayMetadata?.primaryText) || id
  const views = textOf(r?.viewCountText) || textOf(r?.overlayMetadata?.secondaryText)
  const channel = textOf(r?.overlayMetadata?.secondaryText) || ""
  return {
    type: "short",
    id,
    title,
    channel,
    detail: ["Short", views || channel].filter(Boolean).join(" · "),
    url: `https://www.youtube.com/shorts/${id}`,
    thumbnail: safeVideoThumb(
      id,
      pickThumb(r?.thumbnail?.thumbnails || r?.navigationEndpoint?.reelWatchEndpoint?.thumbnail?.thumbnails)
    ),
  }
}

function parseChannel(c) {
  const id = String(c?.channelId || "")
  const handle = textOf(c?.subscriberCountText)
  const title = textOf(c?.title) || id
  if (!id && !title)
    return null
  const url =
    c?.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl
      ? `https://www.youtube.com${c.navigationEndpoint.browseEndpoint.canonicalBaseUrl}`
      : id
        ? `https://www.youtube.com/channel/${id}`
        : ""
  const subs = textOf(c?.subscriberCountText)
  const videos = textOf(c?.videoCountText)
  return {
    type: "channel",
    id: id || title,
    title,
    channel: title,
    detail: ["Channel", subs, videos].filter(Boolean).join(" · "),
    url,
    thumbnail: pickThumb(c?.thumbnail?.thumbnails),
  }
}

function walk(node, out, seen) {
  if (!node || typeof node !== "object")
    return

  if (node.videoRenderer) {
    const item = parseVideo(node.videoRenderer)
    if (item && !seen.has(`video:${item.id}`)) {
      seen.add(`video:${item.id}`)
      out.push(item)
    }
  }
  if (node.channelRenderer) {
    const item = parseChannel(node.channelRenderer)
    if (item && !seen.has(`channel:${item.id}`)) {
      seen.add(`channel:${item.id}`)
      out.push(item)
    }
  }
  if (node.reelItemRenderer) {
    const item = parseShort(node.reelItemRenderer)
    if (item && !seen.has(`short:${item.id}`)) {
      seen.add(`short:${item.id}`)
      out.push(item)
    }
  }
  if (node.shortsLockupViewModel) {
    const s = node.shortsLockupViewModel
    const id = String(
      s?.onTap?.innertubeCommand?.reelWatchEndpoint?.videoId
        || String(s?.entityId || "").replace(/^shorts-shelf-item-/, "")
        || ""
    )
    if (id && !seen.has(`short:${id}`)) {
      const title = textOf(s?.overlayMetadata?.primaryText)
        || String(s?.accessibilityText || "").replace(/\s*,\s*\d.*$/i, "").replace(/\s*-\s*play Short$/i, "").trim()
        || id
      const views = textOf(s?.overlayMetadata?.secondaryText)
      const thumb = pickThumb(s?.thumbnailViewModel?.thumbnailViewModel?.image?.sources)
        || pickThumb(s?.onTap?.innertubeCommand?.reelWatchEndpoint?.thumbnail?.thumbnails)
        || pickThumb(s?.thumbnail?.sources)
      seen.add(`short:${id}`)
      out.push({
        type: "short",
        id,
        title,
        channel: "",
        detail: ["Short", views].filter(Boolean).join(" · "),
        url: `https://www.youtube.com/shorts/${id}`,
        thumbnail: safeVideoThumb(id, thumb),
      })
    }
  }
  if (node.gridVideoRenderer) {
    const item = parseVideo(node.gridVideoRenderer)
    if (item && !seen.has(`video:${item.id}`)) {
      seen.add(`video:${item.id}`)
      out.push(item)
    }
  }
  if (node.compactVideoRenderer) {
    const item = parseVideo(node.compactVideoRenderer)
    if (item && !seen.has(`video:${item.id}`)) {
      seen.add(`video:${item.id}`)
      out.push(item)
    }
  }
  if (node.richItemRenderer?.content)
    walk(node.richItemRenderer.content, out, seen)

  if (Array.isArray(node)) {
    for (const child of node)
      walk(child, out, seen)
    return
  }

  for (const key of Object.keys(node)) {
    if (key === "videoRenderer" || key === "channelRenderer" || key === "reelItemRenderer"
        || key === "shortsLockupViewModel" || key === "gridVideoRenderer" || key === "compactVideoRenderer")
      continue
    walk(node[key], out, seen)
  }
}

function extractResults(initialData) {
  const out = []
  const seen = new Set()
  walk(initialData, out, seen)
  return out.slice(0, MAX_RESULTS)
}

async function dismissConsent(page) {
  try {
    const buttons = [
      'button[aria-label*="Accept"]',
      'button[aria-label*="Accept all"]',
      'button[aria-label*="Agree"]',
      'tp-yt-paper-button[aria-label*="Accept"]',
      'form[action*="consent"] button',
    ]
    for (const sel of buttons) {
      const el = await page.$(sel)
      if (el) {
        await el.click().catch(() => {})
        await new Promise((r) => setTimeout(r, 400))
        break
      }
    }
  } catch {
    // ignore consent failures
  }
}

async function main() {
  if (!query) {
    process.stdout.write(JSON.stringify({ query: "", results: [] }) + "\n")
    return
  }

  const searchUrl = "https://www.youtube.com/results?search_query=" + encodeURIComponent(query)

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
    const page = await browser.newPage()
    await page.setViewport({ width: 1400, height: 900 })
    await page.setUserAgent(
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    await page.setExtraHTTPHeaders({ "Accept-Language": "en-US,en;q=0.9" })
    await page.setCookie({
      name: "CONSENT",
      value: "YES+cb.20210328-17-p0.en+FX+000",
      domain: ".youtube.com",
      path: "/",
    })

    await page.goto(searchUrl, { waitUntil: "domcontentloaded", timeout: 45000 })
    await dismissConsent(page)
    await page.waitForFunction(
      () => Boolean(window.ytInitialData) || document.querySelector("ytd-video-renderer, ytd-channel-renderer, ytd-reel-item-renderer"),
      { timeout: 20000 }
    ).catch(() => {})

    // Give lazy shelves a moment to hydrate.
    await new Promise((r) => setTimeout(r, 800))
    await page.evaluate(() => window.scrollBy(0, 1200)).catch(() => {})
    await new Promise((r) => setTimeout(r, 500))

    const initialData = await page.evaluate(() => {
      if (window.ytInitialData)
        return window.ytInitialData
      const scripts = Array.from(document.querySelectorAll("script"))
      for (const s of scripts) {
        const text = s.textContent || ""
        const marker = "var ytInitialData = "
        const i = text.indexOf(marker)
        if (i < 0)
          continue
        const start = i + marker.length
        const end = text.indexOf("};", start)
        if (end < 0)
          continue
        try {
          return JSON.parse(text.slice(start, end + 1))
        } catch {
          // continue
        }
      }
      return null
    })

    let results = initialData ? extractResults(initialData) : []

    // DOM fallback if ytInitialData is empty/blocked.
    if (results.length === 0) {
      results = await page.evaluate(() => {
        const out = []
        const seen = new Set()

        function push(item) {
          const key = `${item.type}:${item.id}`
          if (!item.id || seen.has(key))
            return
          seen.add(key)
          out.push(item)
        }

        for (const el of document.querySelectorAll("ytd-video-renderer, ytd-rich-item-renderer ytd-video-renderer")) {
          const a = el.querySelector("a#video-title, a#thumbnail")
          const href = a?.href || ""
          const idMatch = href.match(/[?&]v=([^&]+)/) || href.match(/\/shorts\/([^/?]+)/)
          const id = idMatch?.[1] || ""
          const title = (el.querySelector("#video-title")?.textContent || "").trim()
          const channel = (el.querySelector("#channel-name, ytd-channel-name")?.textContent || "").trim()
          const thumb = el.querySelector("img")?.src || ""
          const meta = Array.from(el.querySelectorAll("#metadata-line span, #metadata-line yt-formatted-string"))
            .map((n) => (n.textContent || "").trim())
            .filter(Boolean)
            .join(" · ")
          if (!id)
            continue
          const isShort = /\/shorts\//.test(href)
          push({
            type: isShort ? "short" : "video",
            id,
            title: title || id,
            channel,
            detail: [channel, meta].filter(Boolean).join(" · "),
            url: isShort ? `https://www.youtube.com/shorts/${id}` : `https://www.youtube.com/watch?v=${id}`,
            thumbnail: safeVideoThumb(id, thumb),
          })
        }

        for (const el of document.querySelectorAll("ytd-channel-renderer")) {
          const a = el.querySelector("a#main-link, a.channel-link")
          const href = a?.href || ""
          const title = (el.querySelector("#text.ytd-channel-name, #channel-title")?.textContent || "").trim()
          const thumb = el.querySelector("img")?.src || ""
          const id = href || title
          push({
            type: "channel",
            id,
            title: title || id,
            channel: title,
            detail: "Channel",
            url: href,
            thumbnail: thumb,
          })
        }

        for (const el of document.querySelectorAll("ytd-reel-item-renderer, ytm-shorts-lockup-view-model")) {
          const a = el.querySelector("a")
          const href = a?.href || ""
          const idMatch = href.match(/\/shorts\/([^/?]+)/)
          const id = idMatch?.[1] || ""
          const title = (el.querySelector("#video-title, span")?.textContent || "").trim()
          const thumb = el.querySelector("img")?.src || ""
          if (!id)
            continue
          push({
            type: "short",
            id,
            title: title || id,
            channel: "",
            detail: "Short",
            url: `https://www.youtube.com/shorts/${id}`,
            thumbnail: safeVideoThumb(id, thumb),
          })
        }

        return out.slice(0, 40)
      })
    }

    process.stdout.write(JSON.stringify({ query, results }) + "\n")
  } catch (err) {
    fail(err?.stack || err?.message || String(err))
  } finally {
    if (browser)
      await browser.close().catch(() => {})
  }
}

main()
