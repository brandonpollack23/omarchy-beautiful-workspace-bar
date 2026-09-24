import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// The hover preview: the workspace's name and window count over a small copy
// of its monitor, with the wallpaper behind and each window where Hyprland
// has put it.
PopupCard {
  id: card
  required property var host

  anchorItem: host.hoverAnchor ? host.hoverAnchor : host
  owner: host.hoverOwner
  bar: host.bar
  triggerMode: "hover"
  open: host.hoverId !== 0 && host.previewScreen !== null && host.previewWindows.length > 0

  // fittedContentHeight adds the padding and border, fittedContentWidth
  // doesn't, so the horizontal inset is added here.
  readonly property real horizontalInset: card.padding * 2 + Border.left(card.borderSpec) + Border.right(card.borderSpec)
  readonly property real wellWidth: Math.min(Style.space(360), Math.max(1, card.availableCardWidth - card.horizontalInset))
  readonly property real wellHeight: host.previewScreen && host.previewScreen.width > 0
    ? Math.round(card.wellWidth * host.previewScreen.height / host.previewScreen.width)
    : Math.round(card.wellWidth * 9 / 16)

  contentWidth: card.fittedContentWidth(card.wellWidth + card.horizontalInset)
  contentHeight: card.fittedContentHeight(header.height + column.spacing + card.wellHeight)

  property int wallpaperStamp: 0
  onVisibleChanged: {
    if (card.visible) return
    card.wallpaperStamp++
    if (card.host.hoverId === 0) card.host.shownId = 0
  }
  readonly property string activeAddress: Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address || "") : ""

  Column {
    id: column
    anchors.centerIn: parent
    width: card.wellWidth
    spacing: Style.space(8)

    Item {
      id: header
      width: parent.width
      height: Math.max(title.implicitHeight, count.implicitHeight)

      Text {
        id: title
        anchors.left: parent.left
        anchors.right: count.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: Logic.title(card.host.shownId, card.host.previewWorkspace ? card.host.previewWorkspace.name : "")
        color: Color.popups.text
        font.family: card.host.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: count
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: {
          var n = card.host.previewWindows.length
          var words = n + (n === 1 ? " window" : " windows")
          return card.host.shownId === card.host.focusedId ? words + "  ·  here" : words
        }
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: card.host.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The monitor, scaled down: everything inside is placed in Hyprland's
    // logical coordinates times `s`.
    Rectangle {
      id: well
      width: parent.width
      height: card.wellHeight
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.text, 0.06)
      clip: true

      readonly property real s: card.host.previewScreen && card.host.previewScreen.width > 0
        ? width / card.host.previewScreen.width : 0
      readonly property real originX: card.host.previewScreen ? card.host.previewScreen.x : 0
      readonly property real originY: card.host.previewScreen ? card.host.previewScreen.y : 0

      Image {
        anchors.fill: parent
        // The path is a symlink that `omarchy theme set` and
        // `omarchy background` repoint, so reload it each time the card has
        // closed, ready for the next opening.
        source: Util.fileUrl(Color.stateHome + "/omarchy/current/background") + "#" + card.wallpaperStamp
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.round(well.width * 2)
        asynchronous: true
        cache: false
        smooth: true
      }

      // Dims the wallpaper so the windows stand out.
      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.popups.background, 0.35)
      }

      Repeater {
        model: card.host.previewWindows

        PreviewWindow {
          required property var modelData
          host: card.host
          win: modelData
          s: well.s
          originX: well.originX
          originY: well.originY
          active: modelData.address !== "" && modelData.address === card.activeAddress
        }
      }
    }
  }
}
