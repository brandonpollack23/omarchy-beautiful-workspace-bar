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

// Hyprland writes window addresses as "0x5dbe17026020"; Quickshell's
// HyprlandToplevel.address drops the "0x". Compare them in one form.
function address(value) {
  var text = String(value || "").toLowerCase()
  return text.indexOf("0x") === 0 ? text.substring(2) : text
}

// Everything the widget draws, from `hyprctl -j workspaces`, `monitors` and
// `clients`. Quickshell 0.3.1 has its own workspace objects, but it ignores
// `changeworkspaceid` and matches new workspaces by name, so once a script
// renumbers workspaces they can hold stale or duplicate ids. Hyprland's own
// answer is always right.
function hyprState(workspaces, monitors, clients) {
  var state = {
    workspaces: [],
    focusedId: 0,
    focusedMonitor: "",
    activeIds: [],
    // Active on a monitor other than the focused one: shown, but not focused.
    elsewhereIds: [],
    openSpecials: [],
    monitors: {},
    clients: [],
    windowWorkspace: {}
  }
  var ws = Array.isArray(workspaces) ? workspaces : []
  for (var i = 0; i < ws.length; i++) {
    var w = ws[i]
    if (!w) continue
    var id = Number(w.id)
    if (!isFinite(id) || id === 0) continue
    state.workspaces.push({
      id: id,
      name: String(w.name === undefined || w.name === null ? id : w.name),
      windows: Number(w.windows) || 0,
      monitor: String(w.monitor || "")
    })
  }
  var mons = Array.isArray(monitors) ? monitors : []
  for (var m = 0; m < mons.length; m++) {
    var mon = mons[m]
    if (!mon || mon.disabled) continue
    var name = String(mon.name || "")
    state.monitors[name] = {
      x: Number(mon.x) || 0,
      y: Number(mon.y) || 0,
      width: Number(mon.width) || 0,
      height: Number(mon.height) || 0,
      scale: Number(mon.scale) || 1,
      transform: Number(mon.transform) || 0
    }
    var active = mon.activeWorkspace ? Number(mon.activeWorkspace.id) : 0
    if (active > 0 && state.activeIds.indexOf(active) === -1) state.activeIds.push(active)
    if (mon.focused) {
      state.focusedMonitor = name
      state.focusedId = active > 0 ? active : 0
    } else if (active > 0 && state.elsewhereIds.indexOf(active) === -1) {
      state.elsewhereIds.push(active)
    }
    var special = mon.specialWorkspace ? String(mon.specialWorkspace.name || "") : ""
    if (special !== "" && state.openSpecials.indexOf(special) === -1) state.openSpecials.push(special)
  }
  var cl = Array.isArray(clients) ? clients : []
  for (var c = 0; c < cl.length; c++) {
    var client = cl[c]
    if (!client || !client.workspace) continue
    state.clients.push(client)
    state.windowWorkspace[address(client.address)] = Number(client.workspace.id) || 0
  }
  return state
}

// The workspaces to mark urgent: those holding a window that asked for
// attention (`urgent`, keyed by address), other than the focused one.
function urgentIds(urgent, windowWorkspace, focusedId) {
  var out = []
  for (var addr in urgent) {
    if (!urgent[addr]) continue
    var id = windowWorkspace ? windowWorkspace[addr] : undefined
    if (id === undefined || id === 0 || id === focusedId || out.indexOf(id) !== -1) continue
    out.push(id)
  }
  return out
}

// WCAG relative luminance of {r, g, b} with channels in 0..1.
function luminance(c) {
  function channel(v) {
    var x = Number(v) || 0
    return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

function contrast(a, b) {
  var la = luminance(a)
  var lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}


// Where a dragged workspace would land: how many of the other buttons'
// centres (along the bar, in order) lie before the point it is dragged to.
function dropIndex(centres, position) {
  var list = Array.isArray(centres) ? centres : []
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i] < position) n++
  return n
}

// The renumbering that moves workspace `fromId` to position `toIndex` among
// `ids` (sorted), as [from, to] id changes in order. The workspaces keep the
// same set of ids, so any gaps stay where they are. Every workspace that moves
// first goes to a temporary id above all of them, so no two ever share one.
function reorderPlan(ids, fromId, toIndex) {
  var list = Array.isArray(ids) ? ids.slice() : []
  list.sort(function(a, b) { return a - b })
  var at = list.indexOf(fromId)
  if (at === -1) return []
  var order = list.slice()
  order.splice(at, 1)
  var index = Math.max(0, Math.min(order.length, Math.floor(Number(toIndex) || 0)))
  order.splice(index, 0, fromId)
  var moves = []
  for (var i = 0; i < order.length; i++) {
    if (order[i] !== list[i]) moves.push({ from: order[i], to: list[i] })
  }
  if (moves.length === 0) return []
  var base = list[list.length - 1] + 1
  var steps = []
  for (var m = 0; m < moves.length; m++) steps.push([moves[m].from, base + m])
  for (var k = 0; k < moves.length; k++) steps.push([base + k, moves[k].to])
  return steps
}

// Hyprland's own way to give a workspace a new id. A config that keeps
// something per workspace id (saved layouts, say) can swap in a function of
// its own through the `renumberLua` setting.
var DEFAULT_RENUMBER = 'hl.dispatch(hl.dsp.workspace.change_id({ workspace = "{from}", id = {to} }))'

// One Lua chunk for `hyprctl eval` that runs `steps` through `template`,
// where {from} and {to} stand for the ids.
function renumberScript(steps, template) {
  var t = String(template || "").trim()
  if (t === "") t = DEFAULT_RENUMBER
  var lines = []
  var list = Array.isArray(steps) ? steps : []
  for (var i = 0; i < list.length; i++) {
    var from = Math.floor(Number(list[i][0]))
    var to = Math.floor(Number(list[i][1]))
    if (!isFinite(from) || !isFinite(to)) continue
    lines.push(t.split("{from}").join(String(from)).split("{to}").join(String(to)))
  }
  return lines.join("\n")
}

// The id a new workspace at the end of the bar gets.
function nextId(ids) {
  var list = Array.isArray(ids) ? ids : []
  var max = 0
  for (var i = 0; i < list.length; i++) if (list[i] > max) max = list[i]
  return max + 1
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
    pillGeometry: pillGeometry,
    address: address,
    hyprState: hyprState,
    urgentIds: urgentIds,
    contrast: contrast,
    dropIndex: dropIndex,
    reorderPlan: reorderPlan,
    renumberScript: renumberScript,
    nextId: nextId
  }
}
