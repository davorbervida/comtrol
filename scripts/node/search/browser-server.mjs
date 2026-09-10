#!/usr/bin/env node
// Persistent Puppeteer browser for cOMtrol web search.
// Protocol: newline-delimited JSON on stdin → stdout.
//   → {"cmd":"search","id":1,"provider":"youtube","query":"..."}
//   ← {"id":1,"ok":true,"results":[...]} | {"id":1,"ok":false,"error":"..."}
//   → {"cmd":"shutdown"}
//   ← {"event":"ready"} once browser is up
// Exits on stdin EOF, shutdown, or parent process death.

import process from "node:process"
import puppeteer from "puppeteer"
import { LAUNCH_ARGS } from "./lib/common.mjs"
import * as youtube from "./youtube.mjs"
import * as reddit from "./reddit.mjs"
import * as google from "./google.mjs"
import * as duckduckgo from "./duckduckgo.mjs"
import * as x from "./x.mjs"
import * as wikipedia from "./wikipedia.mjs"

const PROVIDERS = {
  youtube: youtube.search,
  reddit: reddit.search,
  google: google.search,
  duckduckgo: duckduckgo.search,
  x: x.search,
  wikipedia: wikipedia.search,
}

const PARENT_PID = process.ppid
const PARENT_CHECK_MS = 2000

let browser = null
let shuttingDown = false
let stdinBuffer = ""
/** @type {Map<number|string, AbortController>} */
const inflight = new Map()

function reply(obj) {
  try {
    process.stdout.write(JSON.stringify(obj) + "\n")
  } catch {
    // ignore broken pipe
  }
}

function parentAlive() {
  if (!PARENT_PID || PARENT_PID <= 1)
    return true
  try {
    process.kill(PARENT_PID, 0)
    return true
  } catch {
    return false
  }
}

async function ensureBrowser() {
  if (browser && browser.connected)
    return browser
  browser = await puppeteer.launch({
    headless: true,
    args: LAUNCH_ARGS,
  })
  browser.on("disconnected", () => {
    browser = null
  })
  return browser
}

async function shutdown(code = 0) {
  if (shuttingDown)
    return
  shuttingDown = true
  for (const [, ac] of inflight)
    ac.abort()
  inflight.clear()
  if (browser) {
    try {
      await browser.close()
    } catch {
      // ignore
    }
    browser = null
  }
  process.exit(code)
}

async function handleSearch(msg) {
  const id = msg.id
  const provider = String(msg.provider || "").trim()
  const query = String(msg.query || "")
  const fn = PROVIDERS[provider]
  if (!fn) {
    reply({ id, provider, ok: false, error: "Unknown provider: " + provider })
    return
  }
  const ac = new AbortController()
  inflight.set(id, ac)
  try {
    const b = await ensureBrowser()
    if (ac.signal.aborted)
      return
    const results = await fn(b, query)
    if (ac.signal.aborted)
      return
    reply({ id, provider, ok: true, results: results || [] })
  } catch (err) {
    if (ac.signal.aborted)
      return
    reply({
      id,
      provider,
      ok: false,
      error: String(err?.stack || err?.message || err),
    })
  } finally {
    inflight.delete(id)
  }
}

function handleLine(line) {
  const raw = String(line || "").trim()
  if (!raw)
    return
  let msg
  try {
    msg = JSON.parse(raw)
  } catch {
    reply({ ok: false, error: "Invalid JSON" })
    return
  }
  const cmd = String(msg.cmd || "")
  if (cmd === "shutdown" || cmd === "cool") {
    shutdown(0)
    return
  }
  if (cmd === "ping") {
    reply({ id: msg.id, ok: true, event: "pong", ready: Boolean(browser?.connected) })
    return
  }
  if (cmd === "search") {
    handleSearch(msg)
    return
  }
  reply({ id: msg.id, ok: false, error: "Unknown cmd: " + cmd })
}

function onStdinChunk(chunk) {
  stdinBuffer += String(chunk || "")
  let nl
  while ((nl = stdinBuffer.indexOf("\n")) >= 0) {
    const line = stdinBuffer.slice(0, nl)
    stdinBuffer = stdinBuffer.slice(nl + 1)
    handleLine(line)
  }
}

async function main() {
  process.stdin.setEncoding("utf8")
  process.stdin.on("data", onStdinChunk)
  process.stdin.on("end", () => { shutdown(0) })
  process.stdin.on("error", () => { shutdown(1) })
  process.on("SIGTERM", () => { shutdown(0) })
  process.on("SIGINT", () => { shutdown(0) })

  setInterval(() => {
    if (!parentAlive())
      shutdown(0)
  }, PARENT_CHECK_MS).unref()

  try {
    await ensureBrowser()
    reply({ event: "ready" })
  } catch (err) {
    reply({ event: "error", error: String(err?.message || err) })
    await shutdown(1)
  }
}

main()
