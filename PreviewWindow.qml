import QtQuick
import Quickshell.Wayland
import qs.Commons

// One window in the preview, where Hyprland has it, scaled by `s`.
//
// In capture mode it is a single screenshot of the window (ScreencopyView on
// the toplevel's Wayland handle; a live feed per window would cost far too
// much for a hover). With icons mode, or when no frame arrives, it is a
// tinted block with the app's icon, which never shows window contents.
Rectangle {
  id: tile

  required property var host
  required property var win
  required property real s
  required property real originX
  required property real originY
  property bool active: false

  readonly property var toplevel: host.toplevelFor(win.address)
  readonly property bool wantsCapture: host.previewMode === "capture" && !!toplevel && !!toplevel.wayland
  // A capture gets this long to deliver a frame before the icon stands in.
  property bool settled: false
  readonly property bool captured: wantsCapture && shot.hasContent
  readonly property bool showBlock: !wantsCapture || (settled && !shot.hasContent)
  readonly property string icon: host.iconFor(win.cls)

  x: Math.round((win.x - originX) * s)
  y: Math.round((win.y - originY) * s)
  width: Math.max(3, Math.round(win.width * s))
  height: Math.max(3, Math.round(win.height * s))
  radius: Math.min(Style.space(4), Style.cornerRadius)
  color: showBlock ? Util.alpha(Color.popups.background, 0.85) : Color.popups.background
  border.width: active ? 2 : 1
  border.color: active ? Color.accent : Util.alpha(Color.popups.text, win.floating ? 0.5 : 0.25)
  clip: true

  Timer {
    interval: 600
    running: tile.wantsCapture
    onTriggered: tile.settled = true
  }

  ScreencopyView {
    id: shot
    anchors.fill: parent
    anchors.margins: tile.border.width
    visible: tile.captured
    captureSource: tile.wantsCapture ? tile.toplevel.wayland : null
    live: false
    paintCursor: false
  }

  Column {
    visible: tile.showBlock
    anchors.centerIn: parent
    spacing: Style.space(4)

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: tile.icon !== "" && tile.width >= Style.space(20) && tile.height >= Style.space(20)
      width: Math.min(Style.space(32), Math.round(Math.min(tile.width, tile.height) * 0.45))
      height: width
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.max(1, width * Screen.devicePixelRatio)
      sourceSize.height: Math.max(1, height * Screen.devicePixelRatio)
      source: tile.icon
      asynchronous: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: text !== "" && tile.width >= Style.space(64) && tile.height >= Style.space(48)
      width: Math.min(implicitWidth, tile.width - Style.space(8))
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: tile.win.cls
      color: Util.alpha(Color.popups.text, 0.75)
      font.family: tile.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // The app's icon in the corner of a screenshot, so a wall of text still
  // says which app it is.
  Image {
    visible: tile.captured && tile.icon !== "" && tile.width >= Style.space(44) && tile.height >= Style.space(32)
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(3)
    width: Style.space(14)
    height: width
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.max(1, width * Screen.devicePixelRatio)
    sourceSize.height: Math.max(1, height * Screen.devicePixelRatio)
    source: tile.icon
    asynchronous: true
  }
}
