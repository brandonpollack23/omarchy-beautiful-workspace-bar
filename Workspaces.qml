import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Every Hyprland workspace, by the name Hyprland gives it, with an accent pill
// that slides to the focused one. Nothing is stored: the names are
// Hyprland's own (`hl.dsp.workspace.rename`), so renaming a workspace from a
// script or a keybinding shows up here at once.
//
//   left-click     go to the workspace (a special one is toggled)
//   middle-click   send the focused window there, without following it
//   scroll         previous / next workspace
//   hover          preview of the windows on it
BarWidget {
  id: root
  moduleName: "io.github.brandonpollack23.beautiful-workspace-bar"

  readonly property bool showSpecial: root.setting("showSpecial", true) !== false
  readonly property bool showNumbers: root.setting("showNumbers", false) === true
  readonly property string previewMode: Logic.previewMode(root.setting("previewMode", "capture"))

  // Theme. The bar's own colors where the host passes them, else the palette.
  readonly property color ink: root.bar ? root.bar.barForeground : Color.bar.text
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color onAccent: Color.background
  readonly property string fontFamily: root.bar && root.bar.fontFamily !== "" ? root.bar.fontFamily : Style.font.family

  // The pill sits this far in from the bar's edges, and a button is never
  // narrower than the pill is tall, so a one-digit workspace gets a circle.
  readonly property int pillInset: Math.max(2, Math.round(root.barSize * 0.16))
  readonly property int pillThickness: Math.max(0, root.barSize - root.pillInset * 2)
  readonly property real buttonPadding: Style.spaceReal(9)

  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

  // Which workspaces to draw. Only ids (and, for special workspaces, names)
  // are read here, so renaming a regular workspace does not rebuild the
  // buttons; each button follows its own workspace's name. The lists are only
  // replaced when they really change, since a Repeater recreates every button
  // when its model is set.
  readonly property var computedEntries: {
    var values = Hyprland.workspaces.values
    var list = []
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      list.push({ id: id, name: id < 0 ? values[i].name : "" })
    }
    return Logic.entries(list, root.showSpecial)
  }

  property var normalIds: []
  property var specialIds: []

  function syncEntries() {
    var next = root.computedEntries
    if (JSON.stringify(next.normal) !== JSON.stringify(root.normalIds)) {
      root.pillAnimates = false
      root.normalIds = next.normal
      pillSettle.restart()
    }
    if (JSON.stringify(next.special) !== JSON.stringify(root.specialIds)) root.specialIds = next.special
  }

  onComputedEntriesChanged: root.syncEntries()
  Component.onCompleted: {
    root.syncEntries()
    root.loadOpenSpecials()
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function hasWindows(id) {
    var ws = root.workspaceById(id)
    return ws !== null && ws.toplevels.values.length > 0
  }

  // Keeping up with Hyprland: Quickshell 0.3 doesn't follow
  // `changeworkspaceid`, which `hl.dsp.workspace.change_id` sends. A
  // renumbering sends a burst of them, and Quickshell drops a refresh asked
  // for while one is running, so refresh once the burst is over and once more
  // after that.
  Timer {
    id: resyncTimer
    interval: 30
    onTriggered: {
      Hyprland.refreshWorkspaces()
      resyncSettle.restart()
    }
  }

  Timer {
    id: resyncSettle
    interval: 150
    onTriggered: {
      Hyprland.refreshWorkspaces()
      Hyprland.refreshMonitors()
      Hyprland.refreshToplevels()
    }
  }

  // Window geometry and class only arrive with `hyprctl clients`.
  Timer {
    id: toplevelRefresh
    interval: 40
    onTriggered: Hyprland.refreshToplevels()
  }

  // Special workspaces shown on each monitor, by monitor name.
  property var openSpecials: ({})

  function loadOpenSpecials() {
    var open = {}
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var ipc = monitors[i].lastIpcObject
      var special = ipc && ipc.specialWorkspace ? String(ipc.specialWorkspace.name || "") : ""
      if (special !== "") open[monitors[i].name] = special
    }
    root.openSpecials = open
  }

  function isSpecialOpen(name) {
    for (var monitor in root.openSpecials) {
      if (root.openSpecials[monitor] === name) return true
    }
    return false
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = String(event.name || "")
      if (name === "changeworkspaceid") {
        resyncTimer.restart()
      } else if (name === "activespecial") {
        // "<workspace>,<monitor>", the workspace empty when it was closed.
        var data = String(event.data || "")
        var comma = data.lastIndexOf(",")
        var open = {}
        for (var key in root.openSpecials) open[key] = root.openSpecials[key]
        var workspace = data.substring(0, comma)
        var monitor = data.substring(comma + 1)
        if (workspace === "") delete open[monitor]
        else open[monitor] = workspace
        root.openSpecials = open
      } else if (name === "openwindow" || name === "closewindow" || name === "movewindowv2"
          || name === "changefloatingmode" || name === "fullscreen") {
        toplevelRefresh.restart()
      }
    }
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // Lua long brackets, so a workspace name needs no escaping.
  function luaString(text) {
    return "[==[" + String(text) + "]==]"
  }

  function activate(id) {
    if (id > 0) {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
      return
    }
    var ws = root.workspaceById(id)
    if (ws) root.dispatch("hl.dsp.workspace.toggle_special(" + root.luaString(Logic.specialName(ws.name)) + ")")
  }

  function sendFocusedWindow(id) {
    var target = String(id)
    if (id < 0) {
      var ws = root.workspaceById(id)
      if (!ws) return
      target = ws.name
    }
    root.dispatch("hl.dsp.window.move({ workspace = " + root.luaString(target) + ", follow = false })")
  }

  property int wheelAccum: 0

  function handleWheel(delta) {
    root.wheelAccum += delta
    while (root.wheelAccum >= 120) { root.wheelAccum -= 120; root.step(-1) }
    while (root.wheelAccum <= -120) { root.wheelAccum += 120; root.step(1) }
  }

  function step(direction) {
    var next = Logic.neighbour(root.normalIds, root.focusedId, direction)
    if (next > 0) root.activate(next)
  }

  // Hover preview. Opens after a short hover; once open, moving to the next
  // button swaps it at once, and leaving only closes it after a moment, so
  // sweeping along the bar doesn't flicker.
  property int hoverId: 0
  property int pendingId: 0
  property Item hoverAnchor: null
  property Item pendingAnchor: null

  function requestPreview(id, anchor) {
    if (root.previewMode === "off" || !root.hasWindows(id)) return
    toplevelRefresh.restart()
    previewHide.stop()
    root.pendingId = id
    root.pendingAnchor = anchor
    if (root.hoverId !== 0) root.showPending()
    else previewDelay.restart()
  }

  function cancelPreview(id) {
    if (root.pendingId === id) {
      previewDelay.stop()
      root.pendingId = 0
    }
    if (root.hoverId === id) previewHide.restart()
  }

  function hidePreview() {
    previewDelay.stop()
    previewHide.stop()
    root.pendingId = 0
    root.hoverId = 0
  }

  function showPending() {
    if (root.pendingId === 0) return
    root.hoverAnchor = root.pendingAnchor
    root.hoverId = root.pendingId
    if (root.hoverAnchor && typeof root.hoverAnchor.hideOwnTooltip === "function")
      root.hoverAnchor.hideOwnTooltip()
  }

  Timer { id: previewDelay; interval: 350; onTriggered: root.showPending() }
  Timer { id: previewHide; interval: 120; onTriggered: root.hoverId = 0 }

  // A workspace that goes away (or is renumbered) under an open preview
  // closes it rather than leaving it pointing at nothing.
  onNormalIdsChanged: if (root.hoverId > 0 && root.normalIds.indexOf(root.hoverId) === -1) root.hidePreview()

  // The workspace the card shows. It outlives `hoverId` while the card fades
  // out, and is cleared once the card is hidden, so hovering the same
  // workspace again takes fresh screenshots.
  property int shownId: 0
  onHoverIdChanged: {
    if (root.hoverId !== 0) root.shownId = root.hoverId
    else if (!previewCard.visible) root.shownId = 0
  }

  readonly property var previewWorkspace: root.shownId !== 0 ? root.workspaceById(root.shownId) : null

  // A special workspace that has never been shown has no monitor; fall back
  // to the focused one.
  readonly property var previewMonitor: {
    if (root.shownId === 0) return null
    var ws = root.previewWorkspace
    return ws && ws.monitor ? ws.monitor : Hyprland.focusedMonitor
  }

  readonly property var previewScreen: {
    var m = root.previewMonitor
    if (!m) return null
    return Logic.logicalMonitor({
      x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale,
      transform: m.lastIpcObject ? m.lastIpcObject.transform : 0
    })
  }

  // Only each window's `hyprctl clients` snapshot is read, never
  // `toplevel.workspace` (placeholder objects at startup have crashed the shell).
  readonly property var previewWindows: {
    if (root.shownId === 0) return []
    var all = Hyprland.toplevels.values
    var snapshots = []
    var toplevels = []
    for (var i = 0; i < all.length; i++) {
      var ipc = all[i].lastIpcObject
      if (ipc && ipc.workspace && Number(ipc.workspace.id) === root.shownId) {
        snapshots.push(ipc)
        toplevels.push(all[i])
      }
    }
    var layout = Logic.previewLayout(snapshots, 12)
    for (var k = 0; k < layout.length; k++) {
      for (var t = 0; t < toplevels.length; t++) {
        if (String(toplevels[t].lastIpcObject.address || "") === layout[k].address) {
          layout[k].toplevel = toplevels[t]
          break
        }
      }
    }
    return layout
  }

  function iconFor(cls) {
    var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
    var name = entry && entry.icon ? entry.icon : ""
    var path = name !== "" ? Quickshell.iconPath(name, true) : ""
    return path !== "" ? path : Quickshell.iconPath("application-x-executable", true)
  }

  // What the preview card reports as its owner, so the bar can close it when
  // another popout opens.
  readonly property QtObject hoverOwner: QtObject {
    function close() { root.hidePreview() }
  }

  PreviewCard { id: previewCard; host: root }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + root.trailingGap
  implicitHeight: grid.implicitHeight

  // Off while the buttons are rebuilt, so the pill jumps to its new place
  // instead of sliding in from where the old buttons were.
  property bool pillAnimates: false

  Timer { id: pillSettle; interval: 120; running: true; onTriggered: root.pillAnimates = true }

  function buttonGeometry() {
    var out = []
    for (var i = 0; i < normalRepeater.count; i++) {
      var item = normalRepeater.itemAt(i)
      if (item) out.push({ id: item.workspaceId, x: item.x, y: item.y, width: item.width, height: item.height })
    }
    return out
  }

  // Declared before the grid so it is drawn under the buttons' text.
  Rectangle {
    id: pill
    readonly property var geo: Logic.pillGeometry(root.buttonGeometry(), root.focusedId, root.vertical, root.pillInset)
    x: geo.x
    y: geo.y
    width: geo.width
    height: geo.height
    visible: geo.visible
    radius: Math.min(width, height) / 2
    color: root.accent

    Behavior on x { enabled: root.pillAnimates; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    Behavior on y { enabled: root.pillAnimates; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    Behavior on width { enabled: root.pillAnimates; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: root.pillAnimates; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 200 } }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.normalIds.length + root.specialIds.length + (separator.visible ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: normalRepeater
      model: root.normalIds
      WorkspaceButton { required property int modelData; host: root; workspaceId: modelData }
    }

    Rectangle {
      id: separator
      visible: root.normalIds.length > 0 && root.specialIds.length > 0
      Layout.alignment: Qt.AlignCenter
      Layout.leftMargin: root.vertical ? 0 : Style.space(4)
      Layout.rightMargin: root.vertical ? 0 : Style.space(4)
      Layout.topMargin: root.vertical ? Style.space(4) : 0
      Layout.bottomMargin: root.vertical ? Style.space(4) : 0
      Layout.preferredWidth: root.vertical ? Math.round(root.barSize * 0.4) : Math.max(1, Style.space(1))
      Layout.preferredHeight: root.vertical ? Math.max(1, Style.space(1)) : Math.round(root.barSize * 0.4)
      radius: Math.min(width, height) / 2
      color: Util.alpha(root.ink, 0.3)
    }

    Repeater {
      model: root.specialIds
      WorkspaceButton { required property int modelData; host: root; workspaceId: modelData }
    }
  }

  // Scriptable, and how the README's screenshots are taken:
  //   omarchy-shell io.github.brandonpollack23.beautiful-workspace-bar preview 2
  IpcHandler {
    target: "io.github.brandonpollack23.beautiful-workspace-bar"

    function preview(id: string): void {
      var n = parseInt(id, 10) || 0
      root.hidePreview()
      if (n === 0 || !root.hasWindows(n)) return
      var anchor = null
      for (var i = 0; i < normalRepeater.count; i++) {
        var item = normalRepeater.itemAt(i)
        if (item && item.workspaceId === n) anchor = item
      }
      toplevelRefresh.restart()
      root.hoverAnchor = anchor ? anchor : grid
      root.hoverId = n
    }
    function unpreview(): void { root.hidePreview() }
    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
    function resync(): void { resyncTimer.restart() }
  }
}
