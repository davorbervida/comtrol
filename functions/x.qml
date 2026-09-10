pragma Singleton
import Quickshell
import QtQuick

// X search via shared WebBrowser daemon.
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
    if (t === "user")
      return "󰀄"
    if (t === "tweet" || t === "post")
      return "󰕄"
    return "𝕏"
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
      root.webListed(root.cachedResults.slice())
      return serial
    }

    root.reqId = WebBrowser.search("x", q)
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
      if (provider !== "x")
        return
      if (reqId !== root.reqId || root.reqId === 0)
        return
      root.reqId = 0
      if (!ok) {
        var err = String(error || "X search failed")
        var errLines = err.split("\n")
        root.webFailed(errLines[errLines.length - 1] || err)
        return
      }
      root.cachedResults = results || []
      root.cachedQuery = root.webQuery.trim()
      root.webListed(root.cachedResults)
    }
  }
}
