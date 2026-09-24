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
//   right-click    rename it
//   middle-click   send the focused window there, without following it
//   drag           move it along the bar (renumbers workspaces)
//   scroll         previous / next workspace
//   hover          preview of the windows on it
//   +              a new workspace at the end
//
// Each of these can be turned off in the widget's settings (manifest.json).
BarWidget {
  id: root
  moduleName: "io.github.brandonpollack23.beautiful-workspace-bar"

  readonly property bool showSpecial: root.setting("showSpecial", true) !== false
  readonly property bool showNumbers: root.setting("showNumbers", false) === true
  // `previewMode: "off"` is still honoured, from before `preview` existed.
  readonly property bool previewEnabled: root.setting("preview", true) !== false
    && String(root.setting("previewMode", "capture")) !== "off"
  readonly property string previewMode: Logic.previewMode(root.setting("previewMode", "capture"))
  readonly property int previewSize: Util.clamp(Number(root.setting("previewSize", 220)), 100, 800)
  readonly property bool addButtonEnabled: root.setting("addButton", true) !== false
  readonly property bool renameEnabled: root.setting("rename", true) !== false
  readonly property bool reorderEnabled: root.setting("reorder", true) !== false
  readonly property string renumberLua: String(root.setting("renumberLua", ""))
  readonly property bool middleClickMove: root.setting("middleClickMove", true) !== false
  readonly property bool scrollSwitch: root.setting("scrollSwitch", true) !== false
  readonly property bool animate: root.setting("animate", true) !== false

  // Theme. The bar's own colors where the host passes them, else the palette.
  readonly property color ink: root.bar ? root.bar.barForeground : Color.bar.text
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  // Text on the pill: the theme's background, unless its foreground reads
  // better on the accent (light themes with a dark accent).
  readonly property color onAccent: Logic.contrast(Color.accent, Color.foreground) > Logic.contrast(Color.accent, Color.background)
    ? Color.foreground : Color.background
  readonly property string fontFamily: root.bar && root.bar.fontFamily !== "" ? root.bar.fontFamily : Style.font.family

  // The pill sits this far in from the bar's edges, and a button is never
  // narrower than the pill is tall, so a one-digit workspace gets a circle.
  readonly property int pillInset: Math.max(2, Math.round(root.barSize * 0.16))
  readonly property int pillThickness: Math.max(0, root.barSize - root.pillInset * 2)
  readonly property real buttonPadding: Style.spaceReal(9)

  // Hyprland's state, as Logic.hyprState reads it from hyprctl. Quickshell's
  // own workspace objects aren't used: after `hl.dsp.workspace.change_id`
  // (a script renumbering workspaces) Quickshell 0.3.1 keeps stale and
  // duplicate ids, and no refresh clears them.
  property var hypr: Logic.hyprState([], [], [])

  // Set straight from the `workspacev2` event, so the pill moves without
  // waiting for hyprctl, then confirmed by each state read.
  property int focusedId: 0

  // Which workspaces to draw. Only ids (and, for special workspaces, names)
  // are read here, so renaming a regular workspace does not rebuild the
  // buttons; each button follows its own workspace's name. The lists are only
  // replaced when they really change, since a Repeater recreates every button
  // when its model is set.
  property var normalIds: []
  property var specialIds: []

  function applyState(text) {
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      return
    }
    var next = Logic.hyprState(parsed.workspaces, parsed.monitors, parsed.clients)
    root.hypr = next
    if (next.focusedId > 0) root.focusedId = next.focusedId
    root.syncEntries()
  }

  function syncEntries() {
    var next = Logic.entries(root.hypr.workspaces, root.showSpecial)
    if (JSON.stringify(next.normal) !== JSON.stringify(root.normalIds)) {
      root.pillAnimates = false
      root.normalIds = next.normal
      pillSettle.restart()
    }
    if (JSON.stringify(next.special) !== JSON.stringify(root.specialIds)) root.specialIds = next.special
  }

  onShowSpecialChanged: root.syncEntries()
  Component.onCompleted: root.refresh()

  function workspaceById(id) {
    var list = root.hypr.workspaces
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i]
    }
    return null
  }

  function hasWindows(id) {
    var ws = root.workspaceById(id)
    return ws !== null && ws.windows > 0
  }

  // Shown on another monitor. The focused monitor's workspace is left out,
  // so the one just left doesn't flash an outline before hyprctl catches up.
  function isShownElsewhere(id) {
    return id !== root.focusedId && root.hypr.elsewhereIds.indexOf(id) !== -1
  }

  function isSpecialOpen(name) {
    return root.hypr.openSpecials.indexOf(name) !== -1
  }

  // Windows that asked for attention, by address. Hyprland sends `urgent`
  // once; a window stops counting when it's closed, or when its workspace is
  // focused.
  property var urgentWindows: ({})
  readonly property var urgentIds: Logic.urgentIds(root.urgentWindows, root.hypr.windowWorkspace, root.focusedId)

  function isUrgent(id) {
    return root.urgentIds.indexOf(id) !== -1
  }

  function setUrgent(addr, on) {
    var key = Logic.address(addr)
    if (key === "" || !!root.urgentWindows[key] === on) return
    var next = {}
    for (var k in root.urgentWindows) if (k !== key) next[k] = root.urgentWindows[k]
    if (on) next[key] = true
    root.urgentWindows = next
  }

  function clearUrgentOn(id) {
    var next = {}
    var changed = false
    for (var k in root.urgentWindows) {
      if (root.hypr.windowWorkspace[k] === id) changed = true
      else next[k] = root.urgentWindows[k]
    }
    if (changed) root.urgentWindows = next
  }

  onFocusedIdChanged: root.clearUrgentOn(root.focusedId)

  // Reading Hyprland's state: one hyprctl round for workspaces, monitors and
  // windows, after a burst of events has settled. A read asked for while one
  // is running is done once it finishes.
  property bool refreshPending: false

  function refresh() {
    refreshDebounce.restart()
  }

  Timer {
    id: refreshDebounce
    interval: 25
    onTriggered: {
      if (stateReader.running) root.refreshPending = true
      else stateReader.running = true
    }
  }

  Process {
    id: stateReader
    command: ["sh", "-c",
      "printf '{\"workspaces\":%s,\"monitors\":%s,\"clients\":%s}' "
      + "\"$(hyprctl -j workspaces)\" \"$(hyprctl -j monitors)\" \"$(hyprctl -j clients)\""]
    stdout: StdioCollector {
      onStreamFinished: root.applyState(this.text)
    }
    onExited: {
      if (!root.refreshPending) return
      root.refreshPending = false
      refreshDebounce.restart()
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = String(event.name || "")
      var data = String(event.data || "")
      if (name === "workspacev2") {
        // "<id>,<name>", for the focused monitor.
        var id = parseInt(data, 10)
        if (id > 0) root.focusedId = id
        root.refresh()
      } else if (name === "urgent") {
        root.setUrgent(data, true)
        root.refresh()
      } else if (name === "closewindow") {
        root.setUrgent(data, false)
        root.refresh()
      } else if (name === "createworkspacev2" || name === "destroyworkspacev2" || name === "renameworkspace"
          || name === "changeworkspaceid" || name === "moveworkspacev2" || name === "focusedmon"
          || name === "activespecial" || name === "openwindow" || name === "movewindowv2"
          || name === "changefloatingmode" || name === "fullscreen"
          || name === "monitoraddedv2" || name === "monitorremovedv2") {
        root.refresh()
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

  // A new workspace, one past the last, and go there. Hyprland makes it on
  // focus, and drops it again when it's left empty.
  function createWorkspace() {
    root.activate(Logic.nextId(root.normalIds))
  }

  // Ask for a name in Omarchy's input prompt, then have Hyprland rename the
  // workspace. An empty name puts its number back.
  function renameWorkspace(id) {
    if (!root.bar || id <= 0) return
    var ws = root.workspaceById(id)
    var prompt = "Rename " + Logic.title(id, ws ? ws.name : "")
    root.bar.run("name=$(omarchy-menu-input " + Util.shellQuote(prompt) + " --width 450) || exit 0; "
      + "name=${name//]==]/}; "
      + "hyprctl eval \"hl.dispatch(hl.dsp.workspace.rename({ workspace = '" + id + "', name = [==[${name:-" + id + "}]==] }))\"")
  }

  // Move workspace `id` to position `index` along the bar, by renumbering
  // the workspaces in between (Logic.reorderPlan), in one `hyprctl eval`.
  function reorder(id, index) {
    if (!root.bar) return
    var steps = Logic.reorderPlan(root.normalIds, id, index)
    if (steps.length === 0) return
    root.bar.run("hyprctl eval " + Util.shellQuote(Logic.renumberScript(steps, root.renumberLua)))
    root.refresh()
  }

  // Dragging a workspace: the button follows the pointer along the bar, and
  // a marker shows where it would land.
  property int dragId: 0
  property int dropAt: -1

  function otherButtons(id) {
    var out = []
    for (var i = 0; i < normalRepeater.count; i++) {
      var item = normalRepeater.itemAt(i)
      if (item && item.workspaceId !== id) out.push(item)
    }
    return out
  }

  function beginDrag(button) {
    root.hidePreview()
    button.hideOwnTooltip()
    root.dragId = button.workspaceId
    root.moveDrag(button)
  }

  function moveDrag(button) {
    var others = root.otherButtons(button.workspaceId)
    var centres = []
    for (var i = 0; i < others.length; i++) {
      centres.push(root.vertical ? others[i].y + others[i].height / 2 : others[i].x + others[i].width / 2)
    }
    var at = root.vertical
      ? button.y + button.dragOffset + button.height / 2
      : button.x + button.dragOffset + button.width / 2
    root.dropAt = Logic.dropIndex(centres, at)
  }

  function endDrag(button) {
    var id = root.dragId
    var index = root.dropAt
    root.dragId = 0
    root.dropAt = -1
    button.dragOffset = 0
    if (id !== 0 && index >= 0) root.reorder(id, index)
  }

  // Where the drop marker goes, along the bar: in the gap before the button
  // the dragged one would land in front of, or after the last.
  readonly property real dropMarkerPos: {
    if (root.dragId === 0 || root.dropAt < 0) return -1
    var others = root.otherButtons(root.dragId)
    if (others.length === 0) return -1
    var gap = root.vertical ? grid.rowSpacing : grid.columnSpacing
    if (root.dropAt < others.length) {
      var next = others[root.dropAt]
      return (root.vertical ? next.y : next.x) - gap / 2
    }
    var last = others[others.length - 1]
    return (root.vertical ? last.y + last.height : last.x + last.width) + gap / 2
  }

  property int wheelAccum: 0

  function handleWheel(delta) {
    if (!root.scrollSwitch) return
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
    if (!root.previewEnabled || root.dragId !== 0 || !root.hasWindows(id)) return
    // Windows move and resize without telling anyone; get their places now.
    root.refresh()
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

  // The workspace's monitor in logical pixels. A special workspace that has
  // never been shown has no monitor; the focused one stands in.
  readonly property var previewScreen: {
    if (root.shownId === 0) return null
    var ws = root.previewWorkspace
    var m = ws && root.hypr.monitors[ws.monitor] ? root.hypr.monitors[ws.monitor] : root.hypr.monitors[root.hypr.focusedMonitor]
    return m ? Logic.logicalMonitor(m) : null
  }

  // The windows the card draws. Only replaced when they really change: a new
  // model recreates every tile, and with it every screenshot.
  property var previewWindows: []

  function syncPreview() {
    var list = []
    if (root.shownId !== 0) {
      var clients = root.hypr.clients
      var here = []
      for (var i = 0; i < clients.length; i++) {
        if (Number(clients[i].workspace.id) === root.shownId) here.push(clients[i])
      }
      list = Logic.previewLayout(here, 12)
    }
    if (JSON.stringify(list) !== JSON.stringify(root.previewWindows)) root.previewWindows = list
  }

  onShownIdChanged: root.syncPreview()
  onHyprChanged: {
    root.clearUrgentOn(root.focusedId)
    root.syncPreview()
  }

  // Quickshell's handle on a window, for the screenshot. Toplevels are keyed
  // by address, which, unlike its workspace ids, never goes stale.
  function toplevelFor(addr) {
    var key = Logic.address(addr)
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      if (Logic.address(all[i].address) === key) return all[i]
    }
    return null
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
      if (!item) continue
      out.push({
        id: item.workspaceId,
        x: item.x + (root.vertical ? 0 : item.dragOffset),
        y: item.y + (root.vertical ? item.dragOffset : 0),
        width: item.width,
        height: item.height
      })
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

    // Not while a drag moves it: it has to keep up with the pointer.
    readonly property bool animates: root.animate && root.pillAnimates && root.dragId === 0

    Behavior on x { enabled: pill.animates; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    Behavior on y { enabled: pill.animates; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    Behavior on width { enabled: pill.animates; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: pill.animates; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 200 } }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.normalIds.length + root.specialIds.length
      + (addButton.visible ? 1 : 0) + (separator.visible ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: normalRepeater
      model: root.normalIds
      WorkspaceButton { required property int modelData; host: root; workspaceId: modelData }
    }

    WidgetButton {
      id: addButton
      bar: root.bar
      text: "+"
      hasVisualContent: root.addButtonEnabled
      fontFamily: root.fontFamily
      foreground: Util.alpha(root.ink, addButton.tooltipHovered ? 1 : 0.55)
      tooltipText: "New workspace"
      fixedWidth: root.vertical ? root.barSize : root.pillThickness
      fixedHeight: root.vertical ? root.pillThickness : root.barSize
      onPressed: function(which) { if (which === Qt.LeftButton) root.createWorkspace() }
      onWheelMoved: function(delta) { root.handleWheel(delta) }

      Rectangle {
        anchors.centerIn: parent
        width: root.pillThickness
        height: root.pillThickness
        radius: width / 2
        color: Util.alpha(root.ink, 0.10)
        opacity: addButton.tooltipHovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }
    }

    Rectangle {
      id: separator
      visible: (root.normalIds.length > 0 || addButton.visible) && root.specialIds.length > 0
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

  // Where a dragged workspace would land.
  Rectangle {
    visible: root.dropMarkerPos >= 0
    x: root.vertical ? root.pillInset : Math.round(root.dropMarkerPos - width / 2)
    y: root.vertical ? Math.round(root.dropMarkerPos - height / 2) : root.pillInset
    width: root.vertical ? root.pillThickness : Math.max(2, Style.space(2))
    height: root.vertical ? Math.max(2, Style.space(2)) : root.pillThickness
    radius: Math.min(width, height) / 2
    color: root.accent
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
      root.refresh()
      root.hoverAnchor = anchor ? anchor : grid
      root.hoverId = n
    }
    function unpreview(): void { root.hidePreview() }
    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
    function resync(): void { root.refresh() }
    function add(): void { root.createWorkspace() }
    function rename(id: string): void { root.renameWorkspace(parseInt(id, 10) || root.focusedId) }
    function move(id: string, position: string): void {
      // `position` counts from 1, as the bar reads left to right.
      root.reorder(parseInt(id, 10) || 0, (parseInt(position, 10) || 1) - 1)
    }
  }
}
