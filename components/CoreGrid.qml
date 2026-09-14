import QtQuick
import qs.Commons
import "../Theme.js" as Theme

// Topology-aware core usage grid. Hybrid chips get P / E / LP rows with
// larger P cells; homogeneous chips wrap as a uniform mosaic. SMT siblings
// are already collapsed by Model.coreGridLayout. Fill follows the theme
// accent, urgent at ≥90%.
Item {
  id: root

  property var layout: ({ mode: "uniform", rows: [] })
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family

  readonly property bool hasCells: {
    var rows = root.layout && root.layout.rows ? root.layout.rows : []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].cells && rows[i].cells.length) return true
    }
    return false
  }

  visible: hasCells
  implicitWidth: 200
  implicitHeight: visible ? column.implicitHeight : 0

  function cellSize(kind) {
    if (kind === "performance") return Style.space(12)
    if (kind === "same") return Style.space(10)
    return Style.space(8)
  }

  function kindLabel(kind) {
    if (kind === "performance") return "P"
    if (kind === "efficiency") return "E"
    if (kind === "lowpower") return "LP"
    return ""
  }

  function fillFor(usage) {
    var u = Number(usage) || 0
    return u >= 90 ? root.urgent : root.accent
  }

  function opacityFor(usage) {
    var u = Number(usage) || 0
    if (u < 0) u = 0
    if (u > 100) u = 100
    return 0.18 + 0.82 * (u / 100)
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      text: "CORES"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Repeater {
      model: root.layout && root.layout.rows ? root.layout.rows : []

      delegate: Item {
        id: rowRoot
        required property var modelData
        width: column.width
        implicitHeight: Math.max(kindText.implicitHeight, flow.implicitHeight)

        Text {
          id: kindText
          textFormat: Text.PlainText
          visible: root.layout && root.layout.mode === "hybrid" && root.kindLabel(rowRoot.modelData.kind) !== ""
          text: root.kindLabel(rowRoot.modelData.kind)
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: visible ? Style.space(18) : 0
          horizontalAlignment: Text.AlignRight
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Flow {
          id: flow
          anchors.left: kindText.right
          anchors.leftMargin: kindText.visible ? Style.space(6) : 0
          anchors.right: parent.right
          spacing: Style.space(3)

          Repeater {
            model: rowRoot.modelData && rowRoot.modelData.cells ? rowRoot.modelData.cells : []

            delegate: Rectangle {
              required property var modelData
              width: root.cellSize(rowRoot.modelData ? rowRoot.modelData.kind : "same")
              height: width
              radius: 2
              color: root.fillFor(modelData.usage)
              opacity: root.opacityFor(modelData.usage)
              border.width: 1
              border.color: Theme.trackFor(root.foreground)
            }
          }
        }
      }
    }
  }
}
