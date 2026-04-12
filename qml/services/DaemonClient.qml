pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * DaemonClient — Singleton that connects to skwd-daemon over Unix socket.
 *
 * Protocol: JSON Lines over $XDG_RUNTIME_DIR/skwd/daemon.sock
 * Events use the skwd.wall.* namespace.
 *
 * Services should use call() for RPC and connect to eventReceived for push events.
 */
QtObject {
    id: client

    // ── Connection state ──────────────────────────────
    readonly property bool connected: _socket.connected
    property bool ready: false

    // ── Cache state (from daemon events) ──────────────
    property bool cacheRunning: false
    property int cacheProgress: 0
    property int cacheTotal: 0

    // ── Signals ───────────────────────────────────────

    // Generic event — all daemon-pushed events fire through here.
    // Services filter by event name in their own Connections block.
    signal eventReceived(string event, var data)

    // File watcher events
    signal fileAdded(string name, string path, string type)
    signal fileRemoved(string name, string type)
    signal fileRenamed(string oldName, string newName)
    signal folderRemoved(var names)
    signal weItemAdded(string weId, string weDir)
    signal weItemRemoved(string weId)
    signal scanDone()

    // Cache events
    signal cacheReady()
    signal itemCached(var data)

    // Wallpaper events
    signal wallpaperApplied(string type, string name, string path, string weId)
    signal wallpaperToggle()
    signal wallpaperShow()
    signal wallpaperHide()

    // ── Public API ────────────────────────────────────

    function call(method, params, callback) {
        if (!_socket.connected) {
            if (callback) callback(null, {code: -1, message: "not connected"})
            return
        }
        var id = _nextId++
        if (callback) _pending[id] = { cb: callback, ts: Date.now() }
        var line = JSON.stringify({method: method, params: params || {}, id: id})
        _socket.write(line + "\n")
        _socket.flush()
    }

    // Convenience wrappers
    function subscribe(events) { call("subscribe", {events: events}) }
    function status(callback)  { call("status", {}, callback) }

    function toggle() { call("wall.toggle", {}) }
    function show()   { call("wall.show", {}) }
    function hide()   { call("wall.hide", {}) }

    function applyStatic(path, callback) {
        call("wall.apply", {type: "static", path: path}, callback)
    }
    function applyVideo(path, callback) {
        call("wall.apply", {type: "video", path: path}, callback)
    }
    function applyWE(weId, screens, callback) {
        call("wall.apply", {type: "we", we_id: weId, screens: screens || []}, callback)
    }
    function restore(callback) { call("wall.restore", {}, callback) }

    function rebuildCache(callback)    { call("wall.cache_rebuild", {}, callback) }
    function clearData(callback)       { call("wall.clear_data", {}, callback) }
    function cacheStatus(callback)     { call("wall.cache_status", {}, callback) }

    function listWallpapers(favouritesOnly, callback) {
        call("wall.list", {favourites: !!favouritesOnly}, callback)
    }
    function setFavourite(key, favourite, callback) {
        call("wall.set_favourite", {key: key, favourite: favourite}, callback)
    }
    function updateAnalysis(key, tags, colors, analyzedBy, hue, sat, callback) {
        var params = {key: key}
        if (tags !== undefined && tags !== null) params.tags = JSON.stringify(tags)
        if (colors !== undefined && colors !== null) params.colors = JSON.stringify(colors)
        if (analyzedBy) params.analyzed_by = analyzedBy
        if (hue !== undefined && hue !== null) params.hue = hue
        if (sat !== undefined && sat !== null) params.sat = sat
        call("wall.update_analysis", params, callback)
    }
    function importFromQml(callback) { call("wall.import", {}, callback) }
    function deleteItem(name, type, weId, callback) {
        var params = {name: name, type: type || "static"}
        if (weId) params.we_id = weId
        call("wall.delete", params, callback)
    }
    function setMatugen(key, matugenJson, callback) {
        call("wall.set_matugen", {key: key, matugen: matugenJson}, callback)
    }
    function setMatugenBatch(entries, callback) {
        call("wall.set_matugen_batch", {entries: entries}, callback)
    }

    function fetchWeather(callback) {
        call("wall.weather", {}, callback)
    }

    // ── Private implementation ────────────────────────

    property int _nextId: 1
    property var _pending: ({})

    function _handleLine(line) {
        line = line.trim()
        if (!line) return

        var msg
        try { msg = JSON.parse(line) }
        catch (e) { console.warn("DaemonClient: invalid JSON:", line); return }

        if (msg.event) {
            _handleEvent(msg.event, msg.data || {})
            return
        }

        if (msg.id !== undefined) {
            var entry = _pending[msg.id]
            if (entry) {
                delete _pending[msg.id]
                if (msg.error) entry.cb(null, msg.error)
                else entry.cb(msg.result, null)
            }
        }
    }

    function _handleEvent(event, data) {
        // Generic signal — services listen on this
        client.eventReceived(event, data)

        // Typed signals for backward compatibility
        switch (event) {
        case "skwd.wall.file_added":
            client.fileAdded(data.name || "", data.path || "", data.type || "static"); break
        case "skwd.wall.file_removed":
            client.fileRemoved(data.name || "", data.type || "static"); break
        case "skwd.wall.file_renamed":
            client.fileRenamed(data.old_name || "", data.new_name || ""); break
        case "skwd.wall.folder_removed":
            client.folderRemoved(data.names || []); break
        case "skwd.wall.we_added":
            client.weItemAdded(data.we_id || "", data.we_dir || ""); break
        case "skwd.wall.we_removed":
            client.weItemRemoved(data.we_id || ""); break
        case "skwd.wall.scan_done":
            client.scanDone(); break
        case "skwd.wall.cache":
            client.cacheRunning = (data.status === "started" || data.status === "progress")
            client.cacheProgress = data.progress || 0
            client.cacheTotal = data.total || 0
            if (data.status === "ready") client.cacheReady()
            break
        case "skwd.wall.cached":
            client.itemCached(data); break
        case "skwd.wall.applied":
            client.wallpaperApplied(data.type || "", data.name || "", data.path || "", data.we_id || ""); break
        case "skwd.wall.toggle":
            client.wallpaperToggle(); break
        case "skwd.wall.show":
            client.wallpaperShow(); break
        case "skwd.wall.hide":
            client.wallpaperHide(); break
        }
    }

    // ── Socket ────────────────────────────────────────

    property var _socket: Socket {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/skwd/daemon.sock"

        connected: false

        parser: SplitParser {
            onRead: data => client._handleLine(data)
        }

        onConnectionStateChanged: {
            if (connected) {
                console.log("DaemonClient: connected")
                client.subscribe(["skwd."])
                client.ready = true
            } else {
                console.log("DaemonClient: disconnected")
                client.ready = false
                client._pending = {}
                client._reconnectTimer.restart()
            }
        }
    }

    property var _reconnectTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (!client.connected)
                client._socket.connected = true
        }
    }

    // Expire stale pending callbacks after 30s
    property var _cleanupTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            var now = Date.now()
            var stale = []
            for (var id in client._pending) {
                if (now - client._pending[id].ts > 30000) stale.push(id)
            }
            for (var i = 0; i < stale.length; i++) {
                var entry = client._pending[stale[i]]
                delete client._pending[stale[i]]
                if (entry && entry.cb) entry.cb(null, {code: -2, message: "timeout"})
            }
        }
    }

    Component.onCompleted: {
        _socket.connected = true
    }
}
