// Decisions the widget makes about workspaces, kept free of Qt so that
// tests/logic.test.js can run them under Node. Workspaces.qml imports this
// file as `Logic`.

// Hyprland names a special workspace "special:<name>". The bar shows the part
// after the prefix, and the toggle dispatcher takes it too.
var SPECIAL_PREFIX = "special:"

function specialName(name) {
  var text = String(name || "")
  return text.indexOf(SPECIAL_PREFIX) === 0 ? text.substring(SPECIAL_PREFIX.length) : text
}

// The ids to draw, from Hyprland's workspace list: regular workspaces by id
// (the order Hyprland keeps them in, and the one a renumbering script
// maintains), then special ones by name. A workspace Quickshell has only
// half-created (id 0) is skipped until it is complete.
function entries(workspaces, showSpecial) {
  var list = Array.isArray(workspaces) ? workspaces : []
  var normal = []
  var special = []
  for (var i = 0; i < list.length; i++) {
    var ws = list[i]
    if (!ws) continue
    var id = Number(ws.id)
    if (!isFinite(id) || id === 0) continue
    if (id > 0) {
      if (normal.indexOf(id) === -1) normal.push(id)
    } else if (showSpecial !== false && special.indexOf(id) === -1) {
      special.push({ id: id, name: specialName(ws.name) })
    }
  }
  normal.sort(function(a, b) { return a - b })
  special.sort(function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) })
  return {
    normal: normal,
    special: special.map(function(s) { return s.id })
  }
}

// What a workspace's button says. A workspace Hyprland has not renamed is
// named after its id, so that is shown as the plain number. On a vertical bar
// only a number fits, so regular workspaces show their id and special ones
// their first letter; the full name is in the tooltip and the preview.
function label(id, name, showNumbers, vertical) {
  var n = Number(id)
  var text = n < 0 ? specialName(name) : String(name || "")
  var named = text !== "" && text !== String(n)
  if (vertical) return n < 0 ? (text.charAt(0).toUpperCase() || "S") : String(n)
  if (!named) return String(n)
  if (showNumbers && n > 0) return n + " " + text
  return text
}

// The full name, for the tooltip and the preview header.
function title(id, name) {
  var n = Number(id)
  var text = n < 0 ? specialName(name) : String(name || "")
  if (text === "" || text === String(n)) return "Workspace " + n
  return n > 0 ? n + " · " + text : text
}

// The workspace one step along `ids` from `current`, wrapping round.
function neighbour(ids, current, step) {
  var list = Array.isArray(ids) ? ids : []
  if (list.length === 0) return 0
  var at = list.indexOf(current)
  if (at === -1) return step > 0 ? list[0] : list[list.length - 1]
  var next = (at + step) % list.length
  if (next < 0) next += list.length
  return list[next]
}

function previewMode(value) {
  var mode = String(value || "")
  return mode === "capture" || mode === "icons" || mode === "off" ? mode : "capture"
}

// A monitor in logical pixels. Hyprland reports a monitor's size in physical
// pixels but window positions in logical ones, so at a scale of 1.5 the
// physical size would squash every window into two thirds of the preview.
function logicalMonitor(monitor) {
  if (!monitor || typeof monitor !== "object") return null
  var scale = Number(monitor.scale)
  if (!isFinite(scale) || scale <= 0) scale = 1
  var w = Math.round((Number(monitor.width) || 0) / scale)
  var h = Math.round((Number(monitor.height) || 0) / scale)
  var rotated = (Math.floor(Number(monitor.transform) || 0) % 2) === 1
  return {
    x: Number(monitor.x) || 0,
    y: Number(monitor.y) || 0,
    width: rotated ? h : w,
    height: rotated ? w : h
  }
}

// `at` and `size` are JS arrays under Node but Qt array-likes in QML, so test
// for an indexable pair rather than Array.isArray.
function isPair(value) {
  return value !== null && value !== undefined && typeof value === "object"
    && Number(value.length) >= 2 && value[0] !== undefined && value[1] !== undefined
}

// The windows a preview draws, from `hyprctl clients` objects: mapped,
// visible and with a size, tiled before floating so floating ones are drawn
// on top, and at most `limit` of them so a crowded workspace can't stall the
// bar with captures.
function previewLayout(clients, limit) {
  var list = Array.isArray(clients) ? clients : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c || !isPair(c.at) || !isPair(c.size)) continue
    if (c.hidden || c.mapped === false) continue
    var w = Number(c.size[0])
    var h = Number(c.size[1])
    if (!(w > 0) || !(h > 0)) continue
    out.push({
      address: String(c.address || ""),
      x: Number(c.at[0]) || 0,
      y: Number(c.at[1]) || 0,
      width: w,
      height: h,
      floating: !!c.floating,
      cls: String(c["class"] || ""),
      title: String(c.title || "")
    })
  }
  out.sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
  var cap = Math.max(0, Math.floor(Number(limit) || 0))
  return cap > 0 ? out.slice(0, cap) : out
}

// Where the sliding pill goes: over the button for `id`, inset by `inset` on
// the bar's cross axis. `buttons` are {id, x, y, width, height}.
function pillGeometry(buttons, id, vertical, inset) {
  var list = Array.isArray(buttons) ? buttons : []
  for (var i = 0; i < list.length; i++) {
    var b = list[i]
    if (!b || b.id !== id || !(b.width > 0) || !(b.height > 0)) continue
    var pad = Math.max(0, Number(inset) || 0)
    if (vertical) return { visible: true, x: b.x + pad, y: b.y, width: Math.max(0, b.width - pad * 2), height: b.height }
    return { visible: true, x: b.x, y: b.y + pad, width: b.width, height: Math.max(0, b.height - pad * 2) }
  }
  return { visible: false, x: 0, y: 0, width: 0, height: 0 }
}

if (typeof module !== "undefined") {
  module.exports = {
    specialName: specialName,
    entries: entries,
    label: label,
    title: title,
    neighbour: neighbour,
    previewMode: previewMode,
    logicalMonitor: logicalMonitor,
    previewLayout: previewLayout,
    pillGeometry: pillGeometry
  }
}
