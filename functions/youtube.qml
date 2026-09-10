pragma Singleton
import Quickshell
import QtQuick

// YouTube search via shared WebBrowser daemon.
Item {
  id: root

  property int webSerial: 0
  property int reqId: 0
  property string webQuery: ""
  property var cachedResults: []
  property string cachedQuery: ""

  signal webListed(var results)
  signal webFailed(string message)

  function cancel() {
    root.webSerial += 1
    root.reqId = 0
  }

  function iconForType(type) {
    var t = String(type || "")
    if (t === "channel")
      return "󰡉"
    if (t === "short")
      return "󰎁"
    if (t === "live")
      return "󰐻"
    return "󰗃"
  }

  // Prefer JPEG thumbnails — YouTube often serves AVIF/WebP on hq720 URLs.
  function safeThumbnail(item) {
    var id = String((item && item.id) || "").trim()
    var type = String((item && item.type) || "")
    if (id && type !== "channel")
      return "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg"
    var thumb = String((item && item.thumbnail) || "").trim()
    var m = thumb.match(/\/vi\/([^/]+)\//)
    if (m && m[1])
      return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
    return thumb
  }

  function normalizeResults(results) {
    var list = results || []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      out.push({
        type: item.type,
        id: item.id,
        title: item.title,
        channel: item.channel,
        detail: item.detail,
        url: item.url,
        thumbnail: root.safeThumbnail(item)
      })
    }
    return out
  }

  function searchWeb(query) {
    root.webSerial += 1
    root.webQuery = String(query || "")
    var serial = root.webSerial

    var q = root.webQuery.trim()
    if (!q) {
      root.reqId = 0
      root.cachedResults = []
      root.cachedQuery = ""
      root.webListed([])
      return serial
    }

    if (root.cachedQuery === q && root.cachedResults && root.cachedResults.length > 0) {
      root.reqId = 0
      root.webListed(root.normalizeResults(root.cachedResults))
      return serial
    }

    root.reqId = WebBrowser.search("youtube", q)
    return serial
  }

  function open(url) {
    var u = String(url || "").trim()
    if (!u)
      return false
    Quickshell.execDetached(["xdg-open", u])
    return true
  }

  Connections {
    target: WebBrowser
    function onReply(provider, reqId, ok, results, error) {
      if (provider !== "youtube")
        return
      if (reqId !== root.reqId || root.reqId === 0)
        return
      root.reqId = 0
      if (!ok) {
        var err = String(error || "YouTube search failed")
        var errLines = err.split("\n")
        root.webFailed(errLines[errLines.length - 1] || err)
        return
      }
      var normalized = root.normalizeResults(results)
      root.cachedResults = normalized
      root.cachedQuery = root.webQuery.trim()
      root.webListed(normalized)
    }
  }
}
