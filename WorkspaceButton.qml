import QtQuick
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// One workspace in the bar. The accent pill behind the focused one belongs to
// Workspaces.qml, so it can slide between buttons; this draws everything
// else: the label, a hover wash, a pulsing wash while urgent, and an outline
// when the workspace is on screen without having focus (a special workspace
// that is open, or a workspace shown on another monitor).
WidgetButton {
  id: button

  required property var host
  required property int workspaceId

  readonly property var workspace: host.workspaceById(workspaceId)
  readonly property bool special: workspaceId < 0
  readonly property string wsName: workspace ? workspace.name : ""

  readonly property bool focused: !special && host.focusedId === workspaceId
  readonly property bool shown: special
    ? host.isSpecialOpen(wsName)
    : (workspace !== null && workspace.active && !focused)
  readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
  readonly property bool urgent: workspace !== null && workspace.urgent && !focused

  readonly property string labelText: {
    var text = Logic.label(workspaceId, wsName, host.showNumbers, host.vertical)
    return special && !host.vertical ? "  " + text : text
  }

  bar: host.bar
  text: ""
  labelVisible: false
  hasVisualContent: true
  fontFamily: host.fontFamily

  fixedWidth: host.vertical
    ? host.barSize
    : Math.max(host.pillThickness, Math.round(nameText.implicitWidth + host.buttonPadding * 2))
  fixedHeight: host.vertical
    ? Math.max(host.pillThickness, Math.round(nameText.implicitHeight + Style.spaceReal(6) * 2))
    : host.barSize

  // A preview says more than a tooltip, so the tooltip only shows where there
  // is no preview to open.
  tooltipText: host.previewMode !== "off" && occupied ? "" : Logic.title(workspaceId, wsName)

  onTooltipHoveredChanged: {
    if (tooltipHovered) host.requestPreview(workspaceId, button)
    else host.cancelPreview(workspaceId)
  }

  onPressed: function(which) {
    if (which === Qt.LeftButton) host.activate(workspaceId)
    else if (which === Qt.MiddleButton) host.sendFocusedWindow(workspaceId)
  }
  onWheelMoved: function(delta) { host.handleWheel(delta) }

  // The washes share the pill's shape: inset from the bar's edges on its
  // cross axis, fully rounded.
  component Wash: Rectangle {
    x: button.vertical ? button.host.pillInset : 0
    y: button.vertical ? 0 : button.host.pillInset
    width: button.vertical ? button.host.pillThickness : button.width
    height: button.vertical ? button.height : button.host.pillThickness
    radius: Math.min(width, height) / 2
  }

  Wash {
    color: Util.alpha(button.host.ink, 0.10)
    opacity: button.tooltipHovered && !button.focused ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  Wash {
    id: urgentWash
    color: Util.alpha(button.host.urgentColor, 0.28)
    visible: button.urgent
    opacity: 1

    SequentialAnimation on opacity {
      running: button.urgent
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }

  Wash {
    color: "transparent"
    border.width: 1
    border.color: button.host.accent
    opacity: button.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  Text {
    id: nameText
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: button.labelText
    font.family: button.host.fontFamily
    font.pixelSize: button.fontSize
    font.bold: button.focused
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: button.focused ? button.host.onAccent : (button.urgent ? button.host.urgentColor : button.host.ink)
    // Only the text dims: the pill may be sliding in behind it.
    opacity: button.occupied || button.focused || button.shown || button.urgent ? 1 : 0.5

    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on opacity { NumberAnimation { duration: 140 } }
  }
}
